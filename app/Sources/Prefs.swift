import Foundation

/// Mirrors the preference domain read by the AirPodsCompat tweak.
///
/// Rootless jailbreaks (Dopamine/ElleKit) map system paths under `/var/jb`;
/// roothide uses `jbroot` indirection which resolves the same way for us.
enum Prefs {
    static let domain = "com.justintunsday.airpodscompat"

    static var directory: String {
        if FileManager.default.fileExists(atPath: "/var/jb/var/mobile/Library/Preferences") {
            return "/var/jb/var/mobile/Library/Preferences"
        }
        return "/var/mobile/Library/Preferences"
    }

    static var path: String { directory + "/" + domain + ".plist" }

    static func load() -> [String: Any] {
        (NSDictionary(contentsOfFile: path) as? [String: Any]) ?? [:]
    }

    static func save(_ prefs: [String: Any]) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: prefs, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
