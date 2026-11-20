import ComposableArchitecture
import EventKit
import Foundation
import Testing

@testable import GlimpseCore

/// The agenda's Join button and ⌘J: only today's next/current meeting with a strict link,
/// re-picked at meeting boundaries, and opened only on an explicit Join action.
@MainActor
struct CalendarFeatureJoinTests {
    // CalendarFeature uses the user's calendar, so fixtures are built in it too.
    private let calendar = Calendar.current
    private nonisolated var day: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)) }
    private nonisolated func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
    private nonisolated var standup: CalendarEvent {
        MeetingFixtures.event("Standup", at(10), at(10, 30), link: "https://zoom.us/j/123")
    }
    private nonisolated var review: CalendarEvent { MeetingFixtures.event("Review", at(11), at(12)) }

    private func loadedState(_ events: [CalendarEvent]) -> CalendarFeature.State {
        var state = CalendarFeature.State(displayedMonth: day)
        state.calendarAuthorizationStatus = .fullAccess
        state.selectedDate = day
        state.eventsDate = day
        state.eventsRequestID = UUID(0)
        state.isLoadingEvents = true
        return state
    }

    private func makeStore(
        _ state: CalendarFeature.State, now: LockIsolated<Date>, clock: TestClock<Duration>,
        opened: LockIsolated<[URL]> = .init([]), failOpen: Bool = false
    ) -> TestStoreOf<CalendarFeature> {
        TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = DateGenerator { now.value }
            $0.continuousClock = clock
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.meetingLinks.open = { link in
                if failOpen { throw MeetingLinkClient.OpenError.launchServices(-10814) }
                opened.withValue { $0.append(link.url) }
            }
        }
    }

    @Test
    func nextMeetingWithALinkIsJoinableAndJoinOpensIt() async {
        let now = LockIsolated(at(9, 56))
        let clock = TestClock()
        let opened = LockIsolated<[URL]>([])
        let events = [standup, review]
        let store = makeStore(loadedState(events), now: now, clock: clock, opened: opened)

        await store.send(.eventsLoaded(date: day, requestID: UUID(0), events: events)) {
            $0.isLoadingEvents = false
            $0.eventsRequestID = nil
            $0.events = events
            $0.joinableEventID = "Standup"
        }
        #expect(store.state.joinableEvent == standup)
        await store.send(.joinMeeting(standup))
        await store.send(.closePanel)
        await store.finish()
        #expect(opened.value.map(\.absoluteString) == ["https://zoom.us/j/123"])
    }

    @Test
    func joinableIsRepickedWhenTheMeetingEnds() async {
        let now = LockIsolated(at(10, 10))
        let clock = TestClock()
        let events = [standup, review]
        let store = makeStore(loadedState(events), now: now, clock: clock)
        await store.send(.eventsLoaded(date: day, requestID: UUID(0), events: events)) {
            $0.isLoadingEvents = false
            $0.eventsRequestID = nil
            $0.events = events
            $0.joinableEventID = "Standup"
        }
        // The next instant anything can change is 10:30 (Standup ends): one wake, no polling.
        now.setValue(at(10, 30))
        await clock.advance(by: .seconds(20 * 60 + 1))
        await store.receive(\.refreshJoinableMeeting) {
            // Review is next now and has no link: no Join.
            $0.joinableEventID = nil
        }
        await store.send(.closePanel)
    }

    @Test
    func joinIgnoresAnythingButTheCurrentJoinableEvent() async {
        let now = LockIsolated(at(9))
        let opened = LockIsolated<[URL]>([])
        let other = MeetingFixtures.event("Other", at(15), at(16), link: "https://meet.google.com/abc-defg-hij")
        var state = loadedState([standup, other])
        state.isLoadingEvents = false
        state.eventsRequestID = nil
        state.events = [standup, other]
        state.joinableEventID = "Standup"
        let store = makeStore(state, now: now, clock: TestClock(), opened: opened)
        await store.send(.joinMeeting(other))
        await store.send(.joinMeeting(review))
        #expect(opened.value.isEmpty)
    }

    @Test
    func joinFailureShowsAMessage() async {
        var state = loadedState([standup])
        state.isLoadingEvents = false
        state.eventsRequestID = nil
        state.events = [standup]
        state.joinableEventID = "Standup"
        let store = makeStore(state, now: .init(at(9, 58)), clock: TestClock(), failOpen: true)
        await store.send(.joinMeeting(standup))
        await store.receive(\.joinMeetingFailed) {
            $0.eventOpenError = "Couldn’t open the meeting link."
        }
    }

    @Test
    func otherDaysAndLinklessMeetingsAreNeverJoinable() async {
        let now = LockIsolated(at(9))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        var state = loadedState([])
        state.selectedDate = tomorrow
        state.eventsDate = tomorrow
        let store = makeStore(state, now: now, clock: TestClock())
        let future = MeetingFixtures.event("Tomorrow", tomorrow.addingTimeInterval(36_000),
                                           tomorrow.addingTimeInterval(37_800), link: "https://zoom.us/j/1")
        await store.send(.eventsLoaded(date: tomorrow, requestID: UUID(0), events: [future])) {
            $0.isLoadingEvents = false
            $0.eventsRequestID = nil
            $0.events = [future]
        }

        let plain = makeStore(loadedState([review]), now: now, clock: TestClock())
        await plain.send(.eventsLoaded(date: day, requestID: UUID(0), events: [review])) {
            $0.isLoadingEvents = false
            $0.eventsRequestID = nil
            $0.events = [review]
        }
    }

    @Test
    func declinedMeetingWithALinkIsNotJoinable() async {
        let declined = MeetingFixtures.event("Skip", at(10), at(11), declined: true, link: "https://zoom.us/j/9")
        let store = makeStore(loadedState([declined]), now: .init(at(9, 58)), clock: TestClock())
        await store.send(.eventsLoaded(date: day, requestID: UUID(0), events: [declined])) {
            $0.isLoadingEvents = false
            $0.eventsRequestID = nil
            $0.events = [declined]
        }
    }

    @Test
    func hidingThePanelStopsTheJoinRefresh() async {
        let now = LockIsolated(at(9))
        let clock = TestClock()
        let store = makeStore(loadedState([standup]), now: now, clock: clock)
        await store.send(.eventsLoaded(date: day, requestID: UUID(0), events: [standup])) {
            $0.isLoadingEvents = false
            $0.eventsRequestID = nil
            $0.events = [standup]
            $0.joinableEventID = "Standup"
        }
        await store.send(.hiddenPreservingContext)
        await clock.advance(by: .seconds(7_200))
        // No refreshJoinableMeeting arrives once hidden.
    }
}
