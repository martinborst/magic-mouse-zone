import AppKit
import ApplicationServices
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class ScrollEngine: ObservableObject {
    nonisolated(unsafe) static weak var shared: ScrollEngine?

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled") }
    }
    @Published var ignoreMultipleFingers: Bool {
        didSet { UserDefaults.standard.set(ignoreMultipleFingers, forKey: "ignoreMultipleFingers") }
    }
    @Published var zone: ScrollZone {
        didSet { persistZone() }
    }
    @Published var handedness: Handedness {
        didSet { UserDefaults.standard.set(handedness.rawValue, forKey: "handedness") }
    }
    @Published var fingers: [FingerDot] = []
    @Published var mouseConnected = false
    @Published var deviceSummary = "Looking for a Magic Mouse…"
    @Published var accessibilityGranted = false
    @Published var tapRunning = false
    @Published var launchAtLogin = false

    private let touchMonitor = TouchMonitor()
    private let eventTap = ScrollEventTap.shared
    private var permissionTimer: Timer?
    private var didStart = false

    private let state = FilterState()

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "enabled") == nil {
            defaults.set(true, forKey: "enabled")
        }
        if defaults.object(forKey: "ignoreMultipleFingers") == nil {
            defaults.set(true, forKey: "ignoreMultipleFingers")
        }
        enabled = defaults.bool(forKey: "enabled")
        ignoreMultipleFingers = defaults.bool(forKey: "ignoreMultipleFingers")
        handedness = Handedness(rawValue: defaults.string(forKey: "handedness") ?? "") ?? .right
        zone = Self.loadZone() ?? .middleFinger
        ScrollEngine.shared = self
        state.updateConfig(enabled: enabled, zone: zone, ignoreMultipleFingers: ignoreMultipleFingers)
        accessibilityGranted = Permissions.accessibilityGranted
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func start() {
        guard !didStart else {
            refreshPermissionsAndTap()
            return
        }
        didStart = true
        touchMonitor.start()
        refreshPermissionsAndTap()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionsAndTap()
            }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionsAndTap()
            }
        }
    }

    func applyZoneToFilter() {
        state.updateConfig(enabled: enabled, zone: zone, ignoreMultipleFingers: ignoreMultipleFingers)
        if tapRunning {
            eventTap.setEnabled((enabled || ignoreMultipleFingers) && accessibilityGranted)
        }
    }

    func requestAccess() {
        Permissions.requestAccessibility()
        refreshPermissionsAndTap()
    }

    func revealAppInFinder() {
        Permissions.revealAppInFinder()
    }

    func relaunch() {
        Permissions.relaunch()
    }

    nonisolated func reenableTap() {
        ScrollEventTap.shared.reenable()
    }

    func refreshPermissionsAndTap() {
        var granted = Permissions.accessibilityGranted
        if !tapRunning {
            tapRunning = eventTap.start()
        }
        if tapRunning {
            granted = true
            eventTap.setEnabled(enabled || ignoreMultipleFingers)
        }
        if granted != accessibilityGranted {
            accessibilityGranted = granted
        }
        state.updateConfig(enabled: enabled, zone: zone, ignoreMultipleFingers: ignoreMultipleFingers)
        let login = SMAppService.mainApp.status == .enabled
        if login != launchAtLogin {
            launchAtLogin = login
        }
    }

    nonisolated func handleTouches(_ touches: UnsafeMutablePointer<MTTouch>?, count: Int) {
        var dots: [FingerDot] = []
        if let touches, count > 0 {
            for i in 0..<count {
                let touch = touches[i]
                let stateValue = Int(touch.state)
                guard (Int(MTTouchStateMakeTouch)...Int(MTTouchStateBreakTouch)).contains(stateValue) else {
                    continue
                }
                let x = Double(touch.normalizedVector.position.x)
                let y = Double(touch.normalizedVector.position.y)
                let vx = Double(touch.normalizedVector.velocity.x)
                let vy = Double(touch.normalizedVector.velocity.y)
                let speed = hypot(vx, vy)
                let ident = Int(touch.pathIndex != 0 ? touch.pathIndex : touch.fingerID)
                dots.append(
                    FingerDot(
                        id: ident == 0 ? i + 1_000 : ident,
                        x: x,
                        y: y,
                        speed: speed,
                        inZone: state.contains(x: x, y: y)
                    )
                )
            }
        }
        guard state.replaceFingers(dots) else { return }
        let snapshot = dots
        DispatchQueue.main.async { [weak self] in
            self?.fingers = snapshot
            if !snapshot.isEmpty {
                self?.mouseConnected = true
            }
        }
    }

    nonisolated func shouldAllowScrollEvent(_ event: CGEvent) -> Bool {
        state.shouldAllow(event)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        updateLaunchAtLogin()
    }

    private func persistZone() {
        if let data = try? JSONEncoder().encode(zone) {
            UserDefaults.standard.set(data, forKey: "zone")
        }
        state.updateConfig(enabled: enabled, zone: zone, ignoreMultipleFingers: ignoreMultipleFingers)
    }

    private static func loadZone() -> ScrollZone? {
        guard let data = UserDefaults.standard.data(forKey: "zone") else { return nil }
        return try? JSONDecoder().decode(ScrollZone.self, from: data)
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

/// Thread-safe filter used from the CGEvent tap and Multitouch callbacks.
final class FilterState: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    private var ignoreMultipleFingers = true
    private var zone = ScrollZone.middleFinger
    private var fingers: [FingerDot] = []
    private var lastFingerTime: TimeInterval = 0
    private var lastFingerCount = 0
    private var lastUIUpdate: TimeInterval = 0
    private var gestureAllowed: Bool?
    private var inMagicMouseGesture = false

    func updateConfig(enabled: Bool, zone: ScrollZone, ignoreMultipleFingers: Bool) {
        lock.lock()
        self.enabled = enabled
        self.zone = zone
        self.ignoreMultipleFingers = ignoreMultipleFingers
        lock.unlock()
    }

    func contains(x: Double, y: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return zone.contains(x: x, y: y)
    }

    @discardableResult
    func replaceFingers(_ fingers: [FingerDot]) -> Bool {
        lock.lock()
        self.fingers = fingers
        if !fingers.isEmpty {
            lastFingerTime = ProcessInfo.processInfo.systemUptime
            lastFingerCount = fingers.count
        }
        let now = ProcessInfo.processInfo.systemUptime
        let shouldPublish = now - lastUIUpdate >= 1.0 / 24.0
        if shouldPublish {
            lastUIUpdate = now
        }
        lock.unlock()
        return shouldPublish
    }

    func shouldAllow(_ event: CGEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard enabled || ignoreMultipleFingers else { return true }

        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let recentlyTouched = ProcessInfo.processInfo.systemUptime - lastFingerTime < 0.12
        let fingerCount = fingers.isEmpty && recentlyTouched ? lastFingerCount : fingers.count
        let hasFingers = fingerCount > 0 || recentlyTouched

        if momentum == 2 || momentum == 3 { // continue / end
            if inMagicMouseGesture, let allowed = gestureAllowed {
                if momentum == 3 {
                    inMagicMouseGesture = false
                    gestureAllowed = nil
                }
                return allowed
            }
            return true
        }

        if !hasFingers {
            if phase == 1 || phase == 128 { // began / mayBegin
                inMagicMouseGesture = false
                gestureAllowed = nil
            }
            return true
        }

        let allowedNow: Bool
        if ignoreMultipleFingers && Self.isMultiFingerScroll(
            fingers: fingers,
            count: fingerCount,
            zone: zone,
            zoneEnabled: enabled
        ) {
            allowedNow = false
        } else if enabled {
            allowedNow = Self.zoneAllowsScroll(fingers: fingers, zone: zone)
        } else {
            allowedNow = true
        }

        if phase == 1 || phase == 128 || gestureAllowed == nil {
            gestureAllowed = allowedNow
            inMagicMouseGesture = true
        }

        if phase == 4 || phase == 8 { // ended / cancelled
            let allowed = gestureAllowed ?? allowedNow
            return allowed
        }

        return gestureAllowed ?? allowedNow
    }

    private static func isMultiFingerScroll(
        fingers: [FingerDot],
        count: Int,
        zone: ScrollZone,
        zoneEnabled: Bool
    ) -> Bool {
        if fingers.isEmpty {
            return count >= 2
        }
        let speedThreshold = 0.015
        if fingers.filter({ $0.speed >= speedThreshold }).count >= 2 {
            return true
        }
        if zoneEnabled {
            return fingers.filter { zone.contains(x: $0.x, y: $0.y) }.count >= 2
        }
        return fingers.count >= 2
    }

    private static func zoneAllowsScroll(fingers: [FingerDot], zone: ScrollZone) -> Bool {
        guard !fingers.isEmpty else { return true }
        let speedThreshold = 0.015
        if let moving = fingers.max(by: { $0.speed < $1.speed }), moving.speed >= speedThreshold {
            return zone.contains(x: moving.x, y: moving.y)
        }
        return fingers.contains { zone.contains(x: $0.x, y: $0.y) }
    }
}
