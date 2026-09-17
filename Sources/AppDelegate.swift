import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didHandMouseBack = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(.accessory)
        ScrollEngine.shared?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        handMouseBackToSystem()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        handMouseBackToSystem()
    }

    /// Drop our event tap, then reconnect the Magic Mouse so WindowServer
    /// owns digitizer-to-scroll conversion again.
    private func handMouseBackToSystem() {
        if let engine = ScrollEngine.shared {
            engine.shutdown()
        } else {
            ScrollEventTap.shared.stop()
            TouchMonitor.releaseAllMagicMice()
        }
        guard !didHandMouseBack else { return }
        didHandMouseBack = true
        MagicMouseRestorer.restoreAndWait()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.orderSettingsFront()
        return true
    }

    @discardableResult
    static func orderSettingsFront() -> Bool {
        let window = NSApp.windows.first { window in
            window.isVisible
                && (window.title == "Magic Mouse Scroll Zone"
                    || window.identifier?.rawValue.contains("settings") == true)
        } ?? NSApp.windows.first { window in
            window.title == "Magic Mouse Scroll Zone"
                || window.identifier?.rawValue.contains("settings") == true
        }
        guard let window else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}
