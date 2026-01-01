import SwiftUI

@main
struct ComputexHostApp: App {
    @StateObject private var model = AppModel()

    init() {
        CrashLogging.install()
        RuntimeDiagnostics.logEnvironment()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.titleBar)
    }
}
