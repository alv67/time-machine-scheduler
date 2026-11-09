import Foundation

/// Configurazione scritta dall'app e letta dal daemon.
/// weekdays usa ISO-8601: 1 = lunedì … 7 = domenica.
struct ScheduleConfig: Codable, Equatable {
    var enabled = true
    var hour = 2
    var minute = 0
    var weekdays = [1, 2, 3, 4, 5, 6, 7]
    var requireDestination = true
    var preventSleep = true
    var skipOnBattery = false
    var notify = true
    var version = 1
}

enum Paths {
    static let label = "local.tmscheduler.nightly"
    static let supportDir = "/Library/Application Support/TMScheduler"
    static let config = supportDir + "/config.json"
    static let lastRun = supportDir + "/last-run.json"
    static let log = supportDir + "/tmscheduler.log"
    static let script = "/usr/local/bin/tmscheduler-run"
    static let plist = "/Library/LaunchDaemons/" + label + ".plist"
}

enum ScheduleLogic {
    /// Abbreviazioni dei giorni nel locale di sistema, in ordine ISO (lun … dom).
    static var weekdayNames: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        return (1...7).map { iso in
            symbols[iso == 7 ? 0 : iso].capitalized
        }
    }

    /// launchd usa tm_wday: 0 = domenica … 6 = sabato.
    static func launchdWeekday(iso: Int) -> Int {
        iso == 7 ? 0 : iso
    }

    /// Prossima occorrenza della pianificazione dopo `now`, o nil se disattivata.
    static func nextRun(after now: Date, config: ScheduleConfig, calendar: Calendar = .current) -> Date? {
        guard config.enabled, !config.weekdays.isEmpty else { return nil }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: day) // 1 = domenica
            let iso = weekday == 1 ? 7 : weekday - 1
            guard config.weekdays.contains(iso) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = config.hour
            components.minute = config.minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else { continue }
            if candidate > now { return candidate }
        }
        return nil
    }

    /// Host di una destinazione Time Machine; nil per destinazioni locali (file://).
    static func destinationHost(from url: String) -> String? {
        URL(string: url)?.host
    }

    /// Plist del LaunchDaemon, con una voce StartCalendarInterval per ogni giorno scelto.
    static func plistData(config: ScheduleConfig) throws -> Data {
        let intervals = config.weekdays.sorted().map { iso in
            ["Weekday": launchdWeekday(iso: iso), "Hour": config.hour, "Minute": config.minute]
        }
        let plist: [String: Any] = [
            "Label": Paths.label,
            "ProgramArguments": ["/bin/bash", Paths.script],
            "StartCalendarInterval": intervals,
            "RunAtLoad": false,
            "StandardErrorPath": "/var/log/tmscheduler.err",
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
