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
        if let prefs = NSDictionary(contentsOfFile: path) as? [String: Any] { return prefs }
        // Mirror the tweak: an existing unreadable file disables compatibility.
        return FileManager.default.fileExists(atPath: path) ? ["Enabled": false] : [:]
    }

    static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        ACBoolPreference(load() as NSDictionary, key, defaultValue)
    }

    static var scopeAll: Bool { ACFullModelScope(load() as NSDictionary) }

    static func save(_ prefs: [String: Any]) throws {
        // Do not overwrite an unreadable file with partial/default preferences.
        if FileManager.default.fileExists(atPath: path), NSDictionary(contentsOfFile: path) == nil {
            throw NSError(domain: domain, code: 1, userInfo: [NSLocalizedDescriptionKey: "现有配置无法读取，请先备份并修复配置文件"])
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: prefs, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
