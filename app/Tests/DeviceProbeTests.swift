import XCTest
@testable import AirPodsCompat

final class DeviceProbeTests: XCTestCase {

    private func data(_ hex: String) -> Data {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return Data(bytes)
    }

    /// Real proximity-pairing layout: Apple company ID, type 0x07, then
    /// 0x01 prefix followed by the big-endian model ID.
    func testProximityPairingExtractsModelID() {
        let advertisement = AirPodsAdvertisementParser.parse(manufacturerData: data("4c00070501203620"))
        XCTAssertEqual(advertisement.modelID, 0x2036)
        XCTAssertEqual(advertisement.rawManufacturerData, "4c00070501203620")
    }

    func testAllAirPods5ProductIDsParse() {
        for pid: UInt16 in [0x2036, 0x2030, 0x2037, 0x2032] {
            let hex = String(format: "4c00070501%04x20", pid)
            XCTAssertEqual(AirPodsAdvertisementParser.modelID(fromManufacturerData: data(hex)), pid,
                           "pid \(pid) should parse")
        }
    }

    func testNonAppleManufacturerDataIsIgnored() {
        XCTAssertNil(AirPodsAdvertisementParser.modelID(fromManufacturerData: data("0000070501203620")))
    }

    func testTruncatedPayloadReturnsNil() {
        XCTAssertNil(AirPodsAdvertisementParser.modelID(fromManufacturerData: Data()))
        XCTAssertNil(AirPodsAdvertisementParser.modelID(fromManufacturerData: data("4c00")))
        XCTAssertNil(AirPodsAdvertisementParser.modelID(fromManufacturerData: data("4c0007190120")))
    }

    func testTLVWalkSkipsOtherTypes() {
        let advertisement = AirPodsAdvertisementParser.parse(manufacturerData: data("4c001203010203070501203a20"))
        XCTAssertEqual(advertisement.modelID, 0x203a)
    }

    func testCatalogParsesAirPods5Names() {
        let json = """
        {"models":[
          {"productID":8246,"display":"AirPods 5"},
          {"productID":8240,"display":"AirPods 5 (Wireless Charging)"}
        ]}
        """.data(using: .utf8)!
        let catalog = AirPodsModelCatalog(jsonData: json)
        XCTAssertEqual(catalog.displayName(for: 0x2036), "AirPods 5")
        XCTAssertEqual(catalog.displayName(for: 0x2030), "AirPods 5 (Wireless Charging)")
        XCTAssertTrue(catalog.isAirPods5(modelID: 0x2036))
        XCTAssertNil(catalog.displayName(for: 0x9999))
        XCTAssertFalse(catalog.isAirPods5(modelID: 0x201b))
    }

    func testConnectedDeviceProductIDMapsToModelName() {
        let json = """
        {"models":[{"productID":8246,"display":"AirPods 5"}]}
        """.data(using: .utf8)!
        let catalog = AirPodsModelCatalog(jsonData: json)
        let device = ConnectedBTDevice(
            name: "Tundrey's AirPods",
            address: "1C:77:54:82:30:1C",
            productID: 0x2036,
            vendorID: 0x004C,
            connected: true,
            className: "BluetoothDevice"
        )
        XCTAssertEqual(device.modelName(catalog: catalog), "AirPods 5")
        XCTAssertTrue(device.describe(catalog: catalog).contains("0x2036"))
        XCTAssertTrue(device.describe(catalog: catalog).contains("已连接"))
    }

    /// The host app ships the CoreUARP-extracted table; make sure the AirPods 5
    /// model IDs resolve so on-device detection can print a name.
    func testBundledCatalogCoversAirPods5() {
        let catalog = AirPodsModelCatalog(bundle: .main)
        XCTAssertEqual(catalog.displayName(for: 0x2036), "AirPods 5")
        XCTAssertEqual(catalog.displayName(for: 0x2037), "AirPods 5")
        XCTAssertEqual(catalog.displayName(for: 0x2030), "AirPods 5 (Wireless Charging)")
        XCTAssertEqual(catalog.displayName(for: 0x2032), "AirPods 5 (Wireless Charging)")
    }
}
