import SwiftUI

struct ModelInfo: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private enum BorrowProfile: String, CaseIterable, Identifiable {
    case airpods4anc, airpodspro2, airpodspro3, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .airpods4anc: return "AirPods 4 (ANC) · 默认"
        case .airpodspro2: return "AirPods Pro 2"
        case .airpodspro3: return "AirPods Pro 3"
        case .off: return "关闭设置页借用"
        }
    }
}

struct ContentView: View {
    @State private var enabled: Bool = (Prefs.load()["Enabled"] as? Bool) ?? true
    @State private var uarpEnabled: Bool = (Prefs.load()["UARPEnabled"] as? Bool) ?? true
    @State private var scopeAll: Bool = (Prefs.load()["Scope"] as? String) == "all"
    @State private var borrowProfile: BorrowProfile = BorrowProfile(rawValue: Prefs.load()["BorrowProfile"] as? String ?? "") ?? .airpods4anc
    @State private var status: String = ""

    private let models: [ModelInfo] = [
        ModelInfo(title: "AirPods 5", detail: "A3531 / A3532 / A3533 · case A3529 / A3530"),
        ModelInfo(title: "AirPods Pro 3", detail: "A3063 / A3064 / A3065 · case A3122"),
        ModelInfo(title: "AirPods 4 / 4 (ANC)", detail: "A3050…A3057 · cases A3058 / A3059"),
        ModelInfo(title: "AirPods Max 2", detail: "A3454"),
    ]

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("开关")) {
                    Toggle("启用移植", isOn: Binding(
                        get: { enabled },
                        set: { value in
                            if savePreference("Enabled", value: value) { enabled = value }
                        }
                    ))
                    Toggle("UARP 配件注册", isOn: Binding(
                        get: { uarpEnabled },
                        set: { value in
                            if savePreference("UARPEnabled", value: value) { uarpEnabled = value }
                        }
                    ))
                    if !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(status.hasPrefix("保存失败") ? .red : .secondary)
                    }
                }

                Section(header: Text("注册范围"), footer: Text("默认只注册本机缺失的新代型号（更安全）。全部型号包含 Beats/老型号。")) {
                    Toggle("仅新代型号（推荐）", isOn: Binding(
                        get: { !scopeAll },
                        set: { value in setScope(all: !value) }
                    ))
                    Toggle("包含全部型号", isOn: Binding(
                        get: { scopeAll },
                        set: { value in setScope(all: value) }
                    ))
                }

                Section(header: Text("AirPods 5 设置页"),
                        footer: Text("iOS 26.x 借用系统现有的特性页；图标、文案与可用行可能与 AirPods 5 不符。iOS 27 原生支持时自动跳过。")) {
                    Picker("借用目标", selection: Binding(
                        get: { borrowProfile },
                        set: { value in
                            if savePreference("BorrowProfile", value: value.rawValue) {
                                borrowProfile = value
                            }
                        }
                    )) {
                        ForEach(BorrowProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                }

                Section(header: Text("覆盖的型号")) {
                    ForEach(models) { model in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.title).font(.headline)
                            Text(model.detail).font(.footnote).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section(header: Text("诊断")) {
                    NavigationLink {
                        SelfTestView()
                    } label: {
                        Label("运行自检（无需越狱）", systemImage: "stethoscope")
                    }

                    NavigationLink {
                        DeviceProbeView()
                    } label: {
                        Label("设备探测（连接检测）", systemImage: "dot.radiowaves.left.and.right")
                    }

                    Button("重新加载状态") { status = describeState() }
                }

                Section(header: Text("关于")) {
                    Text("需要 rootless / rootful 越狱；配置写入：")
                        .font(.footnote)
                    Text(Prefs.path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("AirPods Compat")
        }
        .navigationViewStyle(.stack)
    }

    @discardableResult
    private func savePreference(_ key: String, value: Any) -> Bool {
        var prefs = Prefs.load()
        prefs[key] = value
        do {
            try Prefs.save(prefs)
            status = "已保存，重启用户空间后生效"
            return true
        } catch {
            status = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    private func setScope(all: Bool) {
        if savePreference("Scope", value: all ? "all" : "core") {
            scopeAll = all
        }
    }

    private func describeState() -> String {
        let prefs = Prefs.load()
        let enabled = (prefs["Enabled"] as? Bool) ?? true
        let uarp = (prefs["UARPEnabled"] as? Bool) ?? true
        let scope = (prefs["Scope"] as? String) ?? "core"
        let borrow = (prefs["BorrowProfile"] as? String) ?? BorrowProfile.airpods4anc.rawValue
        let directoryExists = FileManager.default.fileExists(atPath: Prefs.directory)
        return "enabled=\(enabled) uarp=\(uarp) scope=\(scope) borrow=\(borrow) · prefsDir=\(directoryExists ? "存在" : "不存在")"
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
