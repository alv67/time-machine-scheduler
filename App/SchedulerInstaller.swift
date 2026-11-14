import Foundation

enum InstallerError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return L("error.cancelled")
        case .failed(let message): return message
        }
    }
}

enum RestoreFrequency: String, CaseIterable, Identifiable {
    case manual, hourly, daily, weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return L("frequency.manual")
        case .hourly: return L("frequency.hourly")
        case .daily: return L("frequency.daily")
        case .weekly: return L("frequency.weekly")
        }
    }

    var autoBackup: Bool { self != .manual }

    var interval: Int? {
        switch self {
        case .manual: return nil
        case .hourly: return 3600
        case .daily: return 86400
        case .weekly: return 604800
        }
    }
}

enum SchedulerInstaller {
    static func install(config: ScheduleConfig) throws {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory.appendingPathComponent("tmscheduler-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temp) }

        guard let scriptURL = Bundle.main.url(forResource: "tmscheduler-run", withExtension: "sh") else {
            throw InstallerError.failed(L("error.missingScript"))
        }
        guard let daemonURL = Bundle.main.url(forResource: "tmscheduler-daemon", withExtension: nil) else {
            throw InstallerError.failed(L("error.missingScript"))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: temp.appendingPathComponent("config.json"))
        try fileManager.copyItem(at: scriptURL, to: temp.appendingPathComponent("tmscheduler-run"))
        try fileManager.copyItem(at: daemonURL, to: temp.appendingPathComponent("tmscheduler-daemon"))
        try ScheduleLogic.plistData().write(to: temp.appendingPathComponent(Paths.label + ".plist"))

        let installPlist = config.enabled
            ? """
            /usr/bin/install -m 644 '\(temp.path)/\(Paths.label).plist' '\(Paths.plist)'
            /bin/launchctl bootstrap system '\(Paths.plist)'
            """
            : "/bin/rm -f '\(Paths.plist)'"

        // I binari nuovi esistono prima del bootout: se qualcosa fallisce non resti senza daemon.
        let script = """
        #!/bin/bash
        set -euo pipefail
        /usr/bin/install -d -m 755 '\(Paths.supportDir)'
        /usr/bin/install -m 755 '\(temp.path)/tmscheduler-daemon' '\(Paths.daemon)'
        /usr/bin/install -m 755 '\(temp.path)/tmscheduler-run' '\(Paths.script)'
        /usr/bin/install -m 644 '\(temp.path)/config.json' '\(Paths.config)'
        /bin/launchctl bootout system/\(Paths.legacyLabel) >/dev/null 2>&1 || true
        /bin/rm -f '\(Paths.legacyPlist)'
        /bin/launchctl bootout system/\(Paths.label) >/dev/null 2>&1 || true
        /bin/sleep 1
        \(installPlist)
        """
        try runScript(script)
    }

    /// Rimuove daemon, script e job (anche quello della 0.1.0) e riporta Time Machine alla
    /// frequenza scelta.
    static func restore(frequency: RestoreFrequency) throws {
        var lines = [
            "#!/bin/bash",
            "set -uo pipefail",
            "/bin/launchctl bootout system/\(Paths.label) >/dev/null 2>&1 || true",
            "/bin/launchctl bootout system/\(Paths.legacyLabel) >/dev/null 2>&1 || true",
            "/bin/rm -f '\(Paths.plist)'",
            "/bin/rm -f '\(Paths.legacyPlist)'",
            "/bin/rm -f '\(Paths.daemon)'",
            "/bin/rm -f '\(Paths.script)'",
            // Il daemon arma un risveglio: senza questo resterebbe in lista anche dopo la rimozione.
            "if [ -f '\(Paths.wakeState)' ]; then /usr/bin/pmset schedule cancel wake \"$(/bin/cat '\(Paths.wakeState)')\" >/dev/null 2>&1 || true; fi",
            "/bin/rm -rf '\(Paths.supportDir)'",
        ]
        if frequency.autoBackup, let interval = frequency.interval {
            lines.append("/usr/bin/defaults write /Library/Preferences/com.apple.TimeMachine AutoBackup -bool true || exit 1")
            lines.append("/usr/bin/defaults write /Library/Preferences/com.apple.TimeMachine AutoBackupInterval -int \(interval) || exit 1")
        } else {
            lines.append("/usr/bin/defaults write /Library/Preferences/com.apple.TimeMachine AutoBackup -bool false || exit 1")
        }
        lines.append("exit 0")
        try runScript(lines.joined(separator: "\n"))
    }

    private static func runScript(_ content: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tmscheduler-\(UUID().uuidString).sh")
        try (content + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        defer { try? FileManager.default.removeItem(at: url) }
        try TMController.runPrivileged("/bin/bash '\(url.path)'")
    }
}
