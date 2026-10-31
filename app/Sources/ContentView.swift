import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ContentView: View {
    @StateObject private var configuration = ConfigurationManager()
    @State private var exporting = false
    @State private var document = ConfigurationDocument(data: Data())
    @State private var exportError: String?
    private func toggle(_ key: String, default fallback: Bool = true) -> Binding<Bool> {
        Binding(get: { configuration.bool(key, default: fallback) }, set: { configuration.set(key, $0) })
    }
    var body: some View {
        NavigationView {
            List {
                Section("兼容性") {
                    NavigationLink { DiagnosticsView() } label: {
                        Label("设备与兼容性状态", systemImage: "headphones")
                    }
                    Toggle("启用兼容层", isOn: toggle("Enabled"))
                    Picker("iOS 18–26 功能配置", selection: Binding(
                        get: { configuration.string("BorrowProfile", default: "airpods4anc") },
                        set: { configuration.set("BorrowProfile", $0) }
                    )) {
                        Text("AirPods 4 (ANC)").tag("airpods4anc")
                        Text("关闭适配").tag("off")
                    }
                    Text("仅使用本机可用的原生实现。实际 AirPods 5 身份、固件与配对标识保持真实值。iOS 16–17 保留旧版配置。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("系统资源") {
                    Toggle("设置与控制中心降噪按钮", isOn: toggle("NoiseControlsEnabled"))
                    Toggle("路由图标兼容", isOn: toggle("LegacyRouteResourcesEnabled"))
                    Toggle("电池图标兼容", isOn: toggle("LegacyBatteryResourcesEnabled"))
                    Text("图标适配不会生成电量数据。默认进程名单包括 SpringBoard、MusicUIService 及已验证过的 Apple 客户端。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("配件注册") {
                    Toggle("注册缺失的 UARP 型号", isOn: toggle("UARPEnabled"))
                    Toggle("包含旧型号与 Beats", isOn: Binding(
                        get: { configuration.string("Scope", default: "core") == "all" },
                        set: { configuration.set("Scope", $0 ? "all" : "core") }
                    ))
                    Toggle("记录系统诊断", isOn: toggle("DiagnosticsEnabled", default: false))
                }
                Section("应用配置") {
                    Button("应用到共享配置") { configuration.apply() }
                    Button("导出配置文件") {
                        do {
                            document = ConfigurationDocument(data: try Prefs.data(configuration.values))
                            exporting = true
                        } catch { exportError = error.localizedDescription }
                    }
                    Button("重新读取配置") { configuration.reload() }
                    Text(configuration.status).font(.footnote).foregroundStyle(.secondary)
                    if let exportError { Text(exportError).font(.footnote).foregroundStyle(.red) }
                    Text("沙箱 App 可将导出的 plist 传到设备后，用越狱终端中的 acprefs import 导入。应用后需重启受影响的进程。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("AirPods Compat")
        }
        .navigationViewStyle(.stack)
        .fileExporter(isPresented: $exporting, document: document, contentType: .propertyList,
                      defaultFilename: "AirPodsCompat-config") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
    }
}
