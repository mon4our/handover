// headphone-disconnect — drop Bluetooth audio devices when the Mac sleeps, reconnect them when
// it wakes, so multipoint headphones stay usable on your phone.
//
// See install.sh for the build; sources live in Sources/.

import AppKit
import Foundation
import IOBluetooth

// MARK: - Commands

func printStatus(_ config: Config) {
    print("Configured devices:")
    if config.devices.isEmpty {
        print("  (none — pick them in the menu bar, or add addresses to \(Config.defaultPath))")
    }
    for address in config.devices {
        print("  \(Bluetooth.name(address)) [\(address)]: \(Bluetooth.isConnected(address) ? "connected" : "not connected")")
    }
    print("  disconnect on sleep: \(config.enabled ? "on" : "paused")")
    print("  reconnect on wake:   \(config.reconnectOnWake ? "on" : "off")")

    print("\nAll paired audio devices:")
    for device in Bluetooth.pairedAudioDevices() {
        let address = Bluetooth.normalize(device.addressString ?? "?")
        print("  \(address)  \(device.nameOrAddress ?? "?")  \(device.isConnected() ? "connected" : "-")")
    }
}

/// Prints what the menu bar UI currently shows, without needing a click.
func dumpMenu(settings: Settings) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let watcher = SleepWatcher(settings: settings)
    let controller = MenuBarController(settings: settings, watcher: watcher)
    print(controller.describeMenu())
}

func runMenuBar(settings: Settings) -> Never {
    let app = NSApplication.shared
    // No Dock icon, no window — just the status bar item.
    app.setActivationPolicy(.accessory)

    let watcher = SleepWatcher(settings: settings)
    if !watcher.start() {
        log("error: running without sleep/wake handling")
    }
    // Held for the process lifetime; the status item goes away with it.
    menuBarController = MenuBarController(settings: settings, watcher: watcher)

    app.run()
    exit(0)
}

var menuBarController: MenuBarController?

func runHeadless(settings: Settings) -> Never {
    guard !settings.config.devices.isEmpty else {
        log("fatal: no devices configured (\(settings.path)); run `headphone-disconnect status` to list addresses")
        exit(1)
    }
    let watcher = SleepWatcher(settings: settings)
    guard watcher.start() else { exit(1) }
    for address in settings.config.devices {
        log("  \(Bluetooth.name(address)) [\(address)]: \(Bluetooth.isConnected(address) ? "connected" : "not connected")")
    }
    CFRunLoopRun()
    exit(0)
}

func usage(_ exitCode: Int32 = 1) -> Never {
    print("""
    usage: headphone-disconnect [menubar|watch|disconnect|connect|status] [options]

      menubar     (default) menu bar UI, with sleep/wake handling built in
      watch       sleep/wake handling only, no UI
      disconnect  disconnect the configured devices now
      connect     connect the configured devices now
      status      show configured and paired audio devices
      dump-menu   print what the menu bar UI would show (debugging)

    options:
      --config <path>    config file (default: ~/.config/headphone-disconnect/config.json)
      --device <addr>    device address, repeatable; overrides the config file's device list
    """)
    exit(exitCode)
}

// MARK: - Arguments

var command = "menubar"
var configPath = Config.defaultPath
var overrideDevices: [String] = []

var args = Array(CommandLine.arguments.dropFirst())
if let first = args.first, !first.hasPrefix("-") {
    command = first
    args.removeFirst()
}
var index = 0
while index < args.count {
    switch args[index] {
    case "--config":
        guard index + 1 < args.count else { usage() }
        configPath = (args[index + 1] as NSString).expandingTildeInPath
        index += 2
    case "--device":
        guard index + 1 < args.count else { usage() }
        overrideDevices.append(Bluetooth.normalize(args[index + 1]))
        index += 2
    case "-h", "--help":
        usage(0)
    default:
        usage()
    }
}

let settings = Settings(path: configPath)
if !overrideDevices.isEmpty {
    settings.update { $0.devices = overrideDevices }
}

switch command {
case "menubar":
    runMenuBar(settings: settings)
case "watch":
    runHeadless(settings: settings)
case "disconnect":
    log("disconnecting")
    for address in settings.config.devices { _ = Bluetooth.disconnect(address) }
case "connect":
    log("connecting")
    for address in settings.config.devices { _ = Bluetooth.connect(address) }
case "status":
    printStatus(settings.config)
case "dump-menu":
    dumpMenu(settings: settings)
default:
    usage()
}
