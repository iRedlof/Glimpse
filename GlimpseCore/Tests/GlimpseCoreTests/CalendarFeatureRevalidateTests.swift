import ComposableArchitecture
import EventKit
import Foundation
import Testing

@testable import GlimpseCore

/// Stale-while-revalidate: re-fetching the agenda's own day keeps the shown events
/// (no "Loading events…" flash, no extra body pass); a different day or lost access
/// still clears them, and the requestID guard still drops stale responses.
@MainActor
struct CalendarFeatureRevalidateTests {
    private nonisolated static let firstRequest = UUID(1)
    private nonisolated static let secondRequest = UUID(2)
    private let calendar = Calendar.current
    private nonisolated var day: Date { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)) }
    private nonisolated var nextDay: Date { day.addingTimeInterval(86_400 + 3_600) }
    private nonisolated func event(_ id: String) -> CalendarEvent {
        CalendarEvent(id: id, title: id, startDate: day, endDate: day.addingTimeInterval(1_800), isAllDay: false)
    }

    private func shownState() -> CalendarFeature.State {
        var state = CalendarFeature.State(displayedMonth: day)
        state.calendarAuthorizationStatus = .fullAccess
        state.selectedDate = day
        state.eventsDate = day
        state.events = [event("old")]
        return state
    }

    private func makeStore(
        _ state: CalendarFeature.State, now: Date,
        requestIDs: [UUID] = [firstRequest],
        fetch: @escaping @Sendable (Date) async throws -> [CalendarEvent]
    ) -> TestStoreOf<CalendarFeature> {
        let ids = LockIsolated(requestIDs)
        return TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.uuid = .init { ids.withValue { $0.removeFirst() } }
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = fetch
        }
    }

    @Test
    func sameDayRefetch_keepsEventsAndDoesNotShowLoading() async {
        let fresh = [event("fresh")]
        let store = makeStore(shownState(), now: day) { _ in fresh }

        await store.send(.refreshCalendarAuthorization) {
            $0.eventsRequestID = Self.firstRequest
        }
        await store.receive(\.eventsLoaded) {
            $0.events = fresh
            $0.eventsRequestID = nil
        }
    }

    @Test
    func sameDayRefetch_withUnchangedEventsMutatesNothingVisible() async {
        let store = makeStore(shownState(), now: day) { [event] _ in [event("old")] }

        await store.send(.retryEvents) {
            $0.eventsRequestID = Self.firstRequest
        }
        await store.receive(\.eventsLoaded) {
            $0.eventsRequestID = nil
        }
        #expect(store.state.events == [event("old")])
        #expect(store.state.isLoadingEvents == false)
    }

    @Test
    func dayChange_clearsEventsAndShowsLoading() async {
        var state = shownState()
        state.selectedDate = nil
        let newDay = calendar.startOfDay(for: nextDay)
        let fresh = [event("tomorrow")]
        let store = makeStore(state, now: nextDay) { requested in
            #expect(requested == newDay)
            return fresh
        }

        await store.send(.refreshCalendarAuthorization) {
            $0.events = []
            $0.eventsDate = newDay
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.events = fresh
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test
    func retryAfterFailure_showsLoadingAgain() async {
        var state = shownState()
        state.events = []
        state.eventsError = "Query failed"
        let store = makeStore(state, now: day) { _ in [] }

        await store.send(.retryEvents) {
            $0.eventsError = nil
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test
    func sameDayRevalidation_dropsStaleResponseAndKeepsShownEvents() async {
        var state = shownState()
        state.eventsRequestID = Self.secondRequest
        let store = makeStore(state, now: day) { _ in [] }

        await store.send(.eventsLoaded(date: day, requestID: Self.firstRequest, events: [event("stale")]))
        await store.send(.eventsFailed(date: day, requestID: Self.firstRequest, message: "Old failure"))
        #expect(store.state.events == [event("old")])
        #expect(store.state.eventsError == nil)
    }

    @Test
    func sameDayRevalidation_afterRevocationClearsEvents() async {
        let store = TestStore(initialState: shownState()) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(day)
            $0.eventKitClient.authorizationStatus = { .denied }
        }

        await store.send(.refreshCalendarAuthorization) {
            $0.calendarAuthorizationStatus = .denied
            $0.events = []
            $0.eventsDate = nil
        }
    }
}

/// App activation (⌘G, the AI editor, returning from System Settings) only re-reads
/// the agenda when calendar authorization actually changed; EKEventStoreChanged
/// already covers data changes.
@MainActor
struct CalendarFeatureActivationTests {
    private nonisolated var day: Date { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)) }

    private func store(
        was previous: EKAuthorizationStatus, now current: EKAuthorizationStatus,
        fetches: LockIsolated<Int>
    ) -> TestStoreOf<CalendarFeature> {
        var state = CalendarFeature.State(displayedMonth: day)
        state.calendarAuthorizationStatus = previous
        state.selectedDate = day
        if previous == .fullAccess {
            state.eventsDate = day
            state.events = [CalendarEvent(id: "a", title: "A", startDate: day, endDate: day, isAllDay: false)]
        }
        return TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(day)
            $0.uuid = .constant(UUID(1))
            $0.eventKitClient.authorizationStatus = { current }
            $0.eventKitClient.fetchEvents = { _ in
                fetches.withValue { $0 += 1 }
                return []
            }
            $0.eventKitClient.requestAccess = {
                Issue.record("Activation must never request permission")
                return false
            }
        }
    }

    @Test(arguments: [EKAuthorizationStatus.fullAccess, .denied, .notDetermined])
    func activationWithUnchangedAuthorization_doesNothing(status: EKAuthorizationStatus) async {
        let fetches = LockIsolated(0)
        let store = store(was: status, now: status, fetches: fetches)

        await store.send(.applicationDidBecomeActive)
        #expect(fetches.value == 0)
    }

    @Test
    func activationAfterGrantingAccess_loadsEvents() async {
        let fetches = LockIsolated(0)
        let store = store(was: .denied, now: .fullAccess, fetches: fetches)

        await store.send(.applicationDidBecomeActive) {
            $0.calendarAuthorizationStatus = .fullAccess
            $0.eventsDate = self.day
            $0.eventsRequestID = UUID(1)
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
        #expect(fetches.value == 1)
    }

    @Test
    func activationAfterRevokingAccess_clearsEvents() async {
        let fetches = LockIsolated(0)
        let store = store(was: .fullAccess, now: .denied, fetches: fetches)

        await store.send(.applicationDidBecomeActive) {
            $0.calendarAuthorizationStatus = .denied
            $0.events = []
            $0.eventsDate = nil
        }
        #expect(fetches.value == 0)
    }
}
