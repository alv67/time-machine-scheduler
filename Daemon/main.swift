import CoreGraphics
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

/// Utente al console, o nil quando /dev/console non appartiene a nessuno.
private func consoleUID() -> uid_t? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
          let owner = attributes[.ownerAccountID] as? NSNumber,
          owner.uint32Value != 0
    else { return nil }
    return uid_t(owner.uint32Value)
}

/// Sonda Full Disk Access: la lancia il demone perché solo nel suo contesto launchd la
/// scrittura è attribuita a lui — da un'app sarebbe attribuita all'app e l'esito falso.
private func probeFDA() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [Paths.script, "--fda-check"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

private func writeFDAState(_ ok: Bool) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(FDAState(fda: ok, checked: Date())) else { return }
    try? data.write(to: URL(fileURLWithPath: Paths.fdaState))
}

private func logFDA(_ ok: Bool) {
    log(ok ? "fda: ok" : "fda: denied - grant Full Disk Access to \(Paths.daemon)")
}

/// Possedere `/dev/console` non basta: a pagina di login il device node può restare
/// intestato a un utente loggato in background. Lo stato vero lo sa solo la sessione,
/// quindi lo si chiede dentro di essa con lo stesso binario (`--session-state`).
private func userAtConsole() -> Bool {
    guard let uid = consoleUID() else { return false }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["asuser", String(uid), CommandLine.arguments[0], "--session-state"]
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
        try process.run()
    } catch {
        return false
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.contains("onconsole=1")
}

// `--session-state`: stampa lo stato della sessione in cui gira. Va invocato dentro la
// sessione dell'utente (`launchctl asuser`): un demone di sistema non ne ha una.
if CommandLine.arguments.contains("--session-state") {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
        print("onconsole=0 locked=1")
        exit(0)
    }
    let onConsole = (session["kCGSSessionOnConsoleKey"] as? Bool)
        ?? ((session["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue ?? false)
    let locked = (session["CGSSessionScreenIsLocked"] as? Bool)
        ?? ((session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false)
    print("onconsole=\(onConsole ? 1 : 0) locked=\(locked ? 1 : 0)")
    exit(0)
}

log("daemon start")

var config = loadConfig() ?? ScheduleConfig()
var lastTick = Date()
var lastAttempt = Date.distantPast
var pendingSkip: Date?
var armedWake: String?
var job: Process?
var lastFDAProbe = Date.distantPast
var lastFDAOK: Bool?

// La sonda parte subito, così l'app vede lo stato appena aperta.
if config.limitedBackup {
    lastFDAOK = probeFDA()
    lastFDAProbe = Date()
    writeFDAState(lastFDAOK!)
    logFDA(lastFDAOK!)
}

while true {
    let now = Date()
    if let fresh = loadConfig() {
        config = fresh
    }

    let next = ScheduleLogic.nextRun(after: now, config: config)

    // Con `keepAwake` il Mac resta sveglio per tutto il servizio. Senza, il risveglio
    // armato lo porta in DarkWake ~2 minuti prima dello slot e senza un'asserzione si
    // riaddormenta (~45 s) prima che arrivi l'orario: la si tiene solo in quella
    // finestra, fino a quando il run non è partito.
    let inWakeWindow = next.map {
        ScheduleLogic.isWakeWindow(at: now, slot: $0, lead: wakeLead, grace: dueGrace)
    } ?? false
    if config.keepAwake || inWakeWindow {
        Power.preventSleep()
    } else {
        Power.allowSleep()
    }

    // Il Mac è andato in stop. Un risveglio pmset può capitare ancora dentro la
    // finestra utile: quel run si fa lo stesso, e recuperarlo a metà mattina non ha
    // senso comunque — "missed" solo quando la finestra è davvero passata.
    if now.timeIntervalSince(lastTick) > sleepThreshold,
       let missed = ScheduleLogic.nextRun(after: lastTick, config: config),
       ScheduleLogic.isMissedSlot(at: now, slot: missed, grace: dueGrace) {
        let time = clockFormatter.string(from: missed)
        log("missed: Mac asleep at \(time)")
        notify("Backup missed at \(time): the Mac was asleep")
        lastAttempt = now
    }
    lastTick = now

    // Il run saltato per assenza di sessione si annuncia quando qualcuno rientra:
    // alle 02:00 non c'è nessuno che possa vedere la notifica.
    if let skipped = pendingSkip, userAtConsole() {
        pendingSkip = nil
        let time = clockFormatter.string(from: skipped)
        log("notify: run skipped at \(time), no user was logged in")
        notify("Backup skipped at \(time): no user was logged in")
    }

    if let next {
        armWake(for: next, now: now, armed: &armedWake)
    }

    // Sonda Full Disk Access ogni 10 minuti finché l'opzione è accesa, così l'app vede
    // anche quando il permesso viene concesso. Il log dice solo i cambi di stato.
    if config.limitedBackup, job?.isRunning != true,
       now.timeIntervalSince(lastFDAProbe) > 600 {
        let ok = probeFDA()
        lastFDAProbe = now
        writeFDAState(ok)
        if ok != lastFDAOK {
            lastFDAOK = ok
            logFDA(ok)
        }
    }

    if job?.isRunning != true {
        job = nil
        if now.timeIntervalSince(lastAttempt) >= dueGrace,
           ScheduleLogic.isDue(at: now, config: config, lastRun: lastRunDate(), grace: dueGrace) {
            lastAttempt = now
            if !userAtConsole() {
                // A pagina di login Time Machine fallisce sempre (RESULT 80) dopo minuti
                // di copia: meglio non avviarlo e dirlo.
                log("skip: no user at the console")
                pendingSkip = now
            } else {
                log("run: due, starting backup")
                // Il processo va trattenuto: se lo si lascia cadere il figlio viene terminato.
                if let process = spawnRun() {
                    job = process
                }
            }
        }
    }

    Thread.sleep(forTimeInterval: tickInterval)
}
