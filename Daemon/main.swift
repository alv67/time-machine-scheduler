import Darwin
import Foundation
import IOKit.pwr_mgt

// Daemon unico: tiene l'assertion sul keybag mentre la macchina è sbloccata e all'orario
// pianificato lancia `tmscheduler-run` (che fa il backup). Senza assertion Time Machine non
// completa un backup avviato a schermo bloccato (BACKUP_FAILED_DEVICE_LOCKED).

private let tickInterval: TimeInterval = 10
private let renewInterval: TimeInterval = 300
private let dueGrace: TimeInterval = 60

private let logURL = URL(fileURLWithPath: Paths.log)

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

/// API privata di MobileKeyBag, caricata a runtime: se il simbolo sparisce il daemon continua a
/// schedulare (il backup fallirà a dispositivo bloccato) invece di non partire.
private enum Keybag {
    private typealias TakeFn = @convention(c) (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> Int32

    private static let takeFn: TakeFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MobileKeyBag.framework/MobileKeyBag", RTLD_NOW),
              let symbol = dlsym(handle, "MKBDeviceLockAssertion")
        else { return nil }
        return unsafeBitCast(symbol, to: TakeFn.self)
    }()

    static var available: Bool { takeFn != nil }

    /// `options` deve essere un dizionario (NULL fa crashare la funzione). L'assertion vive finché
    /// il processo la trattiene e si rilascia con CFRelease.
    static func take() -> CFTypeRef? {
        guard let takeFn else { return nil }
        var assertion: CFTypeRef?
        guard takeFn(NSDictionary() as CFDictionary, &assertion) == 0 else { return nil }
        return assertion
    }
}

/// Stand-by: finché il servizio è attivo e l'opzione è on, il Mac non va in sleep da solo.
/// Lo schermo può comunque spegnersi.
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

private let clockFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

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

if CommandLine.arguments.contains("--test-assertion") {
    guard Keybag.available else { print("assertion: symbol missing"); exit(2) }
    var held = Keybag.take()
    guard held != nil else { print("assertion: failed"); exit(1) }
    print("assertion: taken")
    Thread.sleep(forTimeInterval: 2)
    held = nil
    print("assertion: released")
    exit(0)
}

// Solo per verificare il percorso degradato: il daemon si comporta come se il
// simbolo non esistesse e salta i run invece di farli fallire a schermo bloccato.
let keybagEnabled = !CommandLine.arguments.contains("--no-keybag")

log("daemon start (keybag assertion: \(keybagEnabled ? (Keybag.available ? "available" : "missing symbol") : "disabled by flag"))")

var config = loadConfig() ?? ScheduleConfig()
var assertion: CFTypeRef?
var lastRenewal = Date.distantPast
var lastAttempt = Date.distantPast
var pendingSkip: Date?
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

    if assertion == nil {
        if keybagEnabled, let taken = Keybag.take() {
            assertion = taken
            lastRenewal = now
            log("keybag: assertion taken")
            // Il run saltato si annuncia quando qualcuno sblocca, non alle 02:00.
            if let skipped = pendingSkip {
                pendingSkip = nil
                let time = clockFormatter.string(from: skipped)
                log("notify: run skipped at \(time), device was locked")
                notify("Backup skipped at \(time): the Mac was locked")
            }
        }
    } else if now.timeIntervalSince(lastRenewal) >= renewInterval {
        // Nuova assertion prima di rilasciare la vecchia: nessun buco.
        if let taken = Keybag.take() {
            assertion = taken
            lastRenewal = now
        } else {
            log("keybag: renewal failed")
        }
    }

    if job?.isRunning != true {
        job = nil
        if now.timeIntervalSince(lastAttempt) >= dueGrace,
           ScheduleLogic.isDue(at: now, config: config, lastRun: lastRunDate(), grace: dueGrace) {
            lastAttempt = now
            if assertion == nil {
                // Senza asserzione le chiavi di classe A sono perse: il backup fallirebbe
                // dopo ~20 minuti. Meglio dirlo subito, senza avviarlo.
                log("skip: keybag locked, login required")
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
