import Foundation
import IOKit

final class TouchMonitor {
    private var startedDeviceIDs = Set<UInt64>()
    private var deviceList: CFArray?
    private var pollTimer: Timer?
    private let lock = NSLock()

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
        stopStartedDevices()
    }

    /// Stops every Magic Mouse we previously started so macOS can generate scroll events again.
    static func releaseAllMagicMice() {
        let list = MTDeviceCreateList().takeRetainedValue()
        let count = CFArrayGetCount(list)
        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: MTDeviceRef.self)
            guard isMagicMouseDevice(device) else { continue }
            MTUnregisterContactFrameCallback(device, touchFrameCallback)
            if MTDeviceIsRunning(device) {
                MTDeviceStop(device)
            }
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
            liveIDs.insert(startOrRestart(device))
        }

        lock.lock()
        let gone = startedDeviceIDs.subtracting(liveIDs)
        startedDeviceIDs.subtract(gone)
        deviceList = list
        lock.unlock()

        if liveIDs.isEmpty && !gone.isEmpty {
            ScrollEngine.shared?.handleMouseLost()
        }
    }

    private func stopStartedDevices() {
        lock.lock()
        let list = deviceList
        deviceList = nil
        startedDeviceIDs.removeAll()
        lock.unlock()

        guard let list else { return }
        let count = CFArrayGetCount(list)
        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: MTDeviceRef.self)
            guard Self.isMagicMouseDevice(device) else { continue }
            MTUnregisterContactFrameCallback(device, touchFrameCallback)
            if MTDeviceIsRunning(device) {
                MTDeviceStop(device)
            }
        }
    }

    @discardableResult
    private func startOrRestart(_ device: MTDeviceRef) -> UInt64 {
        var deviceID: UInt64 = 0
        MTDeviceGetDeviceID(device, &deviceID)
        if deviceID == 0 {
            deviceID = UInt64(bitPattern: Int64(Int(bitPattern: device)))
        }

        let running = MTDeviceIsRunning(device)

        lock.lock()
        let already = startedDeviceIDs.contains(deviceID)
        lock.unlock()

        if already && running {
            return deviceID
        }

        if already {
            MTUnregisterContactFrameCallback(device, touchFrameCallback)
            if running {
                MTDeviceStop(device)
            }
        }

        MTRegisterContactFrameCallback(device, touchFrameCallback)
        MTDeviceStart(device, 0)

        lock.lock()
        startedDeviceIDs.insert(deviceID)
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
