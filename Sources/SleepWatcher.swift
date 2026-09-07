import Foundation
import IOKit
import IOKit.pwr_mgt

// IOMessage.h's power-management message codes: iokit_common_msg(x) == 0xE0000000 | x.
// Swift can't import the macros, so they're spelled out here.
private let messageCanSystemSleep: UInt32 = 0xE000_0270
private let messageSystemWillSleep: UInt32 = 0xE000_0280
private let messageSystemWillPowerOn: UInt32 = 0xE000_0320
private let messageSystemHasPoweredOn: UInt32 = 0xE000_0300

// MARK: - Sleep/wake watcher

final class SleepWatcher {
    private let settings: Settings
    private var rootPort: io_connect_t = 0
    private var notifierPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    /// Devices we disconnected ourselves, so wake only reconnects what sleep took away.
    private var pending: [String] = []
    private var attemptsLeft = 0
    private var darkWakeDeadline: Date?

    /// Called after we change any device's connection state, so a UI can refresh.
    var onChange: (() -> Void)?

    private var config: Config { settings.config }

    init(settings: Settings) {
        self.settings = settings
    }

    /// Register for power notifications on the current run loop. Does not block — the caller
    /// runs the run loop (headless `watch` mode) or hands it to NSApplication (menu bar mode).
    func start() -> Bool {
        let callback: IOServiceInterestCallback = { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            let watcher = Unmanaged<SleepWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handle(messageType: messageType, argument: messageArgument)
        }

        rootPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &notifierPort,
            callback,
            &notifier
        )
        guard rootPort != 0, let notifierPort else {
            log("error: could not register for system power notifications")
            return false
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            IONotificationPortGetRunLoopSource(notifierPort).takeUnretainedValue(),
            .defaultMode
        )

        log("watching for sleep/wake; devices: \(config.devices.joined(separator: ", "))")
        if !config.enabled { log("note: paused — sleep will not disconnect anything") }
        return true
    }

    private func handle(messageType: natural_t, argument: UnsafeMutableRawPointer?) {
        // The config file may have been edited (by the UI, another process, or by hand)
        // since the last event.
        settings.reload()

        switch messageType {
        case messageCanSystemSleep:
            // Idle sleep request — we never veto, just let it through.
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))

        case messageSystemWillSleep:
            // We hold sleep until the disconnects finish (30s budget), which is what makes
            // this reliable: the link is gone before the Mac is actually asleep.
            if config.enabled {
                log("system will sleep")
                pending = disconnectFirmly()
                onChange?()
            } else {
                log("system will sleep — paused, leaving devices alone")
                pending = []
            }
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))

        case messageSystemWillPowerOn:
            break

        case messageSystemHasPoweredOn:
            log("system woke")
            guard config.reconnectOnWake, !pending.isEmpty else { return }
            attemptsLeft = config.reconnectAttempts
            darkWakeDeadline = Date().addingTimeInterval(config.darkWakeGraceSeconds)
            schedule(after: config.reconnectDelay)

        default:
            break
        }
    }

    /// Disconnect every configured device and make sure it stays down. Headphones (and macOS)
    /// can re-establish the link within a second, so we re-check and drop it again before
    /// letting the machine sleep. Returns the devices we actually took offline.
    private func disconnectFirmly() -> [String] {
        var taken: Set<String> = []
        for round in 1...3 {
            let targets = round == 1 ? config.devices : config.devices.filter { taken.contains($0) }
            for address in targets where Bluetooth.isConnected(address) {
                if Bluetooth.disconnect(address) { taken.insert(address) }
            }
            let stillUp = config.devices.filter { taken.contains($0) && Bluetooth.isConnected($0) }
            if stillUp.isEmpty { break }
            log("  \(stillUp.count) device(s) came back; retrying (round \(round))")
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(1.0))
        }
        return config.devices.filter { taken.contains($0) }
    }

    private func schedule(after delay: Double) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.attemptReconnect()
        }
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
    }

    private func attemptReconnect() {
        if config.skipDarkWake && displayIsAsleep() {
            // Dark wake: the user isn't here. Stay armed and check again shortly; if the
            // display never comes on we leave the headphones alone for the phone to use.
            if let deadline = darkWakeDeadline, Date() < deadline {
                schedule(after: config.reconnectInterval)
            } else {
                log("display still asleep (dark wake); leaving \(pending.count) device(s) disconnected")
            }
            return
        }

        log("reconnecting (\(attemptsLeft) attempt(s) left)")
        pending = pending.filter { !Bluetooth.connect($0) }
        attemptsLeft -= 1
        onChange?()

        if pending.isEmpty {
            log("all devices reconnected")
        } else if attemptsLeft > 0 {
            schedule(after: config.reconnectInterval)
        } else {
            log("giving up on: \(pending.joined(separator: ", ")) (probably off or in use elsewhere)")
            pending = []
        }
    }
}
