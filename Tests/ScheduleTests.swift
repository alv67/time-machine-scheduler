import Foundation

@main
struct ScheduleTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!

        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }

        // ISO -> tm_wday
        assert(ScheduleLogic.launchdWeekday(iso: 1) == 1)
        assert(ScheduleLogic.launchdWeekday(iso: 6) == 6)
        assert(ScheduleLogic.launchdWeekday(iso: 7) == 0)

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

        // plist: una voce per giorno con conversione corretta
        config.enabled = true
        config.weekdays = [7, 1]
        let data = try! ScheduleLogic.plistData(config: config)
        let plist = try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
        assert(plist["Label"] as? String == Paths.label)
        assert(plist["RunAtLoad"] as? Bool == false)
        assert(plist["ProgramArguments"] as? [String] == ["/bin/bash", Paths.script])

        let intervals = plist["StartCalendarInterval"] as! [[String: Int]]
        assert(intervals.count == 2)
        assert(intervals[0] == ["Weekday": 1, "Hour": 2, "Minute": 0]) // lunedì
        assert(intervals[1] == ["Weekday": 0, "Hour": 2, "Minute": 0]) // domenica

        print("ScheduleLogic: tutti i test superati")
    }
}
