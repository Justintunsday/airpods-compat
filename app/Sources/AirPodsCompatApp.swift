import SwiftUI

@main
struct AirPodsCompatApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
                NavigationView { DiagnosticsView() }
            } else {
                ContentView()
            }
        }
    }
}
