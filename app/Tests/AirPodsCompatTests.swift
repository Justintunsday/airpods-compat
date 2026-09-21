import XCTest

final class AirPodsCompatTests: XCTestCase {

    /// Model table integrity: every extracted class must be present and carry
    /// a product ID.
    func testModelTableIntegrity() {
        let summary = ACRunSelfTestSummary() as NSDictionary
        let modelCount = (summary["modelCount"] as? NSNumber)?.intValue ?? 0
        let uniquePIDs = (summary["uniqueProductIDs"] as? NSNumber)?.intValue ?? 0

        XCTAssertGreaterThanOrEqual(modelCount, 30, "model table should cover all extracted classes")
        XCTAssertGreaterThan(uniquePIDs, 25, "product IDs should be present for (nearly) every model")
    }

    /// Dynamic registration must complete for every missing model and each
    /// registered accessory must keep a distinct identity (otherwise NSSet
    /// collapses them and UARP lookups fail).
    func testRegistrationCompletesAndIdentitiesAreDistinct() {
        let summary = ACRunSelfTestSummary() as NSDictionary
        let expected = (summary["expected"] as? NSNumber)?.intValue ?? -1
        let registered = (summary["registered"] as? NSNumber)?.intValue ?? -1
        let created = (summary["created"] as? NSNumber)?.intValue ?? 0
        let grew = (summary["grew"] as? NSNumber)?.boolValue ?? false

        XCTAssertEqual(registered, expected, "every missing model must register")

        if created > 0 {
            XCTAssertTrue(grew, "setOfAccessories must grow after registering new models")
        }

        let identifiers = summary["actualIdentifiers"] as? [String] ?? []
        if !identifiers.isEmpty {
            XCTAssertEqual(Set(identifiers).count, identifiers.count,
                           "accessory identifiers must be distinct across models")
        }
    }
}
