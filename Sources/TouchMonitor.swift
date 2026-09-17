import Foundation
import IOKit

final class TouchMonitor {
    /// Keeps the `MTDeviceCreateList` array alive so the started device pointer stays valid.
    private struct StartedDevice {
        let device: MTDeviceRef
        let list: CFArray
    }

    private static let lock = NSLock()
    /// Intentionally never cleared on quit. `MTDeviceStop` / releasing these refs
    /// is what kills native Magic Mouse scrolling for the whole system.
    private static var started: [UInt64: StartedDevice] = [:]

    private var pollTimer: Timer?
    private static var isShuttingDown = false

    func start() {
        Self.isShuttingDown = false
        scanAndStart()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.scanAndStart()
        }
        pollTimer?.tolerance = 0.25
    }

    func stop() {
        Self.isShuttingDown = true
        pollTimer?.invalidate()
        pollTimer = nil
        Self.releaseCallbacks()
    }

    deinit {
        pollTimer?.invalidate()
        Self.releaseCallbacks()
    }

    /// Unregisters our touch callback. Does not start or stop the device.
    static func releaseAllMagicMice() {
        isShuttingDown = true
        releaseCallbacks()
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
        guard !Self.isShuttingDown else { return }
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
            MTUnregisterContactFrameCallback(item.device, touchFrameCallback)
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

    private static func releaseCallbacks() {
        lock.lock()
        let devices = Array(started.values)
        lock.unlock()
        for item in devices {
            MTUnregisterContactFrameCallback(item.device, touchFrameCallback)
        }
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

        if let existing, MTDeviceIsRunning(existing.device) {
            return deviceID
        }

        MTRegisterContactFrameCallback(device, touchFrameCallback)
        if !MTDeviceIsRunning(device) {
            MTDeviceStart(device, 0)
        }

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
