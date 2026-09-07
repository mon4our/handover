import Foundation

// MARK: - Logging

let logPath = ("~/Library/Logs/headphone-disconnect.log" as NSString).expandingTildeInPath

private let logFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

/// Appends to the log file so the menu bar app (whose stdout goes nowhere when launched from
/// Finder) and the CLI end up in the same place. Also echoes to a terminal when there is one.
private let logHandle: FileHandle? = {
    let manager = FileManager.default
    let directory = (logPath as NSString).deletingLastPathComponent
    try? manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
    if !manager.fileExists(atPath: logPath) {
        manager.createFile(atPath: logPath, contents: nil)
    }
    // Keep the file from growing forever; this runs for months at a time.
    if let size = (try? manager.attributesOfItem(atPath: logPath)[.size]) as? Int, size > 2_000_000 {
        try? Data().write(to: URL(fileURLWithPath: logPath))
    }
    guard let handle = FileHandle(forWritingAtPath: logPath) else { return nil }
    handle.seekToEndOfFile()
    return handle
}()

func log(_ message: String) {
    let line = "\(logFormatter.string(from: Date()))  \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if isatty(1) != 0 {
        FileHandle.standardOutput.write(data)
    }
    logHandle?.write(data)
}
