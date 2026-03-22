import Cocoa
import Foundation

let configPath = NSHomeDirectory() + "/.config/appblocker/blocked.txt"
let logPath    = NSHomeDirectory() + "/.config/appblocker/appblocker.log"

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    NSLog("AppBlocker: %@", msg)
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.data(using: .utf8)!.write(to: URL(fileURLWithPath: logPath), options: .atomic)
    }
}

func loadBlockedApps() -> Set<String> {
    guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
        return []
    }
    let ids = content
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    return Set(ids)
}

var blockedApps = loadBlockedApps()
log("Started — watching \(blockedApps.count) blocked bundle IDs")

for app in NSWorkspace.shared.runningApplications {
    guard let bid = app.bundleIdentifier else { continue }
    if blockedApps.contains(bid) {
        log("Killing already-running: \(bid) (\(app.localizedName ?? "?"))")
        app.forceTerminate()
    }
}

let observer = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    guard
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                  as? NSRunningApplication,
        let bid = app.bundleIdentifier
    else { return }

    blockedApps = loadBlockedApps()

    if blockedApps.contains(bid) {
        log("Blocked launch: \(bid) (\(app.localizedName ?? "?"))")
        app.forceTerminate()
    }
}

RunLoop.main.run()
