import ComposableArchitecture
import EventKit
import Foundation
import Testing

@testable import GlimpseCore

@MainActor
struct NextMeetingFeatureTests {
    private let calendar = MeetingFixtures.calendar()
    private nonisolated var day: Date { calendar.startOfDay(for: MeetingFixtures.date(9, in: calendar)) }
    private nonisolated func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        MeetingFixtures.date(hour, minute, second, in: calendar)
    }
    private nonisolated var standup: CalendarEvent { MeetingFixtures.event("Standup", at(10), at(10, 30)) }

    private func makeStore(
        now: LockIsolated<Date>, clock: TestClock<Duration>,
        status: LockIsolated<EKAuthorizationStatus> = .init(.fullAccess),
        fetches: LockIsolated<[Date]> = .init([]),
        events: @escaping @Sendable () -> [CalendarEvent]
    ) -> TestStoreOf<NextMeetingFeature> {
        let calendar = calendar
        return TestStore(initialState: NextMeetingFeature.State()) {
            NextMeetingFeature()
        } withDependencies: {
            $0.date = DateGenerator { now.value }
            $0.calendar = calendar
            $0.continuousClock = clock
            $0.uuid = .incrementing
            $0.eventKitClient.authorizationStatus = { status.value }
            $0.eventKitClient.fetchEvents = { date in
                fetches.withValue { $0.append(date) }
                return events()
            }
        }
    }

    @Test
    func enablingFetchesTodayOnceAndTicksEachMinuteFromTheCache() async {
        let now = LockIsolated(at(9, 47, 30))
        let clock = TestClock()
        let fetches = LockIsolated<[Date]>([])
        let standup = standup
        let store = makeStore(now: now, clock: clock, fetches: fetches) { [standup] }

        await store.send(.setEnabled(true)) {
            $0.isEnabled = true
            $0.requestID = UUID(0)
        }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = day
            $0.events = [standup]
            $0.meeting = NextMeeting(event: standup, phase: .upcoming(minutesUntil: 13))
        }
        // The first tick waits for the minute boundary (30 s + leeway), not a full minute.
        now.setValue(at(9, 48, 0))
        await clock.advance(by: .milliseconds(30_250))
        await store.receive(\.tick) {
            $0.meeting = NextMeeting(event: standup, phase: .upcoming(minutesUntil: 12))
        }
        now.setValue(at(9, 55, 0))
        await clock.advance(by: .milliseconds(60_250))
        await store.receive(\.tick) {
            $0.meeting = NextMeeting(event: standup, phase: .upcoming(minutesUntil: 5))
        }
        #expect(store.state.meeting?.isImminent == true)
        now.setValue(at(10, 0, 0))
        await clock.advance(by: .milliseconds(60_250))
        await store.receive(\.tick) {
            $0.meeting = NextMeeting(event: standup, phase: .inProgress)
        }
        // After the last meeting the segment clears and ticking stops.
        now.setValue(at(10, 30, 0))
        await clock.advance(by: .milliseconds(60_250))
        await store.receive(\.tick) { $0.meeting = nil }
        await clock.advance(by: .seconds(600))
        // Ticks never query EventKit: one fetch for the whole day.
        #expect(fetches.value == [day])
        await store.send(.setEnabled(false)) {
            $0.isEnabled = false
            $0.events = []
            $0.eventsDay = nil
        }
    }

    @Test
    func noAccessNeverPromptsOrFetches() async {
        let now = LockIsolated(at(9))
        let fetches = LockIsolated<[Date]>([])
        let store = makeStore(now: now, clock: TestClock(), status: .init(.notDetermined), fetches: fetches) { [] }
        await store.send(.setEnabled(true)) { $0.isEnabled = true }
        await store.send(.refresh)
        #expect(fetches.value.isEmpty)
    }

    @Test
    func accessRevokedClearsTheSegmentOnRefresh() async {
        let now = LockIsolated(at(9, 50))
        let clock = TestClock()
        let status = LockIsolated(EKAuthorizationStatus.fullAccess)
        let standup = standup
        let store = makeStore(now: now, clock: clock, status: status) { [standup] }
        await store.send(.setEnabled(true)) { $0.isEnabled = true; $0.requestID = UUID(0) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = day
            $0.events = [standup]
            $0.meeting = NextMeeting(event: standup, phase: .upcoming(minutesUntil: 10))
        }
        status.setValue(.denied)
        await store.send(.refresh) {
            $0.events = []
            $0.eventsDay = nil
            $0.meeting = nil
        }
    }

    @Test
    func noMeetingsLeftMeansNoTicker() async {
        let now = LockIsolated(at(18))
        let standup = standup
        let store = makeStore(now: now, clock: TestClock()) { [standup] }
        await store.send(.setEnabled(true)) { $0.isEnabled = true; $0.requestID = UUID(0) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = day
            $0.events = [standup]
        }
        // TestStore would fail on a still-running tick effect at the end of the test.
    }

    @Test
    func tickAfterMidnightRereadsTheNewDay() async {
        let now = LockIsolated(at(23, 58, 0))
        let clock = TestClock()
        let fetches = LockIsolated<[Date]>([])
        let late = MeetingFixtures.event("Late", at(23, 0), at(23, 59, 30))
        let store = makeStore(now: now, clock: clock, fetches: fetches) { [late] }
        await store.send(.setEnabled(true)) { $0.isEnabled = true; $0.requestID = UUID(0) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = day
            $0.events = [late]
            $0.meeting = NextMeeting(event: late, phase: .inProgress)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        now.setValue(tomorrow.addingTimeInterval(1))
        await clock.advance(by: .seconds(61))
        await store.receive(\.tick) { $0.requestID = UUID(1) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = tomorrow
            $0.meeting = nil
        }
        #expect(fetches.value == [day, tomorrow])
    }

    @Test
    func failedQueryClearsAndStaleResultsAreIgnored() async {
        let now = LockIsolated(at(9))
        let store = TestStore(initialState: NextMeetingFeature.State()) {
            NextMeetingFeature()
        } withDependencies: {
            $0.date = DateGenerator { now.value }
            $0.calendar = calendar
            $0.continuousClock = TestClock()
            $0.uuid = .incrementing
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { _ in throw EventKitClient.QueryError.accessUnavailable }
        }
        await store.send(.setEnabled(true)) { $0.isEnabled = true; $0.requestID = UUID(0) }
        await store.receive(\.eventsFailed) {
            $0.requestID = nil
            $0.eventsDay = day
        }
        // A result for a superseded request changes nothing.
        await store.send(.eventsLoaded(day: day, requestID: UUID(9), events: [standup]))
    }

    @Test
    func repeatedEnableIsIdempotentAndRefreshWhileDisabledIsIgnored() async {
        let fetches = LockIsolated<[Date]>([])
        let store = makeStore(now: .init(at(18)), clock: TestClock(), fetches: fetches) { [] }
        await store.send(.refresh)
        await store.send(.tick)
        await store.send(.setEnabled(false))
        #expect(fetches.value.isEmpty)
    }

    @Test
    func refreshSameDayWithCachedEventsRecomputesWithoutFetch() async {
        let now = LockIsolated(at(9, 50))
        let clock = TestClock()
        let fetches = LockIsolated<[Date]>([])
        let standup = standup
        let store = makeStore(now: now, clock: clock, fetches: fetches) { [standup] }
        await store.send(.setEnabled(true)) { $0.isEnabled = true; $0.requestID = UUID(0) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = day
            $0.events = [standup]
            $0.meeting = NextMeeting(event: standup, phase: .upcoming(minutesUntil: 10))
        }
        // Time advances: meeting is now imminent.
        now.setValue(at(9, 57))
        await store.send(.refresh) {
            // Meeting recomputed from cache (10 min → 3 min), but no new fetch.
            $0.meeting = NextMeeting(event: standup, phase: .upcoming(minutesUntil: 3))
        }
        // Only the initial enable fetch, no second fetch on .refresh.
        #expect(fetches.value == [day])
        // Disable to cancel the pending tick effect started by refresh.
        await store.send(.setEnabled(false)) {
            $0.isEnabled = false
            $0.events = []
            $0.eventsDay = nil
            $0.meeting = nil
        }
    }

    @Test
    func refreshAfterMidnightCrossingFetchesNewDay() async {
        let now = LockIsolated(at(23, 58))
        let fetches = LockIsolated<[Date]>([])
        let late = MeetingFixtures.event("Late", at(23, 0), at(23, 59, 30))
        let store = makeStore(now: now, clock: TestClock(), fetches: fetches) { [late] }
        await store.send(.setEnabled(true)) { $0.isEnabled = true; $0.requestID = UUID(0) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = day
            $0.events = [late]
            $0.meeting = NextMeeting(event: late, phase: .inProgress)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        now.setValue(tomorrow.addingTimeInterval(60))
        // Crossing midnight: must fetch the new day.
        await store.send(.refresh) { $0.requestID = UUID(1) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = tomorrow
            $0.meeting = nil
        }
        #expect(fetches.value == [day, tomorrow])
    }

    @Test
    func refreshWithEmptyEventsFetches() async {
        let now = LockIsolated(at(9))
        let fetches = LockIsolated<[Date]>([])
        let store = makeStore(now: now, clock: TestClock(), fetches: fetches) { [] }
        await store.send(.setEnabled(true)) { $0.isEnabled = true; $0.requestID = UUID(0) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = day
            $0.events = []
        }
        // Even on the same day, empty events trigger a fresh fetch (might have changed).
        await store.send(.refresh) { $0.requestID = UUID(1) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = day
            $0.events = []
        }
        #expect(fetches.value == [day, day])
    }

    @Test
    func refreshWithoutAccessFetchesInsteadOfReusing() async {
        let now = LockIsolated(at(9, 50))
        let status = LockIsolated(EKAuthorizationStatus.fullAccess)
        let fetches = LockIsolated<[Date]>([])
        let standup = standup
        let store = makeStore(now: now, clock: TestClock(), status: status, fetches: fetches) { [standup] }
        await store.send(.setEnabled(true)) { $0.isEnabled = true; $0.requestID = UUID(0) }
        await store.receive(\.eventsLoaded) {
            $0.requestID = nil
            $0.eventsDay = day
            $0.events = [standup]
            $0.meeting = NextMeeting(event: standup, phase: .upcoming(minutesUntil: 10))
        }
        status.setValue(.notDetermined)
        // Auth changed: must call fetch to discover the status change and clear.
        await store.send(.refresh) {
            $0.events = []
            $0.eventsDay = nil
            $0.meeting = nil
        }
        // The initial fetch, then the refresh attempt (which immediately clears).
        #expect(fetches.value == [day])
    }
}
