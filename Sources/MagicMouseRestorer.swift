import Foundation
import IOBluetooth
import IOKit

/// Opening a MultitouchSupport client takes over Magic Mouse digitizer-to-scroll
/// conversion. When this process exits, macOS does not take that client back.
/// Reconnecting the mouse is what makes WindowServer start generating scroll again.
enum MagicMouseRestorer {
    private static let magicMouseProductIDs: Set<Int> = [
        0x030D, // Magic Mouse
        0x0269, // Magic Mouse 2
        0x0323  // Magic Mouse USB-C
    ]

    static func restoreAndWait() {
        let mice = connectedMagicMice()
        guard !mice.isEmpty else { return }

        for mouse in mice {
            _ = mouse.closeConnection()
        }
        spinRunLoop(seconds: 0.25)
        for mouse in mice {
            _ = mouse.openConnection(
                nil,
                withPageTimeout: 0x2000,
                authenticationRequired: false
            )
        }
        spinRunLoop(seconds: 0.35)
    }

    private static func spinRunLoop(seconds: TimeInterval) {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            _ = CFRunLoopRunInMode(.defaultMode, 0.05, false)
        }
    }

    private static func connectedMagicMice() -> [IOBluetoothDevice] {
        var found: [IOBluetoothDevice] = []
        var seen = Set<String>()

        for address in bluetoothAddressesFromIORegistry() {
            let candidates = [
                address,
                address.replacingOccurrences(of: ":", with: "-"),
                address.replacingOccurrences(of: "-", with: ":")
            ]
            for candidate in candidates {
                guard let device = IOBluetoothDevice(addressString: candidate) else { continue }
                let key = device.addressString ?? candidate
                guard seen.insert(key).inserted else { continue }
                if device.isConnected() {
                    found.append(device)
                }
                break
            }
        }

        if found.isEmpty, let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in paired where device.isConnected() && isMagicMouse(device) {
                let key = device.addressString ?? device.name ?? UUID().uuidString
                guard seen.insert(key).inserted else { continue }
                found.append(device)
            }
        }
        return found
    }

    private static func isMagicMouse(_ device: IOBluetoothDevice) -> Bool {
        let name = (device.name ?? "").lowercased()
        if name.contains("magic mouse") { return true }
        if name.contains("keyboard") || name.contains("airpods") || name.contains("iphone") {
            return false
        }
        return name.contains("mouse")
    }

    private static func bluetoothAddressesFromIORegistry() -> [String] {
        var addresses: [String] = []
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleMultitouchDevice")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            let vendor = intProperty(service, "VendorID") ?? 0
            let product = intProperty(service, "ProductID") ?? 0
            let apple = vendor == 0x004C || vendor == 0x05AC
            guard apple && magicMouseProductIDs.contains(product) else { continue }
            if let serial = stringProperty(service, "SerialNumber"), serial.contains(":") || serial.contains("-") {
                addresses.append(serial)
            }
        }
        return addresses
    }

    private static func intProperty(_ service: io_service_t, _ key: String) -> Int? {
        guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return (cf.takeRetainedValue() as? NSNumber)?.intValue
    }

    private static func stringProperty(_ service: io_service_t, _ key: String) -> String? {
        guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return cf.takeRetainedValue() as? String
    }
}
