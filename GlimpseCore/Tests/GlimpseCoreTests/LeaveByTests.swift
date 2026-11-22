import ComposableArchitecture
import EventKit
import Foundation
import Testing

@testable import GlimpseCore

/// Leave-by (start − buffer) for located events, trips, and their menu bar / agenda wording.
struct LeaveByTests {
    private let calendar = MeetingFixtures.calendar()
    private let locale = Locale(identifier: "en_US")
    private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        MeetingFixtures.date(hour, minute, second, in: calendar)
    }
    private var dentist: CalendarEvent {
        CalendarEvent(id: "dentist", title: "Dentist", startDate: at(9), endDate: at(10),
                      isAllDay: false, location: "412 Oak St")
    }

    // MARK: - Location

    @Test
    func locationIsTrimmedAndVirtualPlacesAreNotPlaces() {
        #expect(CalendarEvent.physicalLocation("  412 Oak   St \n") == "412 Oak St")
        #expect(CalendarEvent.physicalLocation(nil) == nil)
        #expect(CalendarEvent.physicalLocation("   ") == nil)
        #expect(CalendarEvent.physicalLocation("https://zoom.us/j/123") == nil)
        #expect(CalendarEvent.physicalLocation("Room 4 / www.example.com/call") == nil)
        #expect(CalendarEvent.physicalLocation("Microsoft Teams Meeting") == nil)
        #expect(CalendarEvent.physicalLocation("zoom") == nil)
        #expect(CalendarEvent.physicalLocation("Zoom Cafe, 5th Ave") == "Zoom Cafe, 5th Ave")
        #expect(CalendarEvent.physicalLocation("Join Zoom Meeting") == nil)
        #expect(CalendarEvent.physicalLocation("Join Microsoft Teams Meeting") == nil)
        #expect(CalendarEvent.physicalLocation("join the  Google Meet") == nil)
        #expect(CalendarEvent.physicalLocation("Join Us Cafe") == "Join Us Cafe")
        let event = CalendarEvent(id: "a", title: "A", startDate: at(9), endDate: at(10),
                                  isAllDay: false, location: "Google Meet")
        #expect(event.location == nil)
    }

    // MARK: - Buffer and leave time

    @Test
    func bufferChoicesDefaultToTwentyAndRejectOthers() {
        #expect(LeaveBy.bufferChoices == [10, 15, 20, 30, 45, 60])
        #expect(LeaveBy.defaultBufferMinutes == 20)
        #expect(LeaveBy.validatedBuffer(45) == 45)
        #expect(LeaveBy.validatedBuffer(0) == 20)
        #expect(LeaveBy.validatedBuffer(-5) == 20)
        #expect(LeaveBy.validatedBuffer(25) == 20)
    }

    @Test
    func leaveTimeIsStartMinusBufferOnlyForLocatedTimedEvents() {
        #expect(LeaveBy.leaveTime(for: dentist, bufferMinutes: 20) == at(8, 40))
        #expect(LeaveBy.leaveTime(for: dentist, bufferMinutes: 60) == at(8))
        #expect(LeaveBy.leaveTime(for: dentist, bufferMinutes: nil) == nil)
        let noPlace = MeetingFixtures.event("Standup", at(9), at(9, 30))
        #expect(LeaveBy.leaveTime(for: noPlace, bufferMinutes: 20) == nil)
        let allDay = CalendarEvent(id: "b", title: "Fair", startDate: calendar.startOfDay(for: at(9)),
                                   endDate: calendar.startOfDay(for: at(9)).addingTimeInterval(86_400),
                                   isAllDay: true, location: "Fairgrounds")
        #expect(LeaveBy.leaveTime(for: allDay, bufferMinutes: 20) == nil)
        let declined = CalendarEvent(id: "c", title: "Party", startDate: at(9), endDate: at(10),
                                     isAllDay: false, isDeclined: true, location: "Home")
        #expect(LeaveBy.leaveTime(for: declined, bufferMinutes: 20) == nil)
    }

    @Test
    func clockTextOmitsTheDayPeriod() {
        #expect(LeaveBy.clockText(at(8, 40), calendar: calendar, locale: locale) == "8:40")
        #expect(LeaveBy.clockText(at(20, 5), calendar: calendar, locale: Locale(identifier: "en_GB")) == "20:05")
    }

    // MARK: - Trips

    @Test
    func tripsSpanTwoOrMoreCalendarDaysAndNeedAPlace() {
        let wed = MeetingFixtures.on(2026, 11, 25, 7, in: calendar)
        let sun = MeetingFixtures.on(2026, 11, 29, 14, in: calendar)
        let tahoe = CalendarEvent(id: "t", title: "Tahoe trip", startDate: wed, endDate: sun,
                                  isAllDay: false, location: "South Lake Tahoe")
        #expect(LeaveBy.tripDays(for: tahoe, calendar: calendar) == 5)
        // All-day events end at the next midnight (exclusive): Wed..Sun is still 5 days.
        let allDay = CalendarEvent(
            id: "a", title: "Tahoe", startDate: calendar.startOfDay(for: wed),
            endDate: MeetingFixtures.on(2026, 11, 30, 0, in: calendar), isAllDay: true, location: "Tahoe"
        )
        #expect(LeaveBy.tripDays(for: allDay, calendar: calendar) == 5)
        let oneDay = CalendarEvent(
            id: "o", title: "Fair", startDate: calendar.startOfDay(for: wed),
            endDate: MeetingFixtures.on(2026, 11, 26, 0, in: calendar), isAllDay: true, location: "Fair"
        )
        #expect(LeaveBy.tripDays(for: oneDay, calendar: calendar) == nil)
        let overnight = CalendarEvent(
            id: "n", title: "Red-eye", startDate: MeetingFixtures.on(2026, 11, 25, 22, in: calendar),
            endDate: MeetingFixtures.on(2026, 11, 26, 6, in: calendar), isAllDay: false, location: "SFO"
        )
        #expect(LeaveBy.tripDays(for: overnight, calendar: calendar) == 2)
        let noPlace = CalendarEvent(id: "p", title: "Off", startDate: wed, endDate: sun, isAllDay: false)
        #expect(LeaveBy.tripDays(for: noPlace, calendar: calendar) == nil)
    }

    // MARK: - Agenda badges

    @Test
    func agendaBadgeShowsLeaveByUntilTheEventStarts() {
        #expect(AgendaBadge.badge(for: dentist, leaveByMinutes: 20, now: at(8, 25), calendar: calendar)
            == .leaveBy(at(8, 40)))
        #expect(AgendaBadge.badge(for: dentist, leaveByMinutes: 20, now: at(8, 50), calendar: calendar)
            == .leaveBy(at(8, 40)))
        #expect(AgendaBadge.badge(for: dentist, leaveByMinutes: 20, now: at(9), calendar: calendar) == nil)
        // Leave-by is opt-in.
        #expect(AgendaBadge.badge(for: dentist, leaveByMinutes: nil, now: at(8), calendar: calendar) == nil)
    }

    @Test
    func agendaBadgeShowsAwayForTripsWhateverTheSetting() {
        let tahoe = CalendarEvent(
            id: "t", title: "Tahoe trip", startDate: MeetingFixtures.on(2026, 11, 25, 7, in: calendar),
            endDate: MeetingFixtures.on(2026, 11, 29, 14, in: calendar), isAllDay: false, location: "Tahoe"
        )
        let monday = MeetingFixtures.on(2026, 11, 23, 18, 10, in: calendar)
        #expect(AgendaBadge.badge(for: tahoe, leaveByMinutes: nil, now: monday, calendar: calendar) == .away(days: 5))
        #expect(AgendaBadge.badge(for: tahoe, leaveByMinutes: 20, now: monday, calendar: calendar) == .away(days: 5))
        #expect(AgendaBadge.away(days: 5).text(calendar: calendar, locale: locale) == "Away 5 days")
        #expect(AgendaBadge.leaveBy(at(8, 40)).text(calendar: calendar, locale: locale) == "Leave by 8:40")
        // Foundation separates the day period with a narrow no-break space.
        #expect(AgendaBadge.leaveBy(at(8, 40)).accessibilityText(calendar: calendar, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " ") == "Leave by 8:40 AM")
    }

    // MARK: - Selector

    @Test
    func locatedNextMeetingReadsLeaveByUntilItPasses() throws {
        let events = [dentist]
        let early = try #require(NextMeetingSelector.select(events, now: at(8, 25), calendar: calendar, leaveByMinutes: 20))
        #expect(early.phase == .leaveBy(at: at(8, 40), minutesUntil: 15))
        #expect(!early.isImminent)
        #expect(NextMeetingText.menuBarText(for: early, calendar: calendar, locale: locale)
            == "Dentist · leave by 8:40")

        // Amber 5 minutes before leave-by.
        let amber = try #require(NextMeetingSelector.select(events, now: at(8, 35), calendar: calendar, leaveByMinutes: 20))
        #expect(amber.phase == .leaveBy(at: at(8, 40), minutesUntil: 5))
        #expect(amber.isImminent)
        let notYet = try #require(NextMeetingSelector.select(events, now: at(8, 34, 59), calendar: calendar, leaveByMinutes: 20))
        #expect(!notYet.isImminent)

        // Leave-by passed: the normal countdown, amber again only in its last 5 minutes.
        let after = try #require(NextMeetingSelector.select(events, now: at(8, 48), calendar: calendar, leaveByMinutes: 20))
        #expect(after.phase == .upcoming(minutesUntil: 12))
        #expect(!after.isImminent)
        #expect(NextMeetingText.menuBarText(for: after, calendar: calendar, locale: locale) == "Dentist in 12m")
        let atLeave = try #require(NextMeetingSelector.select(events, now: at(8, 40), calendar: calendar, leaveByMinutes: 20))
        #expect(atLeave.phase == .upcoming(minutesUntil: 20))
    }

    @Test
    func withoutLocationOrSettingTheCountdownIsUnchanged() throws {
        let standup = MeetingFixtures.event("Standup", at(9), at(9, 30))
        let plain = try #require(NextMeetingSelector.select([standup], now: at(8, 25), calendar: calendar, leaveByMinutes: 20))
        #expect(plain.phase == .upcoming(minutesUntil: 35))
        let off = try #require(NextMeetingSelector.select([dentist], now: at(8, 25), calendar: calendar))
        #expect(off.phase == .upcoming(minutesUntil: 35))
    }

    @Test
    func amberLeaveByWinsOverAMeetingInProgress() throws {
        let call = MeetingFixtures.event("Call", at(8), at(8, 45))
        let calm = try #require(NextMeetingSelector.select([call, dentist], now: at(8, 20), calendar: calendar, leaveByMinutes: 20))
        #expect(calm.phase == .inProgress)
        let amber = try #require(NextMeetingSelector.select([call, dentist], now: at(8, 36), calendar: calendar, leaveByMinutes: 20))
        #expect(amber.event == dentist)
        #expect(amber.isImminent)
    }

    @Test
    func transitionsIncludeTheLeaveByWindowAndInstant() {
        let next = NextMeetingSelector.nextTransition([dentist], now: at(8), calendar: calendar, leaveByMinutes: 20)
        #expect(next == at(8, 35))
        let then = NextMeetingSelector.nextTransition([dentist], now: at(8, 35), calendar: calendar, leaveByMinutes: 20)
        #expect(then == at(8, 40))
        #expect(NextMeetingSelector.nextTransition([dentist], now: at(8), calendar: calendar) == at(8, 55))
    }
}

/// The leave-by buffer reaches the next-meeting store, the agenda and preferences.
@MainActor
struct LeaveByFeatureTests {
    private let calendar = MeetingFixtures.calendar()
    private nonisolated func at(_ hour: Int, _ minute: Int = 0) -> Date {
        MeetingFixtures.date(hour, minute, in: MeetingFixtures.calendar())
    }
    private nonisolated var dentist: CalendarEvent {
        CalendarEvent(id: "dentist", title: "Dentist", startDate: at(9), endDate: at(10),
                      isAllDay: false, location: "412 Oak St")
    }

    @Test
    func settingTheBufferRecomputesTheCachedMeeting() async {
        let now = LockIsolated(at(8, 25))
        let clock = TestClock()
        let dentist = dentist
        let calendar = calendar
        let store = TestStore(initialState: NextMeetingFeature.State()) {
            NextMeetingFeature()
        } withDependencies: {
            $0.date = DateGenerator { now.value }
            $0.calendar = calendar
            $0.continuousClock = clock
            $0.uuid = .incrementing
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { _ in [dentist] }
        }
        // Off while disabled: stored, nothing fetched.
        await store.send(.setLeaveBy(minutes: 20)) { $0.leaveByMinutes = 20 }
        await store.send(.setEnabled(true)) {
            $0.isEnabled = true
            $0.requestID = UUID(0)
        }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = calendar.startOfDay(for: now.value)
            $0.events = [dentist]
            $0.meeting = NextMeeting(event: dentist, phase: .leaveBy(at: at(8, 40), minutesUntil: 15))
        }
        await store.send(.setLeaveBy(minutes: 20))
        await store.send(.setLeaveBy(minutes: 30)) {
            $0.leaveByMinutes = 30
            $0.meeting = NextMeeting(event: dentist, phase: .leaveBy(at: at(8, 30), minutesUntil: 5))
        }
        await store.send(.setLeaveBy(minutes: nil)) {
            $0.leaveByMinutes = nil
            $0.meeting = NextMeeting(event: dentist, phase: .upcoming(minutesUntil: 35))
        }
        await store.send(.setEnabled(false)) {
            $0.isEnabled = false
            $0.events = []
            $0.eventsDay = nil
            $0.meeting = nil
        }
    }

    @Test
    func agendaBadgesFollowTheLeaveBySetting() async {
        let dentist = dentist
        let options = LockIsolated(MenuBarDisplayOptions(showLeaveBy: true, leaveByMinutes: 15))
        var initial = CalendarFeature.State(displayedMonth: at(8))
        initial.calendarAuthorizationStatus = .fullAccess
        initial.eventsDate = initial.calendar.startOfDay(for: at(8))
        initial.eventsRequestID = UUID(0)
        let day = initial.eventsDate!
        let store = TestStore(initialState: initial) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(at(8, 25))
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { true }
            $0.preferencesClient.loadDisplayOptions = { options.value }
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
        }
        store.exhaustivity = .off
        await store.send(.reloadPreferences) {
            $0.leaveByMinutes = 15
            $0.agendaNow = at(8, 25)
        }
        await store.send(.eventsLoaded(date: day, requestID: UUID(0), events: [dentist])) {
            $0.events = [dentist]
        }
        #expect(store.state.agendaBadge(for: dentist) == .leaveBy(at(8, 45)))
        options.setValue(MenuBarDisplayOptions(showLeaveBy: false, leaveByMinutes: 15))
        await store.send(.reloadPreferences) { $0.leaveByMinutes = nil }
        #expect(store.state.agendaBadge(for: dentist) == nil)
        // Leave-by on but no load time yet: no leave-by chip.
        var unloaded = CalendarFeature.State(displayedMonth: at(8))
        unloaded.leaveByMinutes = 20
        #expect(unloaded.agendaBadge(for: dentist) == nil)
    }

    @Test
    func preferencesSaveTheToggleAndAValidatedBuffer() async {
        let saved = LockIsolated<[MenuBarDisplayOptions]>([])
        let store = TestStore(initialState: PreferencesFeature.State()) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveDisplayOptions = { value in saved.withValue { $0.append(value) } }
        }
        await store.send(.setShowLeaveBy(true)) { $0.displayOptions.showLeaveBy = true }
        await store.receive(\.delegate.displayOptionsChanged)
        await store.send(.setLeaveByMinutes(45)) { $0.displayOptions.leaveByMinutes = 45 }
        await store.receive(\.delegate.displayOptionsChanged)
        await store.send(.setLeaveByMinutes(7)) { $0.displayOptions.leaveByMinutes = 20 }
        await store.receive(\.delegate.displayOptionsChanged)
        #expect(saved.value.map(\.leaveByMinutes) == [20, 45, 20])
        #expect(saved.value.allSatisfy { $0.showLeaveBy })
    }

    @Test
    func displayOptionsPersistLeaveByWithDefaults() throws {
        #expect(MenuBarDisplayOptions.default.showLeaveBy == false)
        #expect(MenuBarDisplayOptions.default.leaveByMinutes == 20)
        #expect(MenuBarDisplayOptions.default.activeLeaveByMinutes == nil)
        #expect(MenuBarDisplayOptions(showLeaveBy: true, leaveByMinutes: 30).activeLeaveByMinutes == 30)
        let old = try JSONDecoder().decode(MenuBarDisplayOptions.self, from: Data(#"{"showIcon":false}"#.utf8))
        #expect(old.showLeaveBy == false && old.leaveByMinutes == 20 && old.showIcon == false)
        let bad = try JSONDecoder().decode(MenuBarDisplayOptions.self, from: Data(#"{"leaveByMinutes":7}"#.utf8))
        #expect(bad.leaveByMinutes == 20)

        let suite = "LeaveByTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = PreferencesClient.live(defaults: defaults)
        #expect(client.loadDisplayOptions().leaveByMinutes == 20)
        client.saveDisplayOptions(MenuBarDisplayOptions(showLeaveBy: true, leaveByMinutes: 45))
        #expect(client.loadDisplayOptions().showLeaveBy && client.loadDisplayOptions().leaveByMinutes == 45)
        defaults.set(99, forKey: "leaveByMinutes")
        #expect(client.loadDisplayOptions().leaveByMinutes == 20)
    }
}
