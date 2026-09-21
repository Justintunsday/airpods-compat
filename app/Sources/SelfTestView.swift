import SwiftUI
import UIKit

struct SelfTestView: View {
    @State private var report: String = ""
    @State private var running = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("无需越狱即可运行：检查本机系统是否认识 AirPods 5 的各型号，并在 App 进程内干跑 tweak 的动态注册逻辑。")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Button {
                    run()
                } label: {
                    Label(running ? "运行中…" : "运行自检", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)

                if !report.isEmpty {
                    Divider()
                    Text(report)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = report
                    } label: {
                        Label("复制报告", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("自检")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() {
        running = true
        report = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ACRunSelfTest()
            DispatchQueue.main.async {
                report = result
                running = false
            }
        }
    }
}

struct SelfTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { SelfTestView() }
    }
}
