import Foundation

/// Ultimo esito scritto dal job e letto dall'app.
struct LastRun: Codable, Equatable {
    var date: Date
    var result: String
    var durationSeconds: Int?
    /// Vero quando il backup è stato fatto con percorsi esclusi perché inaccessibili.
    var limited: Bool?
    var excluded: Int?
}

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
    /// Impedisce lo stand-by mentre il servizio è attivo: con uno sleep breve il Mac
    /// sarebbe addormentato all'orario pianificato.
    var keepAwake = false
    /// Se la sessione è bloccata, esclude temporaneamente `~/Library` di ogni utente
    /// invece di far fallire il backup.
    var limitedBackup = false
    var version = 1

    init() {}

    /// decodeIfPresent: i config.json scritti prima di `keepAwake` devono restare leggibili.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScheduleConfig()
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        hour = try values.decodeIfPresent(Int.self, forKey: .hour) ?? defaults.hour
        minute = try values.decodeIfPresent(Int.self, forKey: .minute) ?? defaults.minute
        weekdays = try values.decodeIfPresent([Int].self, forKey: .weekdays) ?? defaults.weekdays
        requireDestination = try values.decodeIfPresent(Bool.self, forKey: .requireDestination) ?? defaults.requireDestination
        preventSleep = try values.decodeIfPresent(Bool.self, forKey: .preventSleep) ?? defaults.preventSleep
        skipOnBattery = try values.decodeIfPresent(Bool.self, forKey: .skipOnBattery) ?? defaults.skipOnBattery
        notify = try values.decodeIfPresent(Bool.self, forKey: .notify) ?? defaults.notify
        keepAwake = try values.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? defaults.keepAwake
        limitedBackup = try values.decodeIfPresent(Bool.self, forKey: .limitedBackup) ?? defaults.limitedBackup
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version
    }
}

enum Paths {
    static let label = "local.tmscheduler"
    static let supportDir = "/Library/Application Support/TMScheduler"
    static let config = supportDir + "/config.json"
    static let lastRun = supportDir + "/last-run.json"
    static let log = supportDir + "/tmscheduler.log"
    /// Data del risveglio armato con pmset, per poterlo annullare alla disinstallazione.
    static let wakeState = supportDir + "/wake"
    /// Percorsi esclusi temporaneamente per l'ultimo run: se resta, va ripulito all'avvio.
    static let temporaryExclusions = supportDir + "/temporary-exclusions.txt"
    static let daemon = "/usr/local/bin/tmscheduler-daemon"
    /// Esegue il backup singolo su richiesta del daemon (nessuna schedulazione qui).
    static let script = "/usr/local/bin/tmscheduler-run"
    static let plist = "/Library/LaunchDaemons/" + label + ".plist"

    /// Job della 0.1.0, rimosso al primo avvio della versione nuova.
    static let legacyLabel = "local.tmscheduler.nightly"
    static let legacyPlist = "/Library/LaunchDaemons/" + legacyLabel + ".plist"
}

enum ScheduleLogic {
    /// Abbreviazioni dei giorni nel locale di sistema, in ordine ISO (lun … dom).
    static var weekdayNames: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        return (1...7).map { iso in
            symbols[iso == 7 ? 0 : iso].capitalized
        }
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

    /// Vero se `now` è dentro la finestra dell'orario pianificato e quel run non è ancora stato
    /// fatto. La finestra stretta evita il recupero del backup saltato (Mac spento o in sleep).
    static func isDue(
        at now: Date,
        config: ScheduleConfig,
        lastRun: Date?,
        grace: TimeInterval = 60,
        calendar: Calendar = .current
    ) -> Bool {
        guard config.enabled else { return false }
        let weekday = calendar.component(.weekday, from: now)
        let iso = weekday == 1 ? 7 : weekday - 1
        guard config.weekdays.contains(iso) else { return false }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = config.hour
        components.minute = config.minute
        components.second = 0
        guard let slot = calendar.date(from: components) else { return false }

        guard now >= slot, now.timeIntervalSince(slot) < grace else { return false }
        guard let lastRun else { return true }
        return lastRun < slot
    }

    /// Host di una destinazione Time Machine; nil per destinazioni locali (file://).
    static func destinationHost(from url: String) -> String? {
        URL(string: url)?.host
    }

    /// Plist del daemon: parte al boot e launchd lo riavvia se esce. Orari e giorni stanno nel
    /// config.json letto dal processo, non in StartCalendarInterval.
    static func plistData() throws -> Data {
        let plist: [String: Any] = [
            "Label": Paths.label,
            "ProgramArguments": [Paths.daemon],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "StandardErrorPath": "/var/log/tmscheduler.err",
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
