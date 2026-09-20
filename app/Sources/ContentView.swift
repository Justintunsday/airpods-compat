import SwiftUI

struct ModelInfo: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct ContentView: View {
    @State private var enabled: Bool = (Prefs.load()["Enabled"] as? Bool) ?? true
    @State private var status: String = ""

    private let models: [ModelInfo] = [
        ModelInfo(title: "AirPods 5", detail: "A3531 / A3532 / A3533 · case A3529"),
        ModelInfo(title: "AirPods 5 (Wireless Charging)", detail: "A3439 / A3440 / A3441 · case A3530"),
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("启用移植", isOn: $enabled)
                        .onChange(of: enabled) { newValue in
                            save(enabled: newValue)
                        }
                }

                Section(header: Text("支持的型号")) {
                    ForEach(models) { model in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.title).font(.headline)
                            Text(model.detail).font(.footnote).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section(header: Text("诊断")) {
                    Button("重新加载状态") { status = describeState() }
                    if !status.isEmpty {
                        Text(status).font(.footnote).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("关于")) {
                    Text("需要 rootless 越狱（Dopamine / roothide）。")
                        .font(.footnote)
                    Text("配置写入：\(Prefs.path)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("AirPods Compat")
        }
        .navigationViewStyle(.stack)
    }

    private func save(enabled: Bool) {
        var prefs = Prefs.load()
        prefs["Enabled"] = enabled
        do {
            try Prefs.save(prefs)
            status = "已保存，重启 bluetoothd 后生效"
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }

    private func describeState() -> String {
        let prefs = Prefs.load()
        let enabled = (prefs["Enabled"] as? Bool) ?? true
        let reachable = FileManager.default.fileExists(atPath: Prefs.directory)
        return "enabled=\(enabled) · prefsDir=\(reachable ? "OK" : "不可写")"
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
