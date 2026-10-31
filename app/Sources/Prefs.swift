import Foundation
import Combine

enum Prefs {
    static let domain = "com.justintunsday.airpodscompat"
    static let directory = "/var/mobile/Library/Preferences"
    static var path: String { directory + "/" + domain + ".plist" }
    static func load(from url: URL = URL(fileURLWithPath: path)) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let preferences = value as? [String: Any] else { return [:] }
        return preferences
    }
    static func migrate(_ preferences: [String: Any]) -> [String: Any] {
        var result = preferences
        // Preserve legacy Settings/icon values and unknown keys.
        result["BorrowProfile"] = (preferences["BorrowProfile"] as? String) == "off" ? "off" : "airpods4anc"
        result["ConfigurationVersion"] = 2
        return result
    }
    static func data(_ preferences: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: migrate(preferences), format: .xml, options: 0)
    }
    static func save(_ preferences: [String: Any], to url: URL = URL(fileURLWithPath: path)) throws {
        // Real I/O and readback determine access, including sandbox restrictions.
        let normalized = migrate(preferences)
        try data(normalized).write(to: url, options: .atomic)
        guard NSDictionary(dictionary: load(from: url)).isEqual(to: normalized) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

final class ConfigurationManager: ObservableObject {
    @Published private(set) var values = Prefs.migrate(Prefs.load())
    @Published private(set) var status = "配置尚未应用。普通沙箱 App 可导出配置，在越狱设备用 acprefs 导入。"
    func bool(_ key: String, default fallback: Bool = true) -> Bool {
        (values[key] as? Bool) ?? fallback
    }
    func string(_ key: String, default fallback: String) -> String {
        (values[key] as? String) ?? fallback
    }
    func set(_ key: String, _ value: Any) {
        values[key] = value
        status = "配置已修改，等待应用或导出。"
    }
    func apply() {
        do {
            try Prefs.save(values)
            status = "共享配置已写入并读回验证。重启受影响进程后生效。"
        } catch {
            status = "无法写入共享配置：\(error.localizedDescription)。请导出配置后用 acprefs 导入。"
        }
    }
    func reload() {
        values = Prefs.migrate(Prefs.load())
        status = "已重新读取可访问的配置。系统生效状态见诊断记录。"
    }
}
