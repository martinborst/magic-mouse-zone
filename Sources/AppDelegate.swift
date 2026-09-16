import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ScrollEngine.shared?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScrollEngine.shared?.shutdown()
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
