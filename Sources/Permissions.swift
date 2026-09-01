import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum Permissions {
    /// Fresh TCC read. `AXIsProcessTrusted()` caches the launch-time answer, so
    /// a grant made while the app is running never shows up until relaunch.
    static var accessibilityGranted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            return true
        }
        return CGPreflightPostEventAccess()
    }

    static func requestAccessibility() {
        // The old AX prompt creates a stale TCC row for ad-hoc builds on Sequoia.
        // Request the event-post right this app actually needs, then open Settings
        // so the user can add this exact copy if the dialog is not enough.
        _ = CGRequestPostEventAccess()
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func relaunch() {
        let quoted = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open -n '\(quoted)'"]
        try? process.run()
        NSApp.terminate(nil)
    }
}
