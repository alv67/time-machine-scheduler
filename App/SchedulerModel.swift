import AppKit
import Foundation

private let lastRunFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

private let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
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
            errorMessage = L("error.noWeekday")
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
            errorMessage = L("error.backupStart", error.localizedDescription)
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
                errorMessage = L("error.restoreFrequency", frequency.label)
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
        guard config.enabled else { return L("next.disabled") }
        guard let next = ScheduleLogic.nextRun(after: Date(), config: config) else { return "—" }
        let time = String(format: "%02d:%02d", config.hour, config.minute)
        let calendar = Calendar.current
        if calendar.isDateInToday(next) { return L("next.today", time) }
        if calendar.isDateInTomorrow(next) { return L("next.tomorrow", time) }
        return L("next.date", dayFormatter.string(from: next), time)
    }

    var lastRunText: String {
        guard let lastRun else { return L("lastRun.none") }
        let resultKey: String
        switch lastRun.result {
        case "success": resultKey = "lastRun.success"
        case "failed": resultKey = "lastRun.failed"
        case "running": resultKey = "lastRun.running"
        default: resultKey = "lastRun.result.unknown"
        }
        var text = L("lastRun.format", lastRunFormatter.string(from: lastRun.date), L(resultKey))
        if let duration = lastRun.durationSeconds, lastRun.result != "running" {
            let minutes = duration / 60
            text += minutes > 0 ? L("lastRun.minutes", minutes) : L("lastRun.seconds", duration)
        }
        if lastRun.limited == true {
            text += L("lastRun.limited", lastRun.excluded ?? 0)
        }
        return text
    }

    var tmStatusText: String {
        guard tmStatus.running else { return L("phase.idle") }
        var text: String
        switch tmStatus.phase {
        case "FindingChanges": text = L("phase.findingChanges")
        case "Copying": text = L("phase.copying")
        case "HealthCheckFsck": text = L("phase.healthCheck")
        case "Stopping": text = L("phase.stopping")
        case let phase?: text = phase
        case nil: text = L("phase.running")
        }
        if let percent = tmStatus.percent, percent >= 0 {
            text += L("phase.percent", percent)
        }
        return text
    }

    var destinationText: String {
        guard let destination else { return L("destination.none") }
        let kind = destination.kind == "Network" ? L("destination.network") : L("destination.local")
        return L("destination.format", destination.name, kind, destination.host ?? destination.url)
    }

    var tmFrequencyText: String {
        guard tmAutoBackup else { return L("frequency.manual") }
        switch tmInterval {
        case 3600: return L("frequency.hourly")
        case 86400: return L("frequency.daily")
        case 604800: return L("frequency.weekly")
        case let interval?: return L("frequency.everySeconds", interval)
        case nil: return L("frequency.automatic")
        }
    }
}
