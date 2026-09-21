import SwiftUI

struct ModelInfo: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct ContentView: View {
    @State private var enabled: Bool = (Prefs.load()["Enabled"] as? Bool) ?? true
    @State private var uarpEnabled: Bool = (Prefs.load()["UARPEnabled"] as? Bool) ?? true
    @State private var scopeAll: Bool = (Prefs.load()["Scope"] as? String) == "all"
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
                    Toggle("启用移植", isOn: $enabled)
                        .onChange(of: enabled) { _ in save() }
                    Toggle("UARP 配件注册", isOn: $uarpEnabled)
                        .onChange(of: uarpEnabled) { _ in save() }
                }

                Section(header: Text("注册范围"), footer: Text("默认只注册本机缺失的新代型号（更安全）。全部型号包含 Beats/老型号。")) {
                    Toggle("仅新代型号（推荐）", isOn: Binding(
                        get: { !scopeAll },
                        set: { scopeAll = !$0; save() }
                    ))
                    Toggle("包含全部型号", isOn: Binding(
                        get: { scopeAll },
                        set: { scopeAll = $0; save() }
                    ))
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

                    Button("重新加载状态") { status = describeState() }
                    if !status.isEmpty {
                        Text(status).font(.footnote).foregroundColor(.secondary)
                    }
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

    private func save() {
        var prefs = Prefs.load()
        prefs["Enabled"] = enabled
        prefs["UARPEnabled"] = uarpEnabled
        prefs["Scope"] = scopeAll ? "all" : "core"
        do {
            try Prefs.save(prefs)
            status = "已保存，重启 bluetoothd / 用户空间后生效"
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }

    private func describeState() -> String {
        let prefs = Prefs.load()
        let enabled = (prefs["Enabled"] as? Bool) ?? true
        let uarp = (prefs["UARPEnabled"] as? Bool) ?? true
        let scope = (prefs["Scope"] as? String) ?? "core"
        let reachable = FileManager.default.fileExists(atPath: Prefs.directory)
        return "enabled=\(enabled) uarp=\(uarp) scope=\(scope) · prefsDir=\(reachable ? "OK" : "不可写")"
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
