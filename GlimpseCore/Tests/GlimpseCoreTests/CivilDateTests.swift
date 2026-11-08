import Foundation
import Testing

@testable import GlimpseCore

func fixedCalendar(_ zone: String = "America/Los_Angeles", firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.locale = Locale(identifier: "en_US")
    calendar.firstWeekday = firstWeekday
    return calendar
}

func civil(_ iso: String) -> CivilDate { CivilDate(iso: iso)! }

func clock(_ hhmm: String) -> ClockTime { ClockTime(hhmm: hhmm)! }

/// A wall-clock instant in `calendar`, e.g. `instant("2026-11-12", "14:30")`.
func instant(_ iso: String, _ hhmm: String, _ calendar: Calendar = fixedCalendar()) -> Date {
    let day = civil(iso)
    let time = clock(hhmm)
    return calendar.date(from: DateComponents(
        year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute
    ))!
}

struct CivilDateTests {
    @Test
    func parsesStrictISO() {
        let date = CivilDate(iso: "2026-11-08")
        #expect(date?.year == 2026)
        #expect(date?.month == 11)
        #expect(date?.day == 8)
        #expect(date?.iso == "2026-11-08")
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "26-1-1", "2026-11-08T00:00", "2026-11-08 ", " 2026-11-08",
                      "2026-1-08", "abcd-ef-gh", "", "2026-00-10", "2026-11-00", "-2026-11-08", "2026-+1-08"])
    func rejectsMalformedOrInvalidISO(_ text: String) {
        #expect(CivilDate(iso: text) == nil)
    }

    @Test
    func leapYearsFollowGregorianRules() {
        #expect(CivilDate(iso: "2028-02-29") != nil)
        #expect(CivilDate(iso: "2100-02-29") == nil)
        #expect(CivilDate(iso: "2000-02-29") != nil)
    }

    @Test
    func dayNumberRoundTripsAndKnowsWeekdays() {
        #expect(civil("1970-01-01").dayNumber == 0)
        #expect(civil("1970-01-01").weekday == 5)  // Thursday
        #expect(civil("2026-11-08").weekday == 1)  // Sunday
        #expect(civil("1969-12-31").weekday == 4)  // Wednesday, negative day number
        for iso in ["1900-03-01", "2000-02-29", "2026-11-08", "2400-12-31", "1601-01-01"] {
            let date = civil(iso)
            #expect(CivilDate(dayNumber: date.dayNumber) == date)
        }
        #expect(CivilDate.daysBetween(civil("2026-11-08"), civil("2027-03-01")) == 113)
        #expect(civil("2026-12-31").adding(days: 1) == civil("2027-01-01"))
    }

    @Test
    func ordersChronologically() {
        #expect(civil("2026-11-08") < civil("2026-11-09"))
        #expect(civil("2026-12-31") < civil("2027-01-01"))
        #expect(!(civil("2026-11-08") < civil("2026-11-08")))
    }

    @Test(arguments: ["America/Los_Angeles", "Europe/Berlin", "Pacific/Kiritimati", "Etc/GMT+12", "America/Sao_Paulo"])
    func resolvesToStartOfLocalDayWithoutDrift(_ zone: String) {
        let calendar = fixedCalendar(zone)
        // DST transitions in both hemispheres plus an ordinary day.
        for iso in ["2026-03-08", "2026-03-29", "2026-10-25", "2026-11-01", "2026-11-08", "2018-11-04"] {
            let date = civil(iso)
            guard let start = date.date(in: calendar) else {
                Issue.record("\(iso) unresolved in \(zone)")
                continue
            }
            #expect(CivilDate(start, calendar: calendar) == date)
            #expect(calendar.startOfDay(for: start) == start)
        }
    }

    @Test
    func localDayNearMidnightIsNotUTC() {
        // 23:30 on Nov 8 in UTC-12 is Nov 9 in UTC; the civil date stays local.
        let calendar = fixedCalendar("Etc/GMT+12")
        let lateEvening = instant("2026-11-08", "23:30", calendar)
        #expect(CivilDate(lateEvening, calendar: calendar) == civil("2026-11-08"))
        // 00:30 on Nov 9 in UTC+14 is still Nov 8 in UTC.
        let kiritimati = fixedCalendar("Pacific/Kiritimati")
        let earlyMorning = instant("2026-11-09", "00:30", kiritimati)
        #expect(CivilDate(earlyMorning, calendar: kiritimati) == civil("2026-11-09"))
    }

    @Test
    func clockTimeParsesStrict24Hour() {
        #expect(ClockTime(hhmm: "14:30")?.minutesSinceMidnight == 870)
        #expect(ClockTime(hhmm: "9:05") == ClockTime(hour: 9, minute: 5))
        for bad in ["24:00", "12:60", "2pm", "12:5", "123:00", "", "12:30:00", "-1:00"] {
            #expect(ClockTime(hhmm: bad) == nil, "\(bad)")
        }
        #expect(clock("09:00") < clock("13:00"))
    }
}
