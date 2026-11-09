import ComposableArchitecture
import EventKit
import Foundation
import Testing

@testable import GlimpseCore

@MainActor
struct CalendarFeatureAITests {
    private nonisolated static let now = Calendar.current.date(
        from: DateComponents(year: 2026, month: 11, day: 8, hour: 12)
    )!
    private nonisolated static let fridays = DateRangeHighlight(
        dates: [civil("2026-11-13"), civil("2026-11-20"), civil("2026-11-27")], label: "Next 3 Fridays"
    )
    private nonisolated static let draft = EventDraft(
        title: "Coffee with Priya", day: civil("2026-11-12"), window: .partOfDay(.afternoon), durationMinutes: 30
    )
    private nonisolated static let saved = SavedEvent(
        eventID: "e1", title: "Coffee with Priya", start: now, end: now.addingTimeInterval(1_800), calendarTitle: "Work"
    )

    private static func start(_ iso: String) -> Date { civil(iso).date(in: .current)! }

    private func makeStore(
        _ state: CalendarFeature.State = CalendarFeature.State(displayedMonth: now),
        status: EKAuthorizationStatus = .notDetermined,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<CalendarFeature> {
        TestStore(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(Self.now)
            $0.uuid = .incrementing
            $0.calendarClient.calendarDays = { _, _ in [] }
            $0.calendarClient.gridInfo = { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) }
            $0.eventKitClient.authorizationStatus = { status }
            configure(&$0)
        }
    }

    private func withResults() -> CalendarFeature.State {
        var state = CalendarFeature.State(displayedMonth: Self.now)
        state.highlight = Self.fridays
        state.highlightedDays = Set(Self.fridays.dates.map { $0.date(in: .current)! })
        state.aiAnswer = DateAnswer(text: "80 workdays", detail: nil)
        state.schedule.draft = Self.draft
        state.schedule.phase = .needsAccess
        state.schedule.undo = .init(event: Self.saved, remaining: 5, status: .available)
        return state
    }

    @Test
    func rangeHighlightsDaysAndShowsTheFirst() async {
        let store = makeStore()
        let first = Self.start("2026-11-13")
        await store.send(.aiIntent(.range(Self.fridays))) {
            $0.highlight = Self.fridays
            $0.highlightedDays = [first, Self.start("2026-11-20"), Self.start("2026-11-27")]
            $0.displayedMonth = first
            $0.selectedDate = first
        }
    }

    @Test
    func questionIsAnsweredLocallyWithTheUsersWorkdays() async {
        var state = CalendarFeature.State(displayedMonth: Self.now)
        state.workdays = [2, 3, 4, 5]
        let store = makeStore(state)
        let question = DateQuestion.count(.workdays, from: civil("2026-11-08"), to: civil("2027-03-01"))
        await store.send(.aiIntent(.question(question))) {
            $0.aiAnswer = DateAnswerer.answer(question, today: civil("2026-11-08"), calendar: $0.calendar,
                                              workdays: [2, 3, 4, 5])
        }
        #expect(store.state.aiAnswer?.text == "64 workdays")
    }

    @Test
    func createShowsTheDayAndStartsTheProposalWithoutPrompting() async {
        let requests = LockIsolated(0)
        let store = makeStore { deps in
            deps.eventKitClient.requestAccess = {
                requests.withValue { $0 += 1 }
                return true
            }
        }
        let day = Self.start("2026-11-12")
        await store.send(.aiIntent(.create(Self.draft))) {
            $0.displayedMonth = day
            $0.selectedDate = day
            $0.highlightedDays = [day]
            $0.schedule.draft = Self.draft
            $0.schedule.searchCalendar = $0.calendar
            $0.schedule.phase = .needsAccess
        }
        #expect(requests.value == 0)
    }

    @Test
    func createWithFullAccessSearchesAndLoadsTheDay() async {
        let work = WritableCalendar(id: "w", title: "Work")
        let store = makeStore(status: .fullAccess) { deps in
            deps.eventKitClient.fetchEvents = { _ in [] }
            deps.eventKitClient.defaultWritableCalendar = { work }
            deps.eventKitClient.fetchEventsInInterval = { _ in [] }
        }
        store.exhaustivity = .off
        await store.send(.aiIntent(.create(Self.draft)))
        await store.finish()
        await store.skipReceivedActions()
        #expect(store.state.schedule.phase == .choosing)
        #expect(store.state.schedule.slots.count == 3)
        #expect(store.state.schedule.calendar == work)
        #expect(store.state.schedule.selectedSlotIndex == nil)
        #expect(store.state.calendarAuthorizationStatus == .fullAccess)
    }

    @Test
    func newIntentReplacesEarlierResults() async {
        var state = withResults()
        state.schedule.undo = nil
        let store = makeStore(state)
        await store.send(.aiIntent(.navigate(civil("2026-12-25")))) {
            $0.highlight = nil
            $0.highlightedDays = []
            $0.aiAnswer = nil
            $0.schedule.draft = nil
            $0.schedule.phase = .idle
            $0.displayedMonth = Self.start("2026-12-25")
            $0.selectedDate = Self.start("2026-12-25")
        }
    }

    @Test
    func authorizationChangeFromTheProposalReloadsEvents() async {
        let store = makeStore(status: .fullAccess) { $0.eventKitClient.fetchEvents = { _ in [] } }
        await store.send(.schedule(.delegate(.authorizationChanged(.fullAccess)))) {
            $0.calendarAuthorizationStatus = .fullAccess
            $0.eventsDate = Calendar.current.startOfDay(for: Self.now)
            $0.eventsRequestID = UUID(0)
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
    }

    @Test
    func savedOrUndoneEventReloadsTheAgenda() async {
        let fetches = LockIsolated(0)
        var state = CalendarFeature.State(displayedMonth: Self.now)
        state.calendarAuthorizationStatus = .fullAccess
        let store = makeStore(state, status: .fullAccess) { deps in
            deps.eventKitClient.fetchEvents = { _ in
                fetches.withValue { $0 += 1 }
                return []
            }
        }
        await store.send(.schedule(.delegate(.eventsChanged))) {
            $0.eventsDate = Calendar.current.startOfDay(for: Self.now)
            $0.eventsRequestID = UUID(0)
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
        #expect(fetches.value == 1)
    }

    @Test
    func savedEventReloadsTheAgendaAndTellsTheApp() async {
        let notified = LockIsolated<[SavedEvent]>([])
        var state = CalendarFeature.State(displayedMonth: Self.now)
        state.calendarAuthorizationStatus = .fullAccess
        let store = makeStore(state, status: .fullAccess) { deps in
            deps.eventKitClient.fetchEvents = { _ in [] }
            deps.scheduleEvents.eventSaved = { event in notified.withValue { $0.append(event) } }
        }
        await store.send(.schedule(.delegate(.eventSaved(Self.saved)))) {
            $0.eventsDate = Calendar.current.startOfDay(for: Self.now)
            $0.eventsRequestID = UUID(0)
            $0.isLoadingEvents = true
        }
        await store.receive(\.eventsLoaded) {
            $0.eventsRequestID = nil
            $0.isLoadingEvents = false
        }
        await store.finish()
        #expect(notified.value == [Self.saved])
    }

    /// Tapping another day moves the selection, so a proposal for the old
    /// day (and its slot buttons) must not stay on screen.
    @Test
    func tappingADateClearsAnswersAndTheProposalButKeepsUndo() async {
        let store = makeStore(withResults())
        await store.send(.dateTapped(Self.start("2026-11-20"))) {
            $0.highlight = nil
            $0.highlightedDays = []
            $0.aiAnswer = nil
            $0.selectedDate = Self.start("2026-11-20")
            $0.schedule.draft = nil
            $0.schedule.phase = .idle
        }
        #expect(store.state.schedule.undo != nil)
    }

    @Test
    func tappingADateNeverInterruptsASave() async {
        var state = withResults()
        state.schedule.phase = .saving
        let store = makeStore(state)
        await store.send(.dateTapped(Self.start("2026-11-20"))) {
            $0.highlight = nil
            $0.highlightedDays = []
            $0.aiAnswer = nil
            $0.selectedDate = Self.start("2026-11-20")
        }
        #expect(store.state.schedule.phase == .saving)
    }

    @Test
    func clarificationClearsEarlierResultsAndTheProposal() async {
        let store = makeStore(withResults())
        await store.send(.aiIntent(.clarify("Which day?"))) {
            $0.highlight = nil
            $0.highlightedDays = []
            $0.aiAnswer = nil
            $0.schedule.draft = nil
            $0.schedule.phase = .idle
        }
        #expect(store.state.schedule.undo != nil)
    }

    @Test
    func clearingResultsDismissesTheProposalButKeepsUndo() async {
        let store = makeStore(withResults())
        await store.send(.aiResultsCleared) {
            $0.highlight = nil
            $0.highlightedDays = []
            $0.aiAnswer = nil
            $0.schedule.draft = nil
            $0.schedule.phase = .idle
        }
        #expect(store.state.schedule.undo != nil)
    }

    @Test
    func reopeningClearsResultsAndProposal() async {
        let store = makeStore(withResults()) {
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { true }
        }
        await store.send(.prepareForReopen) {
            $0.highlight = nil
            $0.highlightedDays = []
            $0.aiAnswer = nil
            $0.schedule.draft = nil
            $0.schedule.phase = .idle
            $0.displayedMonth = Self.now
            $0.selectedDate = Self.now
        }
        #expect(store.state.schedule.undo?.remaining == 5)
    }

    @Test
    func disappearingClearsResults() async {
        let store = makeStore(withResults())
        await store.send(.onDisappear) {
            $0.highlight = nil
            $0.highlightedDays = []
            $0.aiAnswer = nil
            $0.schedule.draft = nil
            $0.schedule.phase = .idle
        }
    }

    @Test
    func hidingWithContextKeepsResults() async {
        let store = makeStore(withResults())
        await store.send(.hiddenPreservingContext)
        #expect(store.state.highlight == Self.fridays)
        #expect(store.state.schedule.draft == Self.draft)
    }
}
