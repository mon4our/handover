import Foundation

// MARK: - Config

struct Config {
    /// Bluetooth addresses this utility manages.
    var devices: [String] = []
    /// Master switch for the sleep behaviour. The UI's "Pause" flips this.
    var enabled = true
    var reconnectOnWake = true
    /// Seconds to wait after wake before the first reconnect attempt (the BT stack needs a moment).
    var reconnectDelay: Double = 3
    var reconnectAttempts = 6
    var reconnectInterval: Double = 4
    /// Skip reconnecting during dark wake (Power Nap, scheduled maintenance) — only reconnect
    /// once the display is actually on, i.e. a human woke the Mac.
    var skipDarkWake = true
    var darkWakeGraceSeconds: Double = 120

    static let defaultPath = ("~/.config/handover/config.json" as NSString).expandingTildeInPath

    init() {}

    init(json: [String: Any]) {
        if let v = json["devices"] as? [String] { devices = v }
        if let v = json["enabled"] as? Bool { enabled = v }
        if let v = json["reconnectOnWake"] as? Bool { reconnectOnWake = v }
        if let v = json["reconnectDelay"] as? Double { reconnectDelay = v }
        if let v = json["reconnectAttempts"] as? Int { reconnectAttempts = v }
        if let v = json["reconnectInterval"] as? Double { reconnectInterval = v }
        if let v = json["skipDarkWake"] as? Bool { skipDarkWake = v }
        if let v = json["darkWakeGraceSeconds"] as? Double { darkWakeGraceSeconds = v }
    }

    var json: [String: Any] {
        [
            "devices": devices,
            "enabled": enabled,
            "reconnectOnWake": reconnectOnWake,
            "reconnectDelay": reconnectDelay,
            "reconnectAttempts": reconnectAttempts,
            "reconnectInterval": reconnectInterval,
            "skipDarkWake": skipDarkWake,
            "darkWakeGraceSeconds": darkWakeGraceSeconds,
        ]
    }
}

/// The config file, readable and writable. The menu bar UI edits it in place so the CLI and a
/// headless `watch` process see the same settings.
final class Settings {
    let path: String
    private(set) var config: Config

    init(path: String) {
        self.path = path
        self.config = Settings.read(path: path)
    }

    private static func read(path: String) -> Config {
        guard let data = FileManager.default.contents(atPath: path) else { return Config() }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            log("warning: \(path) is not valid JSON; using defaults")
            return Config()
        }
        return Config(json: json)
    }

    func reload() {
        config = Settings.read(path: path)
    }

    /// Mutate and persist in one step.
    func update(_ mutate: (inout Config) -> Void) {
        mutate(&config)
        save()
    }

    private func save() {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(
            withJSONObject: config.json,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            log("warning: could not serialize config")
            return
        }
        do {
            try (data + Data("\n".utf8)).write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            log("warning: could not write \(path): \(error.localizedDescription)")
        }
    }
}
