import Foundation
import IOKit

final class TouchMonitor {
    /// Keeps the `MTDeviceCreateList` array alive so the started device pointer stays valid.
    private struct StartedDevice {
        let device: MTDeviceRef
        let list: CFArray
    }

    private static let lock = NSLock()
    private static var started: [UInt64: StartedDevice] = [:]
    private static var didWaitForHIDRelease = false

    private var pollTimer: Timer?

    func start() {
        scanAndStart()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.scanAndStart()
        }
        pollTimer?.tolerance = 0.25
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        Self.releaseAllMagicMice()
    }

    deinit {
        pollTimer?.invalidate()
        Self.releaseAllMagicMice()
    }

    /// Stops every Magic Mouse we previously started so macOS can generate scroll events again.
    static func releaseAllMagicMice() {
        let hadStarted: Bool = {
            lock.lock()
            defer { lock.unlock() }
            return !started.isEmpty
        }()
        stopStartedDevices()

        let list = MTDeviceCreateList().takeRetainedValue()
        let count = CFArrayGetCount(list)
        var stoppedFromList = false
        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: MTDeviceRef.self)
            guard isMagicMouseDevice(device) else { continue }
            stopDevice(device)
            stoppedFromList = true
        }

        // MTDeviceStop is asynchronous in the HID stack; give it a moment before exit.
        let shouldWait = hadStarted || stoppedFromList
        lock.lock()
        let alreadyWaited = didWaitForHIDRelease
        if shouldWait {
            didWaitForHIDRelease = true
        }
        lock.unlock()
        if shouldWait && !alreadyWaited {
            _ = CFRunLoopRunInMode(.defaultMode, 0.1, false)
        }
    }

    static func probeDescription() -> String {
        let list = MTDeviceCreateList().takeRetainedValue()
        let count = CFArrayGetCount(list)
        if count == 0 {
            return "No multitouch devices found. Is the Magic Mouse on and connected?"
        }
        var lines: [String] = ["Found \(count) multitouch device(s):"]
        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: MTDeviceRef.self)
            lines.append(describe(device))
        }
        return lines.joined(separator: "\n")
    }

    func scanAndStart() {
        let list = MTDeviceCreateList().takeRetainedValue()
        let count = CFArrayGetCount(list)
        var liveIDs = Set<UInt64>()
        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: MTDeviceRef.self)
            guard Self.isMagicMouseDevice(device) else { continue }
            liveIDs.insert(Self.startOrRestart(device, list: list))
        }

        let gone = Self.takeGoneDevices(liveIDs: liveIDs)
        for item in gone {
            Self.stopDevice(item.device)
        }

        if liveIDs.isEmpty && !gone.isEmpty {
            ScrollEngine.shared?.handleMouseLost()
        }
    }

    private static func takeGoneDevices(liveIDs: Set<UInt64>) -> [StartedDevice] {
        lock.lock()
        defer { lock.unlock() }
        let staleIDs = Set(started.keys).subtracting(liveIDs)
        return staleIDs.compactMap { started.removeValue(forKey: $0) }
    }

    private static func stopStartedDevices() {
        lock.lock()
        let devices = Array(started.values)
        started.removeAll()
        lock.unlock()

        for item in devices {
            stopDevice(item.device)
        }
    }

    private static func stopDevice(_ device: MTDeviceRef) {
        MTUnregisterContactFrameCallback(device, touchFrameCallback)
        MTDeviceStop(device)
    }

    @discardableResult
    private static func startOrRestart(_ device: MTDeviceRef, list: CFArray) -> UInt64 {
        var deviceID: UInt64 = 0
        MTDeviceGetDeviceID(device, &deviceID)
        if deviceID == 0 {
            deviceID = UInt64(bitPattern: Int64(Int(bitPattern: device)))
        }

        lock.lock()
        let existing = started[deviceID]
        lock.unlock()

        if let existing {
            if MTDeviceIsRunning(existing.device) {
                return deviceID
            }
            stopDevice(existing.device)
            lock.lock()
            started.removeValue(forKey: deviceID)
            lock.unlock()
        }

        MTRegisterContactFrameCallback(device, touchFrameCallback)
        MTDeviceStart(device, 0)

        lock.lock()
        started[deviceID] = StartedDevice(device: device, list: list)
        lock.unlock()

        var family: Int32 = 0
        MTDeviceGetFamilyID(device, &family)
        DispatchQueue.main.async {
            Task { @MainActor in
                ScrollEngine.shared?.mouseConnected = true
                ScrollEngine.shared?.deviceSummary = "Magic Mouse connected · family \(family)"
            }
        }
        return deviceID
    }

    private static func isMagicMouseDevice(_ device: MTDeviceRef) -> Bool {
        var family: Int32 = 0
        MTDeviceGetFamilyID(device, &family)

        if family == 112 || family == 113 || family == 114 {
            return true
        }

        // Built-in and Magic Trackpads.
        if (98...110).contains(family) { return false }
        if (128...132).contains(family) { return false }
        if MTDeviceIsBuiltIn(device) { return false }

        var width: Int32 = 0
        var height: Int32 = 0
        MTDeviceGetSensorSurfaceDimensions(device, &width, &height)
        // Magic Mouse surface is taller than it is wide.
        if width > 0 && height > width {
            return true
        }
        return false
    }

    private static func describe(_ device: MTDeviceRef) -> String {
        var family: Int32 = 0
        var deviceID: UInt64 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        MTDeviceGetFamilyID(device, &family)
        MTDeviceGetDeviceID(device, &deviceID)
        MTDeviceGetSensorSurfaceDimensions(device, &width, &height)
        let builtIn = MTDeviceIsBuiltIn(device) ? "built-in" : "external"
        return "  family \(family), id \(deviceID), sensor \(width)×\(height), \(builtIn)"
    }
}

private func touchFrameCallback(
    _ device: MTDeviceRef?,
    _ touches: UnsafeMutablePointer<MTTouch>?,
    _ numTouches: Int,
    _ timestamp: Double,
    _ frame: Int
) {
    ScrollEngine.shared?.handleTouches(touches, count: numTouches)
}
