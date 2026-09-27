import XCTest
@testable import AirPodsCompat

final class SafetyPolicyTests: XCTestCase {
    private func model(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = [
            "model": "A3532", "appleModelNumber": "A3532", "productID": 0x2036,
            "tier": "core", "alternativeAppleModelNumbers": ["A3531"],
            "baseClasses": ["UARPSupportedAccessoryAirPodsBud", "UARPSupportedAccessoryA3064"]
        ]
        overrides.forEach { value[$0.key] = $0.value }
        return value
    }

    func testMissingPreferencesKeepExperimentalRegistrationOff() {
        XCTAssertTrue(ACBoolPreference([:] as NSDictionary, "Enabled", true))
        XCTAssertFalse(ACBoolPreference([:] as NSDictionary, "UARPEnabled", false))
        XCTAssertFalse(ACFullModelScope([:] as NSDictionary))
        XCTAssertFalse(ACBoolPreference(nil, "Enabled", true))
    }

    func testMalformedPreferenceValuesNeverEnableCapabilities() {
        let invalidValues: [Any] = ["true", "YES", "1", 2, -1, NSNull(), [], [:]]
        for value in invalidValues {
            XCTAssertFalse(ACBoolPreference(["UARPEnabled": value] as NSDictionary, "UARPEnabled", true))
        }
        XCTAssertTrue(ACBoolPreference(["UARPEnabled": true] as NSDictionary, "UARPEnabled", false))
        XCTAssertFalse(ACBoolPreference(["UARPEnabled": false] as NSDictionary, "UARPEnabled", true))
        XCTAssertFalse(ACFullModelScope(["Scope": ["all"]] as NSDictionary))
        XCTAssertTrue(ACFullModelScope(["Scope": "all"] as NSDictionary))
    }

    func testValidatedModelsRemoveConcreteFallbacks() {
        let validated = ACValidatedModels([model()] as NSArray)
        XCTAssertEqual(validated.count, 1)
        XCTAssertEqual(validated.first?["baseClasses"] as? [String], ["UARPSupportedAccessoryAirPodsBud"])
    }

    func testMalformedModelTablesAreRejectedWithoutPartialRegistration() {
        let badEntries: [[String: Any]] = [
            model(["model": "../../A3532"]), model(["appleModelNumber": []]),
            model(["productID": "8246"]), model(["productID": true]), model(["productID": 0]),
            model(["productID": 65536]), model(["productID": 8246.5]),
            model(["tier": "unexpected"]), model(["baseClasses": []]),
            model(["baseClasses": ["UARPSupportedAccessoryA3064"]]),
            model(["alternativeAppleModelNumbers": [42]])
        ]
        for invalid in badEntries {
            let valid = model(["model": "A3533", "appleModelNumber": "A3533", "productID": 0x2037])
            XCTAssertTrue(ACValidatedModels([valid, invalid] as NSArray).isEmpty)
        }
        XCTAssertTrue(ACValidatedModels([model(), model()] as NSArray).isEmpty)
        XCTAssertTrue(ACValidatedModels([model(), model(["model": "A3533"])] as NSArray).isEmpty)
        XCTAssertTrue(ACValidatedModels([NSNull()] as NSArray).isEmpty)
        XCTAssertTrue(ACValidatedModels("bad input").isEmpty)
    }

    func testDisplayNamesRejectMalformedAndAmbiguousProductIDs() {
        let names = ACValidatedDisplayNames(["8246": "AirPods 5"] as NSDictionary)
        XCTAssertEqual(names[NSNumber(value: 0x2036)], "AirPods 5")
        let invalidNames: [[String: Any]] = [
            ["8246x": "bad"], ["0": "bad"], ["65536": "bad"],
            ["8246": []], ["8246": ""], ["8246": "one", "08246": "two"]
        ]
        for invalid in invalidNames {
            XCTAssertTrue(ACValidatedDisplayNames(invalid as NSDictionary).isEmpty)
        }
    }

    func testRuntimeProbeBoxesScalarsAndPreservesObjects() {
        let fixture = ACMakeScalarProbeFixture()
        XCTAssertEqual((ACReadNoArgumentValue(fixture, NSSelectorFromString("isConnected")) as? NSNumber)?.boolValue, true)
        XCTAssertEqual((ACReadNoArgumentValue(fixture, NSSelectorFromString("productID")) as? NSNumber)?.uint32Value, 0x2036)
        XCTAssertEqual((ACReadNoArgumentValue(fixture, NSSelectorFromString("signedValue")) as? NSNumber)?.int64Value, -42)
        XCTAssertEqual(ACReadNoArgumentValue(fixture, NSSelectorFromString("name")) as? String, "AirPods fixture")
    }

    func testRuntimeProbeSkipsUnknownABIsArgumentsAndExceptions() {
        let fixture = ACMakeScalarProbeFixture()
        for selector in ["bounds", "echo:", "missingSelector", "throwsValue"] {
            XCTAssertNil(ACReadNoArgumentValue(fixture, NSSelectorFromString(selector)))
        }
        XCTAssertTrue(ACMethodMatches(fixture, NSSelectorFromString("name"), 64, 2, 0)) // '@'
        XCTAssertFalse(ACMethodMatches(fixture, NSSelectorFromString("isConnected"), 64, 2, 0))
        XCTAssertTrue(ACMethodMatches(fixture, NSSelectorFromString("echo:"), 64, 3, 64))
        XCTAssertFalse(ACMethodMatches(fixture, NSSelectorFromString("echo:"), 64, 3, 73)) // 'I'
    }

    func testProbeNumbersDistinguishDecimalFromHexAndRejectAmbiguity() {
        XCTAssertEqual(ACProbeUnsignedNumber("8246")?.uint32Value, 0x2036)
        XCTAssertEqual(ACProbeUnsignedNumber("0x2036")?.uint32Value, 0x2036)
        XCTAssertEqual(ACProbeUnsignedNumber("0X2036")?.uint32Value, 0x2036)
        XCTAssertEqual(ACProbeUnsignedNumber(NSNumber(value: 8246))?.uint32Value, 0x2036)
        let invalidValues: [Any] = ["8246tail", "203a", "-1", "+1", " 8246", "0x", "0x100000000", "4294967296", -1, 8246.5, []]
        for value in invalidValues { XCTAssertNil(ACProbeUnsignedNumber(value)) }
    }
}
