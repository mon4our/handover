import Foundation
import IOBluetooth
import CoreGraphics

// MARK: - Bluetooth

enum Bluetooth {
    static func device(_ address: String) -> IOBluetoothDevice? {
        IOBluetoothDevice(addressString: address)
    }

    static func name(_ address: String) -> String {
        device(address)?.nameOrAddress ?? address
    }

    static func isConnected(_ address: String) -> Bool {
        device(address)?.isConnected() ?? false
    }

    static func disconnect(_ address: String) -> Bool {
        guard let device = device(address) else {
            log("  \(address): not a known device")
            return false
        }
        guard device.isConnected() else {
            log("  \(device.nameOrAddress ?? address): already disconnected")
            return false
        }
        let name = device.nameOrAddress ?? address
        let result = device.closeConnection()
        if result != kIOReturnSuccess {
            log("  \(name): disconnect failed (IOReturn \(result))")
            return false
        }
        // closeConnection() kicks off the teardown but the link only actually drops once the
        // run loop has been serviced — exiting (or sleeping) too early leaves it connected.
        if settle(device, until: false, timeout: 5) {
            log("  \(name): disconnected")
            return true
        }
        log("  \(name): still connected 5s after disconnect request")
        return false
    }

    /// Pump the run loop until the device reaches `state`, or the timeout expires.
    private static func settle(_ device: IOBluetoothDevice, until state: Bool, timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if device.isConnected() == state { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        return device.isConnected() == state
    }

    static func connect(_ address: String) -> Bool {
        guard let device = device(address) else {
            log("  \(address): not a known device")
            return false
        }
        if device.isConnected() {
            log("  \(device.nameOrAddress ?? address): already connected")
            return true
        }
        let name = device.nameOrAddress ?? address
        let result = device.openConnection()
        if result == kIOReturnSuccess && settle(device, until: true, timeout: 5) {
            log("  \(name): reconnected")
            return true
        }
        log("  \(name): connect attempt failed (IOReturn \(result))")
        return false
    }
}

func displayIsAsleep() -> Bool {
    CGDisplayIsAsleep(CGMainDisplayID()) != 0
}


extension Bluetooth {
    /// Paired devices that are headphones/speakers/headsets — the ones worth managing.
    static func pairedAudioDevices() -> [IOBluetoothDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
        return paired.filter { $0.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio) }
    }

    /// Addresses use both `:` and `-` separators depending on where they came from.
    static func normalize(_ address: String) -> String {
        address.replacingOccurrences(of: "-", with: ":").uppercased()
    }
}
