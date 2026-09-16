import SwiftUI

@main
struct MagicMouseZoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = ScrollEngine()

    init() {
        if CommandLine.arguments.contains("--probe") {
            fputs(TouchMonitor.probeDescription() + "\n", stdout)
            Darwin.exit(0)
        }
        if CommandLine.arguments.contains("--stop-devices") {
            TouchMonitor.releaseAllMagicMice()
            Darwin.exit(0)
        }
    }

    var body: some Scene {
        Window("Magic Mouse Scroll Zone", id: "settings") {
            SettingsView()
                .environmentObject(engine)
                .onAppear {
                    engine.start()
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("Magic Mouse Zone", systemImage: engine.enabled ? "computermouse.fill" : "computermouse") {
            MenuBarContent()
                .environmentObject(engine)
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var engine: ScrollEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(engine.enabled ? "Scroll Zone Is On" : "Scroll Zone Is Off") {
            engine.enabled.toggle()
            engine.applyZoneToFilter()
        }
        Divider()
        Button("Scroll Zone Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            if !AppDelegate.orderSettingsFront() {
                openWindow(id: "settings")
            }
        }
        Divider()
        Button("Quit Magic Mouse Zone") {
            NSApp.terminate(nil)
        }
    }
}
