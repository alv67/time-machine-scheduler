import Foundation
import IOKit.pwr_mgt

// Il backup notturno richiede due cose: il Mac sveglio e la sessione sbloccata. Il primo lo
// garantisce l'asserzione di potenza qui sotto; il secondo è un'impostazione dell'utente
// (`screenLock`), perché Time Machine non legge i file di classe A a dispositivo bloccato e
// nessun processo di terzi può cambiarlo: l'asserzione sul keybag non ha effetto senza
// l'entitlement di backupd.

private let tickInterval: TimeInterval = 10
private let dueGrace: TimeInterval = 60
/// Risveglio armato due minuti prima dell'orario pianificato.
private let wakeLead: TimeInterval = 120
/// Salto fra due tick oltre il quale il Mac è andato in stop.
private let sleepThreshold: TimeInterval = 120

private let logURL = URL(fileURLWithPath: Paths.log)

private let clockFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

private func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = formatter.string(from: Date()) + " " + message + "\n"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: logURL) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        FileManager.default.createFile(atPath: logURL.path, contents: data)
    }
}

/// Notifica all'utente davanti al console, come fa lo script a fine backup.
private func notify(_ message: String) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
          let owner = attributes[.ownerAccountID] as? NSNumber,
          owner.uint32Value != 0
    else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = [
        "asuser", String(owner.uint32Value),
        "/usr/bin/osascript", "-e",
        "display notification \"\(message)\" with title \"Time Machine Scheduler\"",
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

/// Stand-by: finché il servizio è attivo e l'opzione è on, il Mac non va in sleep da solo.
/// Lo schermo può comunque spegnersi. Non copre lo stop manuale né il coperchio chiuso.
private enum Power {
    private(set) static var held = false
    private static var id: IOPMAssertionID = 0

    static func preventSleep() {
        guard !held else { return }
        let rc = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "TimeMachineScheduler" as CFString,
            &id
        )
        held = rc == kIOReturnSuccess
        if held {
            log("power: idle sleep prevented")
        } else {
            log("power: cannot prevent sleep, rc=\(rc)")
        }
    }

    static func allowSleep() {
        guard held else { return }
        IOPMAssertionRelease(id)
        held = false
        log("power: idle sleep allowed")
    }
}

private func loadConfig() -> ScheduleConfig? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: Paths.config)) else { return nil }
    return try? JSONDecoder().decode(ScheduleConfig.self, from: data)
}

private func lastRunDate() -> Date? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: Paths.lastRun)) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(LastRun.self, from: data))?.date
}

private func spawnRun() -> Process? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [Paths.script]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        return process
    } catch {
        log("run: cannot start \(Paths.script): \(error.localizedDescription)")
        return nil
    }
}

@discardableResult
private func execute(_ path: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return -1
    }
    process.waitUntilExit()
    return process.terminationStatus
}

/// Formato accettato da `pmset schedule`.
private func wakeStamp(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
    return formatter.string(from: date)
}

/// Un risveglio programmato non sopravvive a un riavvio del Mac, quindi va riarmato a ogni
/// avvio; se cambia l'orario si annulla il precedente per non accumularli.
private func armWake(for slot: Date, now: Date, armed: inout String?) {
    let wakeAt = slot.addingTimeInterval(-wakeLead)
    guard wakeAt > now else { return }
    let stamp = wakeStamp(for: wakeAt)
    guard stamp != armed else { return }
    if let previous = armed {
        execute("/usr/bin/pmset", ["schedule", "cancel", "wake", previous])
    }
    execute("/usr/bin/pmset", ["schedule", "wake", stamp])
    armed = stamp
    try? (stamp + "\n").write(toFile: Paths.wakeState, atomically: true, encoding: .utf8)
    log("wake: armed for \(stamp)")
}

log("daemon start")

var config = loadConfig() ?? ScheduleConfig()
var lastTick = Date()
var lastAttempt = Date.distantPast
var armedWake: String?
var job: Process?

while true {
    let now = Date()
    if let fresh = loadConfig() {
        config = fresh
    }

    if config.keepAwake {
        Power.preventSleep()
    } else {
        Power.allowSleep()
    }

    // Il Mac è andato in stop: il run di quella notte è perso, e recuperarlo al risveglio
    // non ha senso (Time Machine ripartirebbe a metà mattina).
    if now.timeIntervalSince(lastTick) > sleepThreshold,
       let missed = ScheduleLogic.nextRun(after: lastTick, config: config),
       missed <= now {
        let time = clockFormatter.string(from: missed)
        log("missed: Mac asleep at \(time)")
        notify("Backup missed at \(time): the Mac was asleep")
        lastAttempt = now
    }
    lastTick = now

    if let next = ScheduleLogic.nextRun(after: now, config: config) {
        armWake(for: next, now: now, armed: &armedWake)
    }

    if job?.isRunning != true {
        job = nil
        if now.timeIntervalSince(lastAttempt) >= dueGrace,
           ScheduleLogic.isDue(at: now, config: config, lastRun: lastRunDate(), grace: dueGrace) {
            lastAttempt = now
            log("run: due, starting backup")
            // Il processo va trattenuto: se lo si lascia cadere il figlio viene terminato.
            if let process = spawnRun() {
                job = process
            }
        }
    }

    Thread.sleep(forTimeInterval: tickInterval)
}
