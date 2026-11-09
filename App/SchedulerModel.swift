import AppKit
import Foundation

private let lastRunFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "it_IT")
    formatter.dateFormat = "d MMM yyyy, HH:mm"
    return formatter
}()

private let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "it_IT")
    formatter.dateFormat = "EEEE d MMMM"
    return formatter
}()

@MainActor
final class SchedulerModel: ObservableObject {
    static let shared = SchedulerModel()

    @Published var config = ScheduleConfig()
    @Published var tmStatus = TMStatus()
    @Published var lastRun: LastRun?
    @Published var logLines: [String] = []
    @Published var tmAutoBackup = false
    @Published var tmInterval: Int?
    @Published var destination: TMDestination?
    @Published var installed = false
    @Published var busy = false
    @Published var showRestoreDialog = false
    @Published var errorMessage: String?

    init() {
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Paths.config)),
           let saved = try? JSONDecoder().decode(ScheduleConfig.self, from: data) {
            config = saved
        }
        installed = FileManager.default.fileExists(atPath: Paths.plist)
        refresh()
    }

    func refresh() {
        tmStatus = TMController.status()
        tmAutoBackup = TMController.autoBackupEnabled()
        tmInterval = TMController.autoBackupInterval()
        destination = TMController.destination()
        lastRun = TMController.lastRun()
        logLines = TMController.logTail()
        installed = FileManager.default.fileExists(atPath: Paths.plist)
    }

    func apply() {
        if config.enabled && config.weekdays.isEmpty {
            errorMessage = "Seleziona almeno un giorno della settimana."
            return
        }
        busy = true
        do {
            try SchedulerInstaller.install(config: config)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    func backupNow() {
        guard !tmStatus.running else { return }
        do {
            try TMController.startBackupNow(preventSleep: config.preventSleep)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.refresh()
            }
        } catch {
            errorMessage = "Impossibile avviare il backup: \(error.localizedDescription)"
        }
    }

    func openTimeMachineSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    func restore(frequency: RestoreFrequency) {
        busy = true
        do {
            try SchedulerInstaller.restore(frequency: frequency)
            config = ScheduleConfig()
            refresh()
            if tmAutoBackup != frequency.autoBackup {
                openTimeMachineSettings()
                errorMessage = "Lo scheduler è stato rimosso, ma Time Machine non ha applicato «\(frequency.label)». Impostalo nella pagina appena aperta."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    func openLog() {
        let logURL = URL(fileURLWithPath: Paths.log)
        let target = FileManager.default.fileExists(atPath: Paths.log)
            ? logURL
            : URL(fileURLWithPath: Paths.supportDir)
        NSWorkspace.shared.open(target)
    }

    var nextRunText: String {
        guard config.enabled else { return "Pianificazione disattivata" }
        guard let next = ScheduleLogic.nextRun(after: Date(), config: config) else { return "—" }
        let time = String(format: "%02d:%02d", config.hour, config.minute)
        let calendar = Calendar.current
        if calendar.isDateInToday(next) { return "oggi alle \(time)" }
        if calendar.isDateInTomorrow(next) { return "domani alle \(time)" }
        return "\(dayFormatter.string(from: next)) alle \(time)"
    }

    var lastRunText: String {
        guard let lastRun else { return "Nessun backup registrato" }
        let result: String
        switch lastRun.result {
        case "success": result = "riuscito"
        case "failed": result = "fallito"
        default: result = lastRun.result
        }
        var text = "\(lastRunFormatter.string(from: lastRun.date)) · \(result)"
        if let duration = lastRun.durationSeconds, result != "in corso" {
            let minutes = duration / 60
            text += minutes > 0 ? " · \(minutes) min" : " · \(duration) s"
        }
        return text
    }

    var tmStatusText: String {
        guard tmStatus.running else { return "Inattivo" }
        var text: String
        switch tmStatus.phase {
        case "FindingChanges": text = "Ricerca modifiche"
        case "Copying": text = "Copia in corso"
        case "HealthCheckFsck": text = "Verifica disco"
        case "Stopping": text = "Arresto"
        case let phase?: text = phase
        case nil: text = "In corso"
        }
        if let percent = tmStatus.percent, percent >= 0 {
            text += String(format: " · %.0f%%", percent)
        }
        return text
    }

    var destinationText: String {
        guard let destination else { return "Nessuna destinazione configurata" }
        let kind = destination.kind == "Network" ? "rete" : "locale"
        return "\(destination.name) · \(kind) · \(destination.host ?? destination.url)"
    }

    var tmFrequencyText: String {
        guard tmAutoBackup else { return "Manualmente" }
        switch tmInterval {
        case 3600: return "Ogni ora"
        case 86400: return "Ogni giorno"
        case 604800: return "Ogni settimana"
        case let interval?: return "Ogni \(interval) s"
        case nil: return "Automatica"
        }
    }
}
