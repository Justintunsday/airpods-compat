import SwiftUI
import UIKit

struct DeviceProbeView: View {
    @StateObject private var probe = DeviceProbe()

    var body: some View {
        List {
            Section(footer: Text("探测只在本机进行，不上传任何数据。BLE 扫描需要蓝牙权限。")) {
                Button {
                    probe.startScan()
                } label: {
                    Label(probe.isScanning ? "扫描中…" : "开始探测", systemImage: "dot.radiowaves.left.and.right")
                }
                Button("停止扫描") { probe.stopScan() }
                Button("清空附近列表") { probe.clearNearby() }
            }

            Section(header: Text("状态")) {
                Text(probe.bluetoothState)
                if let error = probe.lastError {
                    Text(error).foregroundColor(.red)
                }
                if probe.detectedAirPods5 {
                    Label("已探测到 AirPods 5", systemImage: "checkmark.seal.fill")
                        .foregroundColor(.green)
                }
            }

            Section(header: Text("音频路由（已连接设备）")) {
                ForEach(probe.audioOutputs, id: \.self) { line in
                    Text(line).font(.footnote)
                }
                if !probe.audioInputs.isEmpty {
                    ForEach(probe.audioInputs, id: \.self) { line in
                        Text(line).font(.caption).foregroundColor(.secondary)
                    }
                }
                Button("刷新音频路由") { probe.refreshAudioRoute() }
            }

            Section(header: Text("附近 BLE 设备"), footer: Text("AirPods 会在近场配对广播里携带型号 ID，可据此确认系统/固件上报的型号。")) {
                if probe.nearby.isEmpty {
                    Text("尚未发现设备").foregroundColor(.secondary)
                }
                ForEach(probe.nearby) { device in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(device.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(device.modelDescription)
                            .font(.caption)
                            .foregroundColor(device.isAirPods5 ? .green : .secondary)
                        if !device.rawManufacturerData.isEmpty {
                            Text(device.rawManufacturerData)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section(header: Text("已连接设备（私有 API，尽力）"), footer: Text("越狱/特定沙箱下可读取；失败时只影响本区块。")) {
                if probe.privateDevices.isEmpty {
                    Text("未枚举").foregroundColor(.secondary)
                }
                ForEach(probe.privateDevices, id: \.self) { line in
                    Text(line).font(.footnote)
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = probe.report()
                } label: {
                    Label("复制探测报告", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .disabled(probe.nearby.isEmpty && probe.audioOutputs.isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设备探测")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { probe.refreshAudioRoute() }
    }
}

struct DeviceProbeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { DeviceProbeView() }
    }
}
