import Foundation
import Testing

@testable import GlimpseCore

/// Fixed-zone fixtures so "today" and DST never depend on the test machine.
enum MeetingFixtures {
    static func calendar(_ zone: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    /// A wall time on the fixture day, 2026-11-10.
    static func date(
        _ hour: Int, _ minute: Int = 0, _ second: Int = 0, in calendar: Calendar = calendar()
    ) -> Date {
        on(2026, 11, 10, hour, minute, second, in: calendar)
    }

    static func on(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int = 0, _ second: Int = 0, in calendar: Calendar = calendar()
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )) ?? .distantPast
    }

    static func event(
        _ title: String, _ start: Date, _ end: Date, allDay: Bool = false, busy: Bool = true,
        declined: Bool = false, link: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: title, title: title, startDate: start, endDate: end, isAllDay: allDay,
            blocksTime: busy && !allDay, isDeclined: declined,
            meetingLink: link.flatMap(URL.init(string:)).flatMap(MeetingLink.init(url:))
        )
    }
}

struct NextMeetingSelectorTests {
    private let calendar = MeetingFixtures.calendar()
    private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        MeetingFixtures.date(hour, minute, second, in: calendar)
    }
    private func event(_ title: String, _ start: (Int, Int), _ end: (Int, Int),
                       declined: Bool = false, busy: Bool = true) -> CalendarEvent {
        MeetingFixtures.event(title, at(start.0, start.1), at(end.0, end.1), busy: busy, declined: declined)
    }

    @Test
    func noEventsOrNothingLeftIsNil() {
        #expect(NextMeetingSelector.select([], now: at(9), calendar: calendar) == nil)
        let morning = [event("Standup", (9, 0), (9, 15))]
        #expect(NextMeetingSelector.select(morning, now: at(9, 15), calendar: calendar) == nil)
        #expect(NextMeetingSelector.select(morning, now: at(17), calendar: calendar) == nil)
    }

    @Test
    func picksTheSoonestUpcomingWithRoundedUpMinutes() {
        let events = [event("Review", (13, 0), (14, 0)), event("Standup", (10, 0), (10, 30))]
        let next = NextMeetingSelector.select(events, now: at(9, 48), calendar: calendar)
        #expect(next == NextMeeting(event: events[1], phase: .upcoming(minutesUntil: 12)))
        #expect(next?.isImminent == false)
        // 4 min 30 s away still reads 5 minutes and is imminent.
        let soon = NextMeetingSelector.select(events, now: at(9, 55, 30), calendar: calendar)
        #expect(soon?.phase == .upcoming(minutesUntil: 5))
        #expect(soon?.isImminent == true)
        // 1 second away is 1 minute, never 0.
        #expect(NextMeetingSelector.select(events, now: at(9, 59, 59), calendar: calendar)?.phase
            == .upcoming(minutesUntil: 1))
    }

    @Test
    func imminentBoundaryIsFiveMinutes() {
        let events = [event("Standup", (10, 0), (10, 30))]
        #expect(NextMeetingSelector.select(events, now: at(9, 54), calendar: calendar)?.isImminent == false)
        #expect(NextMeetingSelector.select(events, now: at(9, 55), calendar: calendar)?.isImminent == true)
    }

    @Test
    func meetingStartingNowIsInProgress() {
        let events = [event("Standup", (10, 0), (10, 30))]
        #expect(NextMeetingSelector.select(events, now: at(10), calendar: calendar)
            == NextMeeting(event: events[0], phase: .inProgress))
        #expect(NextMeetingSelector.select(events, now: at(10), calendar: calendar)?.isImminent == false)
    }

    @Test
    func backToBackSwitchesToTheNextMeetingInsideTheImminentWindow() {
        let first = event("Standup", (10, 0), (10, 30))
        let second = event("Planning", (10, 30), (11, 0))
        let events = [first, second]
        #expect(NextMeetingSelector.select(events, now: at(10, 20), calendar: calendar)?.event == first)
        let switching = NextMeetingSelector.select(events, now: at(10, 26), calendar: calendar)
        #expect(switching == NextMeeting(event: second, phase: .upcoming(minutesUntil: 4)))
        // At the shared boundary the first has ended and the second is in progress.
        #expect(NextMeetingSelector.select(events, now: at(10, 30), calendar: calendar)
            == NextMeeting(event: second, phase: .inProgress))
    }

    @Test
    func overlappingMeetingsPreferTheMostRecentlyStarted() {
        let long = event("Offsite", (9, 0), (12, 0))
        let inner = event("1:1", (10, 0), (10, 30))
        let sameStartShorter = event("Sync", (10, 0), (10, 15))
        let events = [long, inner, sameStartShorter]
        #expect(NextMeetingSelector.select(events, now: at(9, 30), calendar: calendar)?.event == long)
        // Both inner meetings started at 10:00: the one ending first wins.
        #expect(NextMeetingSelector.select(events, now: at(10, 5), calendar: calendar)?.event == sameStartShorter)
        #expect(NextMeetingSelector.select(events, now: at(10, 20), calendar: calendar)?.event == inner)
        #expect(NextMeetingSelector.select(events, now: at(11), calendar: calendar)?.event == long)
    }

    @Test
    func farUpcomingDoesNotHideAMeetingInProgress() {
        let current = event("Workshop", (9, 0), (11, 0))
        let later = event("Review", (10, 30), (11, 0))
        let events = [current, later]
        #expect(NextMeetingSelector.select(events, now: at(10), calendar: calendar)?.event == current)
        #expect(NextMeetingSelector.select(events, now: at(10, 25), calendar: calendar)?.event == later)
    }

    @Test
    func allDayFreeDeclinedAndDayLongEventsAreIgnored() {
        let dayStart = calendar.startOfDay(for: at(9))
        let events = [
            MeetingFixtures.event("Holiday", dayStart, dayStart.addingTimeInterval(86_400), allDay: true),
            event("Focus", (10, 0), (11, 0), busy: false),
            event("Declined", (10, 0), (11, 0), declined: true),
            MeetingFixtures.event("Conference", at(0), at(0).addingTimeInterval(86_400)),
            event("Zero", (10, 0), (10, 0)),
        ]
        #expect(NextMeetingSelector.select(events, now: at(9), calendar: calendar) == nil)
        let real = event("Standup", (12, 0), (12, 15))
        #expect(NextMeetingSelector.select(events + [real], now: at(9), calendar: calendar)?.event == real)
    }

    @Test
    func tomorrowsMeetingsNeverCountAndOvernightMeetingsDoAfterMidnight() {
        let tomorrow = MeetingFixtures.on(2026, 11, 11, 9, in: calendar)
        let early = MeetingFixtures.event("Tomorrow", tomorrow, tomorrow.addingTimeInterval(1_800))
        #expect(NextMeetingSelector.select([early], now: at(23, 50), calendar: calendar) == nil)

        let overnight = MeetingFixtures.event("Launch", at(23, 30), MeetingFixtures.on(2026, 11, 11, 0, 30, in: calendar))
        #expect(NextMeetingSelector.select([overnight], now: at(23, 40), calendar: calendar)?.phase == .inProgress)
        let afterMidnight = MeetingFixtures.on(2026, 11, 11, 0, 10, in: calendar)
        #expect(NextMeetingSelector.select([overnight], now: afterMidnight, calendar: calendar)?.phase == .inProgress)
    }

    @Test
    func todayFollowsTheCalendarsTimeZone() {
        // 23:30 UTC on Nov 10 is Nov 11 in Tokyo and still Nov 10 in Los Angeles.
        let utc = MeetingFixtures.calendar("UTC")
        let start = MeetingFixtures.on(2026, 11, 10, 23, 30, in: utc)
        let meeting = MeetingFixtures.event("Call", start, start.addingTimeInterval(1_800))
        let now = MeetingFixtures.on(2026, 11, 10, 14, 0, in: utc)
        #expect(NextMeetingSelector.select([meeting], now: now, calendar: MeetingFixtures.calendar("America/Los_Angeles")) != nil)
        #expect(NextMeetingSelector.select([meeting], now: now, calendar: MeetingFixtures.calendar("Asia/Tokyo")) == nil)
        // Countdown is absolute time, so the zone never changes it.
        #expect(NextMeetingSelector.select([meeting], now: now, calendar: utc)?.phase
            == .upcoming(minutesUntil: 570))
    }

    @Test
    func countdownIsCorrectAcrossTheDSTFallBack() {
        // US fall-back: 2026-11-01 01:59 PDT -> 01:00 PST. 01:30 PDT to 01:30 PST is 60 minutes.
        let fallBackStart = calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: -7 * 3_600), year: 2026, month: 11, day: 1, hour: 1, minute: 30
        )) ?? .distantPast
        let meetingStart = calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: -8 * 3_600), year: 2026, month: 11, day: 1, hour: 1, minute: 30
        )) ?? .distantPast
        let meeting = MeetingFixtures.event("Night", meetingStart, meetingStart.addingTimeInterval(1_800))
        #expect(NextMeetingSelector.select([meeting], now: fallBackStart, calendar: calendar)?.phase
            == .upcoming(minutesUntil: 60))
        // The 25-hour day still bounds "today" correctly: 23:30 local is today.
        let late = MeetingFixtures.on(2026, 11, 1, 23, 30, in: calendar)
        let lateMeeting = MeetingFixtures.event("Late", late, late.addingTimeInterval(900))
        #expect(NextMeetingSelector.select([lateMeeting], now: fallBackStart, calendar: calendar) != nil)
    }

    @Test
    func countdownIsCorrectAcrossTheDSTSpringForward() {
        // US spring-forward 2026-03-08: 01:30 PST to 03:30 PDT is one hour.
        let now = MeetingFixtures.on(2026, 3, 8, 1, 30, in: calendar)
        let start = MeetingFixtures.on(2026, 3, 8, 3, 30, in: calendar)
        let meeting = MeetingFixtures.event("Early", start, start.addingTimeInterval(900))
        #expect(NextMeetingSelector.select([meeting], now: now, calendar: calendar)?.phase
            == .upcoming(minutesUntil: 60))
    }

    @Test
    func delayLandsJustAfterTheNextMinuteBoundary() {
        let delay = NextMeetingSelector.delayUntilNextMinute(after: at(9, 41, 20))
        #expect(abs(delay - (40 + NextMeetingSelector.tickLeeway)) < 0.001)
        let onBoundary = NextMeetingSelector.delayUntilNextMinute(after: at(9, 41, 0))
        #expect(abs(onBoundary - (60 + NextMeetingSelector.tickLeeway)) < 0.001)
    }

    @Test
    func nextTransitionIsTheEarliestImminentStartOrEnd() {
        let events = [event("Standup", (10, 0), (10, 30)), event("Review", (13, 0), (14, 0))]
        #expect(NextMeetingSelector.nextTransition(events, now: at(9), calendar: calendar) == at(9, 55))
        #expect(NextMeetingSelector.nextTransition(events, now: at(9, 56), calendar: calendar) == at(10))
        #expect(NextMeetingSelector.nextTransition(events, now: at(10, 5), calendar: calendar) == at(10, 30))
        #expect(NextMeetingSelector.nextTransition(events, now: at(10, 30), calendar: calendar) == at(12, 55))
        #expect(NextMeetingSelector.nextTransition(events, now: at(14), calendar: calendar) == nil)
    }
}

struct NextMeetingTextTests {
    private let calendar = MeetingFixtures.calendar()
    private let locale = Locale(identifier: "en_US")

    @Test(arguments: [(1, "in 1m"), (12, "in 12m"), (59, "in 59m"), (60, "in 1h"),
                      (65, "in 1h 5m"), (125, "in 2h 5m"), (0, "in 1m")])
    func countdownWording(minutes: Int, expected: String) {
        #expect(NextMeetingText.countdown(minutes: minutes) == expected)
    }

    @Test
    func upcomingAndInProgressText() {
        let start = MeetingFixtures.date(10, in: calendar)
        let event = MeetingFixtures.event("Standup", start, start.addingTimeInterval(1_800))
        #expect(NextMeetingText.menuBarText(
            for: NextMeeting(event: event, phase: .upcoming(minutesUntil: 12)), calendar: calendar, locale: locale
        ) == "Standup in 12m")
        let ends = NextMeetingText.menuBarText(
            for: NextMeeting(event: event, phase: .inProgress), calendar: calendar, locale: locale
        )
        // Formatters may use a narrow no-break space before AM/PM.
        #expect(ends.replacingOccurrences(of: "\u{202F}", with: " ") == "Standup ends 10:30 AM")
        let twentyFour = NextMeetingText.menuBarText(
            for: NextMeeting(event: event, phase: .inProgress), calendar: calendar, locale: Locale(identifier: "en_GB")
        )
        #expect(twentyFour == "Standup ends 10:30")
    }

    @Test
    func endTimeUsesTheCalendarsZone() {
        let utc = MeetingFixtures.calendar("UTC")
        let end = MeetingFixtures.on(2026, 11, 10, 18, 30, in: utc)
        let gb = Locale(identifier: "en_GB")
        #expect(NextMeetingText.endTime(end, calendar: utc, locale: gb) == "18:30")
        #expect(NextMeetingText.endTime(end, calendar: MeetingFixtures.calendar("Asia/Tokyo"), locale: gb) == "3:30")
    }

    @Test
    func titlesAreCollapsedAndTruncatedSensibly() {
        #expect(NextMeetingText.truncatedTitle("  Standup \n daily ") == "Standup daily")
        #expect(NextMeetingText.truncatedTitle("") == "Meeting")
        #expect(NextMeetingText.truncatedTitle(" \n ") == "Meeting")
        let exact = String(repeating: "a", count: NextMeetingText.maximumTitleLength)
        #expect(NextMeetingText.truncatedTitle(exact) == exact)
        let long = NextMeetingText.truncatedTitle("Quarterly planning review with leadership")
        #expect(long == "Quarterly planning…")
        #expect(long.count <= NextMeetingText.maximumTitleLength)
        // A cut ending in punctuation or a space drops it before the ellipsis.
        #expect(NextMeetingText.truncatedTitle("Weekly design sync, team and partners") == "Weekly design sync…")
        // Emoji are whole characters, never split.
        let emoji = NextMeetingText.truncatedTitle(String(repeating: "🎉", count: 30))
        #expect(emoji == String(repeating: "🎉", count: 19) + "…")
    }
}
