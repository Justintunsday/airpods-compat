import Foundation

enum CompatibilityStatus: String {
    case native = "原生"
    case adapted = "已适配"
    case presentationOnly = "仅显示资源"
    case unsupported = "不支持"
    case unverified = "未验证"
}

struct FeatureAssessment: Identifiable {
    let id: String
    let status: CompatibilityStatus
    let detail: String
}

struct CompatibilitySnapshot {
    let capabilities: [String: Any]
    let preferences: [String: Any]
    let osMajor: Int

    init(capabilities: [String: Any] = ACReadPlatformCapabilities(),
         preferences: [String: Any] = Prefs.load(),
         osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.capabilities = capabilities
        self.preferences = preferences
        self.osMajor = osMajor
    }

    var requestedProfile: String {
        if (preferences["Enabled"] as? Bool) == false { return "已关闭" }
        if osMajor < 18 { return "旧版 HeadphoneConfigs · 保留现有配置" }
        if (preferences["BorrowProfile"] as? String) == "off" { return "已关闭" }
        return "AirPods 4 (ANC) · 0x201b"
    }

    var assessments: [FeatureAssessment] {
        let native = capabilities["b868"] as? Bool == true
        return [
            FeatureAssessment(id: "设置与功能选择", status: native ? .native : .unverified,
                detail: native ? "此 App 可见 B868 原生功能类型。" : "目标为 \(requestedProfile)。系统进程中的安装与设备行为需分别验证。"),
            FeatureAssessment(id: "降噪与通透", status: .unverified,
                detail: "保留设备报告与系统限制；不会强制开启硬件功能位。iOS 16 有历史设备验收，当前构建需回归。"),
            FeatureAssessment(id: "路由与电池图标", status: .presentationOnly,
                detail: "在受支持的原生资源工厂内借用图像；不修改音频路由或电量。当前 hook 状态需查看系统记录。"),
            FeatureAssessment(id: "独立充电盒电量", status: .unsupported,
                detail: "尚无已验证的 Case 数据源。Single 记录保持原身份，不生成百分比。"),
            FeatureAssessment(id: "任意 App 图标覆盖", status: .unverified,
                detail: "默认仅显式进程名单。自定义图标和进程内资源选择需要单独证据。")
        ]
    }

    var runtimeRecords: [String] {
        let directory = URL(fileURLWithPath: "/var/mobile/Library/Caches/com.justintunsday.airpodscompat", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "plist" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            let record = Prefs.load(from: url)
            guard let module = record["module"] as? String, let state = record["state"] as? String else { return nil }
            return "\(url.lastPathComponent): \(module)=\(state) · \(record["timestamp"] ?? "?") · build=\(record["build"] ?? "?")"
        }
    }

    func report() -> String {
        var lines = ["AirPodsCompat 兼容性诊断", "时间：\(Date())", "系统：\(ProcessInfo.processInfo.operatingSystemVersionString)",
                     "配置目标：\(requestedProfile)", "活动配置：需系统进程记录与设备验收；App 本地探测不能证明已生效。",
                     "[本 App 可见运行时能力]"]
        lines += capabilities.keys.sorted().map { "\($0)=\(capabilities[$0] ?? false)" }
        lines += assessments.map { "[\($0.status.rawValue)] \($0.id): \($0.detail)" }
        lines += ["[上次系统进程记录；可能过期]"]
        let records = runtimeRecords
        lines += records.isEmpty ? ["未读取到记录（诊断关闭、未安装或沙箱限制）。"] : records
        return lines.joined(separator: "\n")
    }
}
