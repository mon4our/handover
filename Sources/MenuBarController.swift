import AppKit
import IOBluetooth

// MARK: - Menu bar UI

/// A status-bar item that shows what the watcher is doing and lets you override it:
/// pick which headphones to manage, pause the sleep behaviour, or disconnect right now.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let settings: Settings
    private let watcher: SleepWatcher
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var refreshTimer: Timer?

    private var config: Config { settings.config }

    init(settings: Settings, watcher: SleepWatcher) {
        self.settings = settings
        self.watcher = watcher
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = icon(named: "headphones")

        watcher.onChange = { [weak self] in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }

        // Devices come and go without telling us, so poll gently for the icon state.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
        updateStatusItem()
    }

    // MARK: Icon

    private func icon(named name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Headphone Disconnect")
        image?.isTemplate = true
        return image
    }

    private var managedConnected: [String] {
        config.devices.filter { Bluetooth.isConnected($0) }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        // "headphones.slash" only exists on newer systems; fall back to dimming the icon.
        if !config.enabled {
            button.image = icon(named: "headphones.slash") ?? icon(named: "headphones")
            button.appearsDisabled = icon(named: "headphones.slash") == nil
        } else {
            button.image = icon(named: "headphones")
            button.appearsDisabled = managedConnected.isEmpty
        }
        button.toolTip = statusLine
    }

    private var statusLine: String {
        guard !config.devices.isEmpty else { return "No headphones selected" }
        let states = config.devices.map { address in
            "\(Bluetooth.name(address)) — \(Bluetooth.isConnected(address) ? "connected" : "not connected")"
        }
        return states.joined(separator: "\n")
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        settings.reload()
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        // Current state, one line per managed device.
        if config.devices.isEmpty {
            menu.addItem(disabledItem("No headphones selected"))
        } else {
            for address in config.devices {
                let connected = Bluetooth.isConnected(address)
                menu.addItem(disabledItem("\(Bluetooth.name(address)) — \(connected ? "Connected" : "Not connected")"))
            }
        }

        if !config.devices.isEmpty {
            menu.addItem(.separator())
            let anyConnected = !managedConnected.isEmpty
            let toggle = NSMenuItem(
                title: anyConnected ? "Disconnect from This Mac" : "Connect to This Mac",
                action: #selector(toggleConnection),
                keyEquivalent: ""
            )
            toggle.target = self
            menu.addItem(toggle)
        }

        menu.addItem(.separator())
        menu.addItem(checkItem("Disconnect When Mac Sleeps", on: config.enabled, action: #selector(togglePause)))
        let reconnect = checkItem("Reconnect When Mac Wakes", on: config.reconnectOnWake, action: #selector(toggleReconnect))
        reconnect.isEnabled = config.enabled
        menu.addItem(reconnect)

        menu.addItem(.separator())
        let devices = NSMenuItem(title: "Headphones", action: nil, keyEquivalent: "")
        devices.submenu = deviceSubmenu()
        menu.addItem(devices)

        menu.addItem(.separator())
        let openLog = NSMenuItem(title: "Open Log…", action: #selector(openLog), keyEquivalent: "")
        openLog.target = self
        menu.addItem(openLog)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func deviceSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let paired = Bluetooth.pairedAudioDevices()
        if paired.isEmpty {
            submenu.addItem(disabledItem("No paired audio devices"))
            return submenu
        }
        for device in paired {
            guard let address = device.addressString else { continue }
            let normalized = Bluetooth.normalize(address)
            let managed = config.devices.contains { Bluetooth.normalize($0) == normalized }
            let suffix = device.isConnected() ? " (connected)" : ""
            let item = checkItem(
                (device.nameOrAddress ?? normalized) + suffix,
                on: managed,
                action: #selector(toggleDevice(_:))
            )
            item.representedObject = normalized
            submenu.addItem(item)
        }
        return submenu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Tagged so `describeMenu()` can render these as checkboxes.
    private static let checkItemTag = 1

    private func checkItem(_ title: String, on: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = on ? .on : .off
        item.target = self
        item.tag = MenuBarController.checkItemTag
        return item
    }

    /// Build the menu and describe it as text — lets you check the UI's state from a terminal
    /// (`headphone-disconnect dump-menu`) without clicking anything.
    func describeMenu() -> String {
        menuWillOpen(menu)
        return describe(menu, indent: "  ").joined(separator: "\n")
    }

    private func describe(_ menu: NSMenu, indent: String) -> [String] {
        menu.items.flatMap { item -> [String] in
            if item.isSeparatorItem { return [indent + "---"] }
            var line = indent
            if item.tag == MenuBarController.checkItemTag {
                line += item.state == .on ? "[x] " : "[ ] "
            }
            line += item.title
            if item.submenu != nil { line += " >" }
            if !item.isEnabled && item.submenu == nil { line += "   (dimmed)" }
            var lines = [line]
            if let submenu = item.submenu {
                lines += describe(submenu, indent: indent + "    ")
            }
            return lines
        }
    }

    // MARK: Actions

    @objc private func toggleConnection() {
        let connected = managedConnected
        if connected.isEmpty {
            for address in config.devices { _ = Bluetooth.connect(address) }
        } else {
            for address in connected { _ = Bluetooth.disconnect(address) }
        }
        updateStatusItem()
    }

    @objc private func togglePause() {
        settings.update { $0.enabled.toggle() }
        log("disconnect on sleep \(config.enabled ? "enabled" : "paused") from the menu")
        updateStatusItem()
    }

    @objc private func toggleReconnect() {
        settings.update { $0.reconnectOnWake.toggle() }
        log("reconnect on wake \(config.reconnectOnWake ? "enabled" : "disabled") from the menu")
    }

    @objc private func toggleDevice(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        settings.update { config in
            if let index = config.devices.firstIndex(where: { Bluetooth.normalize($0) == address }) {
                config.devices.remove(at: index)
            } else {
                config.devices.append(address)
            }
        }
        log("managed devices: \(config.devices.joined(separator: ", "))")
        updateStatusItem()
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
