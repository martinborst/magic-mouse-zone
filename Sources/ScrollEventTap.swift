import ApplicationServices
import CoreGraphics
import Foundation

final class ScrollEventTap: @unchecked Sendable {
    static let shared = ScrollEventTap()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tap != nil
    }

    func start() -> Bool {
        stop()

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            return false
        }

        lock.lock()
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        lock.unlock()
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        lock.lock()
        let tap = self.tap
        let source = runLoopSource
        self.tap = nil
        runLoopSource = nil
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        let tap = self.tap
        lock.unlock()
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: enabled)
    }

    func reenable() {
        setEnabled(true)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        ScrollEventTap.shared.reenable()
        return Unmanaged.passUnretained(event)
    }

    guard type == .scrollWheel else {
        return Unmanaged.passUnretained(event)
    }

    if ScrollEngine.shared?.shouldAllowScrollEvent(event) == false {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
