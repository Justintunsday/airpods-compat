import XCTest
@testable import AirPodsCompat

final class ConfigurationTests: XCTestCase {
    func testMigrationKeepsLegacyChoicesAndExplicitOff() {
        let preferences: [String: Any] = ["LegacyUIProfile": "pro2", "LegacyIconProfile": "airpods3", "BorrowProfile": "off", "FutureKey": 7]
        let migrated = Prefs.migrate(preferences)
        XCTAssertEqual(migrated["BorrowProfile"] as? String, "off")
        XCTAssertEqual(migrated["LegacyUIProfile"] as? String, "pro2")
        XCTAssertEqual(migrated["FutureKey"] as? Int, 7)
        XCTAssertEqual(migrated["ConfigurationVersion"] as? Int, 2)
        XCTAssertEqual(Prefs.migrate(["BorrowProfile": "airpodspro3"])["BorrowProfile"] as? String, "airpods4anc")
    }
    func testSharedPreferencesWriteReadbackAndDeniedPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.plist")
        try Prefs.save(["Enabled": false], to: url)
        XCTAssertEqual(Prefs.load(from: url)["Enabled"] as? Bool, false)
        XCTAssertThrowsError(try Prefs.save(["Enabled": true], to: directory.appendingPathComponent("missing/blocked.plist")))
    }
    func testNativeRuntimeInventoryIsNotSystemInstallationProof() {
        let adapted = CompatibilitySnapshot(capabilities: ["factory": true, "b768": true], preferences: [:], osMajor: 26)
        XCTAssertEqual(adapted.assessments.first?.status, .unverified)
        XCTAssertTrue(adapted.requestedProfile.contains("0x201b"))
        let native = CompatibilitySnapshot(capabilities: ["b868": true], preferences: [:], osMajor: 26)
        XCTAssertEqual(native.assessments.first?.status, .native)
        XCTAssertEqual(native.assessments.first(where: { $0.id == "独立充电盒电量" })?.status, .unsupported)
    }
}
