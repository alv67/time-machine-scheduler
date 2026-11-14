import Foundation

@main
struct ScheduleTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!

        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }

        // host ricavato dalla destinazione Time Machine
        assert(ScheduleLogic.destinationHost(from: "smb://utente@nas._smb._tcp.local./Backup") == "nas._smb._tcp.local.")
        assert(ScheduleLogic.destinationHost(from: "smb://utente@192.168.1.251/Backup") == "192.168.1.251")
        assert(ScheduleLogic.destinationHost(from: "file:///Volumes/Backup") == nil)

        var config = ScheduleConfig()
        config.weekdays = [1, 2, 3, 4, 5, 6, 7]
        config.hour = 2
        config.minute = 0

        // lunedì 9 nov 2026, 20:00 -> martedì 10 nov, 02:00
        let now = date(2026, 11, 9, 20, 0)
        assert(ScheduleLogic.nextRun(after: now, config: config, calendar: calendar) == date(2026, 11, 10, 2, 0))

        // lunedì 9 nov, 01:00 -> stesso giorno alle 02:00
        assert(ScheduleLogic.nextRun(after: date(2026, 11, 9, 1, 0), config: config, calendar: calendar) == date(2026, 11, 9, 2, 0))

        // solo lunedì, ora passata -> lunedì successivo
        config.weekdays = [1]
        assert(ScheduleLogic.nextRun(after: now, config: config, calendar: calendar) == date(2026, 11, 16, 2, 0))

        // disattivata -> nessuna occorrenza
        config.enabled = false
        assert(ScheduleLogic.nextRun(after: now, config: config, calendar: calendar) == nil)

        // plist del daemon: parte al boot, launchd lo riavvia, nessuna schedulazione in launchd
        let data = try! ScheduleLogic.plistData()
        let plist = try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
        assert(plist["Label"] as? String == Paths.label)
        assert(plist["RunAtLoad"] as? Bool == true)
        assert(plist["KeepAlive"] as? Bool == true)
        assert(plist["ProgramArguments"] as? [String] == [Paths.daemon])
        assert(plist["StartCalendarInterval"] == nil)

        // isDue: la finestra è stretta, il backup saltato non si recupera
        config = ScheduleConfig()
        config.weekdays = [1, 2, 3, 4, 5, 6, 7]
        config.hour = 2
        config.minute = 0
        let slot = date(2026, 11, 10, 2, 0) // martedì
        let at = { (seconds: Int) in slot.addingTimeInterval(TimeInterval(seconds)) }

        assert(ScheduleLogic.isDue(at: at(0), config: config, lastRun: nil, calendar: calendar))
        assert(ScheduleLogic.isDue(at: at(30), config: config, lastRun: date(2026, 11, 9, 2, 4), calendar: calendar))
        assert(!ScheduleLogic.isDue(at: at(90), config: config, lastRun: nil, calendar: calendar))
        assert(!ScheduleLogic.isDue(at: at(-30), config: config, lastRun: nil, calendar: calendar))
        // già eseguito in questa finestra
        assert(!ScheduleLogic.isDue(at: at(30), config: config, lastRun: at(10), calendar: calendar))
        // giorno non pianificato
        config.weekdays = [3]
        assert(!ScheduleLogic.isDue(at: at(0), config: config, lastRun: nil, calendar: calendar))
        // servizio spento
        config.weekdays = [1, 2, 3, 4, 5, 6, 7]
        config.enabled = false
        assert(!ScheduleLogic.isDue(at: at(0), config: config, lastRun: nil, calendar: calendar))

        // config.json scritto prima di keepAwake: manca la chiave, il resto resta
        let legacy = """
        {"enabled":true,"hour":3,"minute":30,"weekdays":[2],"requireDestination":false,
         "preventSleep":false,"skipOnBattery":true,"notify":false,"version":1}
        """
        let decoded = try! JSONDecoder().decode(ScheduleConfig.self, from: Data(legacy.utf8))
        assert(decoded.keepAwake == false)
        assert(decoded.hour == 3 && decoded.minute == 30 && decoded.weekdays == [2])
        assert(decoded.requireDestination == false && decoded.skipOnBattery == true)

        var roundTrip = decoded
        roundTrip.keepAwake = true
        let encoded = try! JSONEncoder().encode(roundTrip)
        let back = try! JSONDecoder().decode(ScheduleConfig.self, from: encoded)
        assert(back == roundTrip)

        print("ScheduleLogic: tutti i test superati")
    }
}
