import SwiftUI

struct DiagnosticsView: View {
    @State private var snapshot = CompatibilitySnapshot()
    var body: some View {
        List {
            Section("配置与运行时") {
                LabeledContent("系统", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("配置目标", value: snapshot.requestedProfile)
                Text("活动状态以系统进程记录和设备实际结果为准。本页的框架探测仅发生在 App 进程内。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("功能状态") {
                ForEach(snapshot.assessments) { feature in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(feature.id).font(.headline)
                            Spacer()
                            Text(feature.status.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(feature.detail).font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            Section("上次系统进程记录") {
                if snapshot.runtimeRecords.isEmpty {
                    Text("暂无可读记录。启用诊断并重启受影响进程后重试；沙箱 App 可能无法读取。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(snapshot.runtimeRecords, id: \.self) { record in
                    Text(record).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            Section {
                NavigationLink("设备与连接诊断") { DeviceProbeView() }
                NavigationLink("型号注册自检（App 进程）") { SelfTestView() }
                Button("刷新能力与记录") { snapshot = CompatibilitySnapshot() }
                ShareLink(item: snapshot.report()) { Label("导出诊断报告", systemImage: "square.and.arrow.up") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("兼容性诊断")
    }
}
