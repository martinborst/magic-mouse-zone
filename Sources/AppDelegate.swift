import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(.accessory)
        ScrollEngine.shared?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        restoreNativeScrolling()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        restoreNativeScrolling()
    }

    /// `MTDeviceStart` hijacks the Magic Mouse digitizer. Stop the original device
    /// refs even if SwiftUI has already released `ScrollEngine`.
    private func restoreNativeScrolling() {
        if let engine = ScrollEngine.shared {
            engine.shutdown()
        } else {
            TouchMonitor.releaseAllMagicMice()
        }
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
