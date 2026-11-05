import ComposableArchitecture
import EventKit
import Foundation
import Testing

@testable import GlimpseCore

@MainActor
struct CalendarFeatureTests {
    private nonisolated static let firstRequest = UUID(1)
    private nonisolated static let secondRequest = UUID(2)

    @Test
    func onAppear_revokedAccessClearsStaleEvents() async {
        let day = Date(timeIntervalSince1970: 1_000_000)
        var state = CalendarFeature.State(displayedMonth: day)
        state.calendarAuthorizationStatus = .fullAccess
        state.events = [
            CalendarEvent(id: "old", title: "Private event", startDate: day, endDate: day, isAllDay: false)
        ]
        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { true }
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
            $0.eventKitClient.authorizationStatus = { .denied }
        }

        await store.send(.onAppear) {
            $0.calendarAuthorizationStatus = .denied
            $0.events = []
        }
    }

    @Test
    func onAppear_loadsDaysAndPreferences() async {
        let testDays = [
            CalendarDay(date: Date(), isCurrentMonth: true)
        ]

        let store = TestStore(
            initialState: CalendarFeature.State()
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.preferencesClient.loadStartOfWeekday = { 2 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5] }
            $0.preferencesClient.loadShowAISearch = { false }
            $0.calendarClient.calendarDays = { _, _ in testDays }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 2, endRow: 4) }
            $0.eventKitClient.authorizationStatus = { .notDetermined }
        }

        await store.send(.onAppear) {
            $0.startOfWeekday = 2
            $0.workdays = [2, 3, 4, 5]
            $0.showAISearch = false
            $0.days = testDays
            $0.gridInfo = GridInfo(startCol: 0, endCol: 2, endRow: 4)
        }
    }

    @Test
    func goToNextMonth_advancesMonth() async {
        let cal = Calendar.current
        let jan = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let feb = cal.date(from: DateComponents(year: 2026, month: 2, day: 15))!

        let store = TestStore(
            initialState: CalendarFeature.State(displayedMonth: jan)
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
        }

        await store.send(.goToNextMonth) {
            $0.displayedMonth = feb
        }
    }

    @Test
    func goToPreviousMonth_goesBack() async {
        let cal = Calendar.current
        let feb = cal.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        let jan = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!

        let store = TestStore(
            initialState: CalendarFeature.State(displayedMonth: feb)
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
        }

        await store.send(.goToPreviousMonth) {
            $0.displayedMonth = jan
        }
    }

    @Test
    func goToNextYear_advancesYear() async {
        let cal = Calendar.current
        let mar2026 = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let mar2027 = cal.date(from: DateComponents(year: 2027, month: 3, day: 15))!

        let store = TestStore(
            initialState: CalendarFeature.State(displayedMonth: mar2026)
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
        }

        await store.send(.goToNextYear) {
            $0.displayedMonth = mar2027
        }
    }

    @Test
    func goToPreviousYear_goesBack() async {
        let cal = Calendar.current
        let mar2026 = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let mar2025 = cal.date(from: DateComponents(year: 2025, month: 3, day: 15))!

        let store = TestStore(
            initialState: CalendarFeature.State(displayedMonth: mar2026)
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
        }

        await store.send(.goToPreviousYear) {
            $0.displayedMonth = mar2025
        }
    }

    @Test
    func togglePin_togglesState() async {
        let store = TestStore(
            initialState: CalendarFeature.State()
        ) {
            CalendarFeature()
        }

        await store.send(.togglePin) {
            $0.isPinned = true
        }

        await store.send(.togglePin) {
            $0.isPinned = false
        }
    }

    @Test
    func togglePreferences_togglesState() async {
        let store = TestStore(
            initialState: CalendarFeature.State()
        ) {
            CalendarFeature()
        }

        await store.send(.togglePreferences) {
            $0.showingPreferences = true
        }

        await store.send(.togglePreferences) {
            $0.showingPreferences = false
        }
    }

    @Test
    func closePanel_resetsPinned() async {
        var state = CalendarFeature.State()
        state.isPinned = true

        let store = TestStore(initialState: state) {
            CalendarFeature()
        }

        await store.send(.closePanel) {
            $0.isPinned = false
        }
    }

    @Test
    func onDisappear_resetsPreferencesFlag() async {
        let now = Date(timeIntervalSince1970: 1000000)
        var state = CalendarFeature.State()
        state.showingPreferences = true

        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
        }

        store.exhaustivity = .off

        await store.send(.onDisappear) {
            $0.showingPreferences = false
            $0.displayedMonth = now
        }
    }

    @Test
    func hiddenPreservingContext_keepsMonthAndDateButEndsEventLoad() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let browsedMonth = Date(timeIntervalSince1970: 5_000_000)
        let selected = Date(timeIntervalSince1970: 5_100_000)
        var state = CalendarFeature.State()
        state.displayedMonth = browsedMonth
        state.selectedDate = selected
        state.showingPreferences = true
        state.isLoadingEvents = true
        state.eventsRequestID = UUID()

        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.hiddenPreservingContext) {
            $0.showingPreferences = false
            $0.isLoadingEvents = false
            $0.eventsRequestID = nil
        }
        #expect(store.state.displayedMonth == browsedMonth)
        #expect(store.state.selectedDate == selected)
    }

    @Test
    func goToToday_resetsMonthAndSelection() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldMonth = Date(timeIntervalSince1970: 0)

        var state = CalendarFeature.State(displayedMonth: oldMonth)
        state.selectedDate = oldMonth

        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.eventKitClient.authorizationStatus = { .notDetermined }
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
        }

        await store.send(.goToToday) {
            $0.displayedMonth = now
            $0.selectedDate = now
        }
    }

    @Test
    func prepareForReopen_resetsToTodayAndReloadsPreferences() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldMonth = Date(timeIntervalSince1970: 0)
        let testDays = [CalendarDay(date: now, isCurrentMonth: true)]

        // Simulate a panel left on an old month with a stale selection and prefs open.
        var state = CalendarFeature.State(displayedMonth: oldMonth)
        state.selectedDate = oldMonth
        state.showingPreferences = true

        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.eventKitClient.authorizationStatus = { .notDetermined }
            $0.preferencesClient.loadStartOfWeekday = { 2 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4] }
            $0.preferencesClient.loadShowAISearch = { false }
            $0.calendarClient.calendarDays = { _, _ in testDays }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 2, endRow: 4) }
        }

        await store.send(.prepareForReopen) {
            $0.showingPreferences = false
            $0.displayedMonth = now
            $0.selectedDate = now
            $0.startOfWeekday = 2
            $0.workdays = [2, 3, 4]
            $0.showAISearch = false
            $0.days = testDays
            $0.gridInfo = GridInfo(startCol: 0, endCol: 2, endRow: 4)
        }
    }

    @Test
    func prepareForReopen_withCalendarAccess_refetchesTodayEvents() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oldMonth = Date(timeIntervalSince1970: 0)
        let todayEvent = CalendarEvent(
            id: "1", title: "Today Meeting",
            startDate: now, endDate: now,
            isAllDay: false
        )

        // Panel left on an old month with stale events from a previous session.
        var state = CalendarFeature.State(displayedMonth: oldMonth)
        state.selectedDate = oldMonth
        state.calendarAuthorizationStatus = .fullAccess
        state.events = []  // stale

        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { true }
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { _ in [todayEvent] }
            $0.uuid = .constant(Self.firstRequest)
        }

        await store.send(.prepareForReopen) {
            $0.displayedMonth = now
            $0.selectedDate = now
            $0.eventsDate = Calendar.current.startOfDay(for: now)
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }

        // Reopening with calendar access must refresh today's events, not leave
        // whatever was loaded for the previously-selected date.
        await store.receive(\.eventsLoaded) {
            $0.events = [todayEvent]
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test
    func dateTapped_selectsDate() async {
        let cal = Calendar.current
        let march15 = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        let store = TestStore(
            initialState: CalendarFeature.State()
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.eventKitClient.authorizationStatus = { .notDetermined }
        }

        await store.send(.dateTapped(march15)) {
            $0.selectedDate = march15
        }
    }

    @Test
    func dateTapped_togglesSelection() async {
        let cal = Calendar.current
        let march15 = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        var state = CalendarFeature.State()
        state.selectedDate = march15

        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.eventKitClient.authorizationStatus = { .notDetermined }
        }

        await store.send(.dateTapped(march15)) {
            $0.selectedDate = nil
        }
    }

    @Test
    func dateTapped_deselect_refetchesTodayEvents() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cal = Calendar.current
        let march15 = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let todayEvent = CalendarEvent(
            id: "1", title: "Today Meeting",
            startDate: now, endDate: now,
            isAllDay: false
        )

        var state = CalendarFeature.State()
        state.selectedDate = march15
        state.calendarAuthorizationStatus = .fullAccess
        state.events = [] // stale from previous filtered fetch

        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { day in
                #expect(day == Calendar.current.startOfDay(for: now))
                return [todayEvent]
            }
            $0.uuid = .constant(Self.firstRequest)
        }

        await store.send(.dateTapped(march15)) {
            $0.selectedDate = nil
            $0.eventsDate = Calendar.current.startOfDay(for: now)
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }

        await store.receive(\.eventsLoaded) {
            $0.events = [todayEvent]
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test
    func aiDateResult_navigatesAndSelects() async {
        let cal = Calendar.current
        let july4 = cal.date(from: DateComponents(year: 2026, month: 7, day: 4))!

        let store = TestStore(
            initialState: CalendarFeature.State()
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.eventKitClient.authorizationStatus = { .notDetermined }
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
        }

        store.exhaustivity = .off

        await store.send(.aiDateResult(july4)) {
            $0.displayedMonth = july4
            $0.selectedDate = july4
        }
    }

    @Test
    func aiDateResult_nilDoesNothing() async {
        let store = TestStore(
            initialState: CalendarFeature.State()
        ) {
            CalendarFeature()
        }

        await store.send(.aiDateResult(nil))
    }

    @Test
    func eventsLoaded_updatesMatchingRequest() async {
        let day = Date(timeIntervalSince1970: 1_000_000)
        let events = [
            CalendarEvent(
                id: "1", title: "Meeting",
                startDate: day, endDate: day,
                isAllDay: false
            )
        ]

        var state = CalendarFeature.State()
        state.calendarAuthorizationStatus = .fullAccess
        state.eventsDate = day
        state.eventsRequestID = Self.firstRequest
        state.isLoadingEvents = true
        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.eventKitClient.authorizationStatus = { .fullAccess }
        }

        await store.send(.eventsLoaded(date: day, requestID: Self.firstRequest, events: events)) {
            $0.events = events
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test
    func calendarAccessResult_granted_fetchesEvents() async {
        let store = TestStore(
            initialState: CalendarFeature.State()
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { _ in [] }
            $0.uuid = .constant(Self.firstRequest)
        }

        await store.send(.calendarAccessResult(.fullAccess)) {
            $0.calendarAuthorizationStatus = .fullAccess
            $0.eventsDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }

        await store.receive(\.eventsLoaded) {
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test
    func calendarAccessResult_denied() async {
        let store = TestStore(
            initialState: CalendarFeature.State()
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.calendarAccessResult(.denied)) {
            $0.calendarAuthorizationStatus = .denied
        }
    }


    @Test
    func reloadPreferences_updatesWeekdayAndWorkdays() async {
        let testDays = [
            CalendarDay(date: Date(), isCurrentMonth: true)
        ]

        // Start with defaults
        let store = TestStore(
            initialState: CalendarFeature.State()
        ) {
            CalendarFeature()
        } withDependencies: {
            $0.preferencesClient.loadStartOfWeekday = { 3 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4] }
            $0.preferencesClient.loadShowAISearch = { false }
            $0.calendarClient.calendarDays = { _, _ in testDays }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 2, endRow: 4) }
        }

        await store.send(.reloadPreferences) {
            $0.startOfWeekday = 3
            $0.workdays = [2, 3, 4]
            $0.showAISearch = false
            $0.days = testDays
            $0.gridInfo = GridInfo(startCol: 0, endCol: 2, endRow: 4)
        }
    }

    @Test
    func dateTapped_queriesSelectedDayAndKeepsOverlappingEvents() async {
        let tomorrow = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16))!
        let oldDay = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let event = CalendarEvent(
            id: "overlap", title: "Multi-day event", startDate: oldDay,
            endDate: tomorrow.addingTimeInterval(3_600), isAllDay: true
        )
        var state = CalendarFeature.State(displayedMonth: oldDay)
        state.calendarAuthorizationStatus = .fullAccess
        state.events = [CalendarEvent(id: "old", title: "Old", startDate: oldDay, endDate: oldDay, isAllDay: false)]
        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(oldDay)
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { requestedDate in
                #expect(requestedDate == tomorrow)
                return [event]
            }
            $0.uuid = .constant(Self.firstRequest)
        }

        await store.send(.dateTapped(tomorrow)) {
            $0.selectedDate = tomorrow
            $0.events = []
            $0.eventsDate = tomorrow
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.events = [event]
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test
    func eventsResponses_rejectOlderRequestForSameDay() async {
        let day = Date(timeIntervalSince1970: 1_000_000)
        let stale = CalendarEvent(id: "stale", title: "Stale", startDate: day, endDate: day, isAllDay: false)
        var state = CalendarFeature.State()
        state.calendarAuthorizationStatus = .fullAccess
        state.eventsDate = day
        state.eventsRequestID = Self.secondRequest
        state.isLoadingEvents = true
        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.eventKitClient.authorizationStatus = { .fullAccess }
        }

        await store.send(.eventsLoaded(date: day, requestID: Self.firstRequest, events: [stale]))
        await store.send(.eventsFailed(date: day, requestID: Self.firstRequest, message: "Old failure"))
        await store.send(.eventsLoaded(date: day.addingTimeInterval(86_400), requestID: Self.secondRequest, events: [stale]))
        #expect(store.state.isLoadingEvents)
        #expect(store.state.events.isEmpty)
    }

    @Test
    func rapidDateSelection_cancelsOlderQueryAndKeepsLatestResults() async throws {
        struct OldQueryError: LocalizedError {
            var errorDescription: String? { "Old query failed" }
        }
        let firstDay = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let secondDay = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 2_000_000))
        let latest = CalendarEvent(id: "latest", title: "Latest", startDate: secondDay, endDate: secondDay, isAllDay: false)
        let pending = AsyncStream<CheckedContinuation<[CalendarEvent], any Error>>.makeStream()
        let oldReturned = AsyncStream<Void>.makeStream()
        let requestIDs = LockIsolated([Self.firstRequest, Self.secondRequest])
        var pendingRequests = pending.stream.makeAsyncIterator()
        var oldReturns = oldReturned.stream.makeAsyncIterator()
        var state = CalendarFeature.State(displayedMonth: firstDay)
        state.calendarAuthorizationStatus = .fullAccess
        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.uuid = .init { requestIDs.withValue { $0.removeFirst() } }
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { requestedDate in
                do {
                    return try await withCheckedThrowingContinuation { continuation in
                        pending.continuation.yield(continuation)
                    }
                } catch {
                    if requestedDate == firstDay {
                        #expect(Task.isCancelled)
                        oldReturned.continuation.yield()
                    }
                    throw error
                }
            }
        }

        await store.send(.dateTapped(firstDay)) {
            $0.selectedDate = firstDay
            $0.eventsDate = firstDay
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }
        let oldQuery = try #require(await pendingRequests.next())
        await store.send(.dateTapped(secondDay)) {
            $0.selectedDate = secondDay
            $0.eventsDate = secondDay
            $0.eventsRequestID = Self.secondRequest
        }
        let latestQuery = try #require(await pendingRequests.next())
        latestQuery.resume(returning: [latest])
        await store.receive(\.eventsLoaded) {
            $0.events = [latest]
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
        oldQuery.resume(throwing: OldQueryError())
        _ = await oldReturns.next()
        pending.continuation.finish()
        oldReturned.continuation.finish()
        await store.finish()
        #expect(store.state.events == [latest])
        #expect(store.state.eventsError == nil)
    }

    @Test(arguments: [EKAuthorizationStatus.notDetermined, .denied, .restricted, .writeOnly])
    func refreshCalendarAuthorization_clearsUnauthorizedEvents(status: EKAuthorizationStatus) async {
        let day = Date(timeIntervalSince1970: 1_000_000)
        var state = CalendarFeature.State(displayedMonth: day)
        state.calendarAuthorizationStatus = .fullAccess
        state.events = [CalendarEvent(id: "old", title: "Private", startDate: day, endDate: day, isAllDay: false)]
        state.eventsDate = day
        state.eventsRequestID = Self.firstRequest
        state.isLoadingEvents = true
        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.eventKitClient.authorizationStatus = { status }
            $0.eventKitClient.fetchEvents = { _ in
                Issue.record("Unauthorized refresh must not query events")
                return []
            }
            $0.eventKitClient.requestAccess = {
                Issue.record("Refresh must never request permission")
                return false
            }
        }

        await store.send(.refreshCalendarAuthorization) {
            $0.calendarAuthorizationStatus = status
            $0.events = []
            $0.eventsDate = nil
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test
    func eventsLoaded_afterRevocationDiscardsPrivateResults() async {
        let day = Date(timeIntervalSince1970: 1_000_000)
        var state = CalendarFeature.State(displayedMonth: day)
        state.calendarAuthorizationStatus = .fullAccess
        state.eventsDate = day
        state.eventsRequestID = Self.firstRequest
        state.isLoadingEvents = true
        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.eventKitClient.authorizationStatus = { .denied }
        }

        await store.send(.eventsLoaded(
            date: day, requestID: Self.firstRequest,
            events: [CalendarEvent(id: "private", title: "Private", startDate: day, endDate: day, isAllDay: false)]
        )) {
            $0.calendarAuthorizationStatus = .denied
            $0.eventsDate = nil
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test(arguments: [false, true])
    func todayAndAISelection_loadEvents(isAI: Bool) async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let target = isAI ? Date(timeIntervalSince1970: 2_000_000) : now
        let targetDay = Calendar.current.startOfDay(for: target)
        var state = CalendarFeature.State(displayedMonth: Date(timeIntervalSince1970: 0))
        state.calendarAuthorizationStatus = .fullAccess
        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.uuid = .constant(Self.firstRequest)
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { requestedDate in
                #expect(requestedDate == targetDay)
                return []
            }
        }

        await store.send(isAI ? .aiDateResult(target) : .goToToday) {
            $0.displayedMonth = target
            $0.selectedDate = target
            $0.eventsDate = targetDay
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.isLoadingEvents = false
            $0.eventsRequestID = nil
        }
    }

    @Test
    func fetchFailure_andRetryRemainDistinctFromEmptyDay() async {
        struct FetchError: LocalizedError {
            var errorDescription: String? { "fetch failed" }
        }
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let shouldFail = LockIsolated(true)
        var state = CalendarFeature.State(displayedMonth: day)
        state.selectedDate = day
        state.calendarAuthorizationStatus = .fullAccess
        let store = TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.uuid = .constant(Self.firstRequest)
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { requestedDate in
                #expect(requestedDate == day)
                if shouldFail.value { throw FetchError() }
                return []
            }
        }

        await store.send(.retryEvents) {
            $0.eventsDate = day
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsFailed) {
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
            $0.eventsError = "fetch failed"
        }
        shouldFail.setValue(false)
        await store.send(.retryEvents) {
            $0.eventsError = nil
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
        #expect(store.state.eventsError == nil)
        #expect(store.state.events.isEmpty)
    }

    @Test
    func requestCalendarAccess_disablesDuplicatesAndUsesActualStatus() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let authorization = LockIsolated(EKAuthorizationStatus.notDetermined)
        let request = AsyncStream<Bool>.makeStream()
        let store = TestStore(initialState: CalendarFeature.State(displayedMonth: now)) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.uuid = .constant(Self.firstRequest)
            $0.eventKitClient.authorizationStatus = { authorization.value }
            $0.eventKitClient.requestAccess = {
                for await result in request.stream { return result }
                return false
            }
            $0.eventKitClient.fetchEvents = { _ in [] }
        }

        await store.send(.requestCalendarAccess) {
            $0.isRequestingCalendarAccess = true
        }
        await store.send(.requestCalendarAccess)
        authorization.setValue(.fullAccess)
        request.continuation.yield(false) // The system's re-read status is the authority.
        request.continuation.finish()
        await store.receive(\.calendarAccessResult) {
            $0.isRequestingCalendarAccess = false
            $0.calendarAuthorizationStatus = .fullAccess
            $0.eventsDate = Calendar.current.startOfDay(for: now)
            $0.eventsRequestID = Self.firstRequest
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.isLoadingEvents = false
            $0.eventsRequestID = nil
        }
    }

    @Test
    func requestCalendarAccess_errorIsVisible() async {
        struct AccessError: LocalizedError {
            var errorDescription: String? { "access failed" }
        }
        let store = TestStore(initialState: CalendarFeature.State()) {
            CalendarFeature()
        } withDependencies: {
            $0.eventKitClient.authorizationStatus = { .notDetermined }
            $0.eventKitClient.requestAccess = { throw AccessError() }
        }

        await store.send(.requestCalendarAccess) {
            $0.isRequestingCalendarAccess = true
        }
        await store.receive(\.calendarAccessFailed) {
            $0.isRequestingCalendarAccess = false
            $0.calendarAccessError = "access failed"
        }
    }
}
