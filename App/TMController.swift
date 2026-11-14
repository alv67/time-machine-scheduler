import AppKit
import Foundation

struct TMStatus: Equatable {
    var running = false
    var phase: String?
    var percent: Double?
}

struct TMDestination: Equatable {
    var name: String
    var kind: String
    var url: String
    var host: String?
}

enum TMController {
    /// Esegue un comando e ne restituisce lo stdout (stringa vuota in caso di errore).
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func status() -> TMStatus {
        let output = run("/usr/bin/tmutil", ["status", "-X"])
        guard let data = output.data(using: .utf8),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        else { return TMStatus() }

        var status = TMStatus()
        if let running = plist["Running"] as? Bool {
            status.running = running
        } else if let running = plist["Running"] as? Int {
            status.running = running == 1
        }
        status.phase = plist["BackupPhase"] as? String
        if let percent = plist["Percent"] as? Double {
            status.percent = percent
        } else if let percent = plist["Percent"] as? Int {
            status.percent = Double(percent)
        }
        return status
    }

    static func autoBackupEnabled() -> Bool {
        run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.TimeMachine", "AutoBackup"])
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    static func autoBackupInterval() -> Int? {
        Int(run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.TimeMachine", "AutoBackupInterval"])
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Destinazione Time Machine attualmente in uso (letta da tmutil, nessun dato hardcoded).
    static func destination() -> TMDestination? {
        let output = run("/usr/bin/tmutil", ["destinationinfo", "-X"])
        guard let data = output.data(using: .utf8),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let destinations = plist["Destinations"] as? [[String: Any]],
              !destinations.isEmpty
        else { return nil }

        let selected = destinations.first { ($0["LastDestination"] as? Int) == 1 } ?? destinations[0]
        let url = selected["URL"] as? String ?? ""
        return TMDestination(
            name: selected["Name"] as? String ?? "Senza nome",
            kind: selected["Kind"] as? String ?? "",
            url: url,
            host: ScheduleLogic.destinationHost(from: url)
        )
    }

    static func lastRun() -> LastRun? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Paths.lastRun)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LastRun.self, from: data)
    }

    static func logTail(maxLines: Int = 200) -> [String] {
        guard let text = try? String(contentsOfFile: Paths.log, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(maxLines)).map(String.init)
    }

    /// Avvia subito un backup senza bloccare la UI (il completamento si segue con status()).
    static func startBackupNow(preventSleep: Bool) throws {
        let process = Process()
        if preventSleep {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            process.arguments = ["-i", "/usr/bin/tmutil", "startbackup", "--auto", "--block"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
            process.arguments = ["startbackup", "--auto", "--block"]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Esegue un comando shell come amministratore (prompt di password di macOS).
    static func runPrivileged(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            throw InstallerError.failed(L("error.scriptCreate"))
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -128 { throw InstallerError.cancelled }
            let message = error[NSAppleScript.errorMessage] as? String ?? L("error.unknown")
            throw InstallerError.failed(message)
        }
    }
}
