import AVFoundation
import Combine
import CoreBluetooth
import Foundation

struct NearbyBLEDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let modelID: UInt16?
    let modelName: String?
    let rawManufacturerData: String
    let advertisementDump: String
    let lastSeen: Date

    var isAirPods5: Bool {
        modelName?.hasPrefix("AirPods 5") ?? false
    }

    var modelDescription: String {
        guard let modelID else {
            if name.localizedCaseInsensitiveContains("airpods") {
                return "未识别到 Apple 近场配对型号（已连接或未广播配对包时常见，可开盖后重扫）"
            }
            return "未识别到 Apple 近场配对型号"
        }
        let hex = String(format: "0x%04x", modelID)
        return modelName.map { "\($0)（\(hex)）" } ?? "未知型号 \(hex)"
    }
}

struct ConnectedBTDevice: Identifiable {
    let id = UUID()
    let name: String
    let address: String?
    let productID: UInt16?
    let vendorID: UInt16?
    let connected: Bool
    let className: String

    func modelName(catalog: AirPodsModelCatalog) -> String? {
        productID.flatMap { catalog.displayName(for: $0) }
    }

    func describe(catalog: AirPodsModelCatalog) -> String {
        var parts: [String] = [name]
        if let model = modelName(catalog: catalog), let productID {
            parts.append(String(format: "%@（0x%04x）", model, productID))
        } else if let productID {
            parts.append(String(format: "pid=0x%04x", productID))
        }
        if let vendorID {
            parts.append(String(format: "vid=0x%04x", vendorID))
        }
        if let address {
            parts.append(address)
        }
        parts.append(connected ? "已连接" : "已配对")
        parts.append(className)
        return parts.joined(separator: " · ")
    }
}

/// Detects the currently connected / nearby headphones without a jailbreak:
///  - audio route (AVAudioSession) shows connected audio devices by name
///  - BLE scan shows nearby AirPods together with the broadcast model ID
///  - private BluetoothManager enumeration provides product IDs of connected
///    devices, which identifies units that no longer broadcast pairing packets
final class DeviceProbe: NSObject, ObservableObject {
    @Published var bluetoothState: String = "未初始化"
    @Published var isScanning = false
    @Published var audioOutputs: [String] = []
    @Published var audioInputs: [String] = []
    @Published var nearby: [NearbyBLEDevice] = []
    @Published var connectedDevices: [ConnectedBTDevice] = []
    @Published var bluetoothProbeStatus: String?
    @Published var lastError: String?

    private var central: CBCentralManager?
    private var discovered: [UUID: NearbyBLEDevice] = [:]
    private let catalog = AirPodsModelCatalog.shared

    var detectedAirPods5: Bool {
        nearby.contains { $0.isAirPods5 }
            || connectedDevices.contains { $0.modelName(catalog: catalog)?.hasPrefix("AirPods 5") ?? false }
    }

    func startScan() {
        lastError = nil
        refreshAudioRoute()
        refreshConnectedDevices()
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            beginScanIfReady()
        }
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    func clearNearby() {
        discovered.removeAll()
        nearby = []
    }

    func refreshAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        audioOutputs = session.currentRoute.outputs.map { output in
            "\(output.portName) · \(output.portType.rawValue) · uid=\(output.uid)"
        }
        if audioOutputs.isEmpty {
            audioOutputs = ["（当前无音频输出，设备可能未连接或未在播放）"]
        }
        audioInputs = (session.availableInputs ?? []).map { input in
            "\(input.portName) · \(input.portType.rawValue)"
        }
    }

    func refreshConnectedDevices() {
        let entries = ACProbeBluetoothDevices()
        bluetoothProbeStatus = ACProbeBluetoothStatus()
        connectedDevices = entries.map { entry in
            ConnectedBTDevice(
                name: entry["name"] as? String ?? "(未知名称)",
                address: entry["address"] as? String,
                productID: (entry["productID"] as? NSNumber).flatMap { UInt16(exactly: $0.intValue) },
                vendorID: (entry["vendorID"] as? NSNumber).flatMap { UInt16(exactly: $0.intValue) },
                connected: (entry["connected"] as? NSNumber)?.boolValue ?? false,
                className: entry["className"] as? String ?? "?"
            )
        }
    }

    func report() -> String {
        var lines: [String] = []
        lines.append("AirPodsCompat 设备探测")
        lines.append("时间：\(Date())")
        lines.append("蓝牙状态：\(bluetoothState)")
        lines.append("")
        lines.append("[音频路由 - 输出]")
        lines.append(contentsOf: audioOutputs.map { "  \($0)" })
        if !audioInputs.isEmpty {
            lines.append("[音频路由 - 输入]")
            lines.append(contentsOf: audioInputs.map { "  \($0)" })
        }
        lines.append("")
        lines.append("[已连接/已配对设备（私有 BluetoothManager）]")
        lines.append("  状态：\(bluetoothProbeStatus ?? "未知")")
        for device in connectedDevices {
            lines.append("  \(device.describe(catalog: catalog))")
        }
        lines.append("")
        lines.append("[附近 BLE 设备]")
        if nearby.isEmpty {
            lines.append("  （无）")
        } else {
            for device in nearby {
                lines.append("  \(device.name) rssi=\(device.rssi)dBm \(device.modelDescription)")
                if !device.rawManufacturerData.isEmpty {
                    lines.append("    mfr=\(device.rawManufacturerData)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func beginScanIfReady() {
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    private func ingest(name: String?, rssi: Int, advertisement: [String: Any], id: UUID) {
        let manufacturerData = advertisement[CBAdvertisementDataManufacturerDataKey] as? Data
        let parsed = manufacturerData.map { AirPodsAdvertisementParser.parse(manufacturerData: $0) }
        let modelID = parsed?.modelID
        let modelName = modelID.flatMap { catalog.displayName(for: $0) }
        let advertisedName = advertisement[CBAdvertisementDataLocalNameKey] as? String
        let device = NearbyBLEDevice(
            id: id,
            name: name ?? advertisedName ?? "(无名称)",
            rssi: rssi,
            modelID: modelID,
            modelName: modelName,
            rawManufacturerData: parsed?.rawManufacturerData ?? "",
            advertisementDump: dumpAdvertisement(advertisement),
            lastSeen: Date()
        )
        discovered[id] = device
        nearby = discovered.values.sorted { $0.rssi > $1.rssi }
    }

    private func dumpAdvertisement(_ advertisement: [String: Any]) -> String {
        advertisement.keys.sorted().map { key in
            let value = advertisement[key]
            let text: String
            if let data = value as? Data {
                text = AirPodsAdvertisementParser.hexString(data)
            } else if let list = value as? [Any] {
                text = list.map { "\($0)" }.joined(separator: ",")
            } else {
                text = "\(value ?? "")"
            }
            return "\(key)=\(text)"
        }.joined(separator: "\n")
    }
}

extension DeviceProbe: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothState = "蓝牙可用"
            beginScanIfReady()
        case .poweredOff:
            bluetoothState = "蓝牙已关闭"
        case .unauthorized:
            bluetoothState = "蓝牙权限被拒绝（设置 → 隐私 → 蓝牙）"
        case .unsupported:
            bluetoothState = "本机不支持 BLE（模拟器）"
        default:
            bluetoothState = "未知状态 \(central.state.rawValue)"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        ingest(name: peripheral.name, rssi: RSSI.intValue, advertisement: advertisementData,
               id: peripheral.identifier)
    }
}
