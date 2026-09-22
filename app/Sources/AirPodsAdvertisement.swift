import Foundation

/// A parsed Apple BLE manufacturer payload.
///
/// AirPods broadcast a "proximity pairing" message (AD type 0x07) whose first
/// value byte is a prefix and whose following two bytes are the model ID
/// (big-endian), e.g. `4c 00 07 04 01 20 36 20` -> 0x2036 (AirPods 5).
struct AirPodsAdvertisement {
    let modelID: UInt16?
    let rawManufacturerData: String
}

enum AirPodsAdvertisementParser {
    static let appleCompanyID: UInt16 = 0x004C
    static let proximityPairingType: UInt8 = 0x07

    static func parse(manufacturerData data: Data) -> AirPodsAdvertisement {
        AirPodsAdvertisement(modelID: modelID(fromManufacturerData: data),
                             rawManufacturerData: hexString(data))
    }

    static func modelID(fromManufacturerData data: Data) -> UInt16? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        guard company == appleCompanyID else { return nil }

        var index = 2
        while index + 1 < bytes.count {
            let type = bytes[index]
            let length = Int(bytes[index + 1])
            let valueStart = index + 2
            let valueEnd = valueStart + length
            guard length > 0, valueEnd <= bytes.count else { return nil }

            if type == proximityPairingType, length >= 3 {
                let high = UInt16(bytes[valueStart + 1])
                let low = UInt16(bytes[valueStart + 2])
                return (high << 8) | low
            }
            index = valueEnd
        }
        return nil
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

/// Maps BLE model IDs to the display names extracted from CoreUARP.
struct AirPodsModelCatalog {
    private struct Table: Decodable {
        struct Model: Decodable {
            let productID: Int?
            let display: String?
        }
        let models: [Model]?
    }

    static let shared = AirPodsModelCatalog(bundle: .main)

    private let displayNames: [UInt16: String]

    init(bundle: Bundle) {
        guard let url = bundle.url(forResource: "Models", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            displayNames = [:]
            return
        }
        displayNames = AirPodsModelCatalog.table(from: data)
    }

    init(jsonData: Data) {
        displayNames = AirPodsModelCatalog.table(from: jsonData)
    }

    static func table(from data: Data) -> [UInt16: String] {
        guard let table = try? JSONDecoder().decode(Table.self, from: data) else {
            return [:]
        }
        var names: [UInt16: String] = [:]
        for model in table.models ?? [] {
            guard let productID = model.productID, let display = model.display,
                  let key = UInt16(exactly: productID) else { continue }
            names[key] = display
        }
        return names
    }

    func displayName(for modelID: UInt16) -> String? {
        displayNames[modelID]
    }

    func isAirPods5(modelID: UInt16) -> Bool {
        (displayNames[modelID] ?? "").hasPrefix("AirPods 5")
    }
}
