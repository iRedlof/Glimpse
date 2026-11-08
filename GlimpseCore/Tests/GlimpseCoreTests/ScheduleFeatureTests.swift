import ComposableArchitecture
import EventKit
import Foundation
import Testing

@testable import GlimpseCore

@MainActor
struct ScheduleFeatureTests {
    private nonisolated static let calendar = fixedCalendar()
    private nonisolated static let day = "2026-11-12"
    private nonisolated static let now = instant("2026-11-08", "10:00", calendar)
    private nonisolated static let work = WritableCalendar(id: "work", title: "Work")
    private nonisolated static let draft = EventDraft(
        title: "Coffee with Priya", day: civil(day), window: .partOfDay(.afternoon), durationMinutes: 30
    )
    private nonisolated static let busy = [
        CalendarEvent(id: "a", title: "Lunch", startDate: at("13:00"), endDate: at("14:00"), isAllDay: false),
        CalendarEvent(id: "b", title: "Review", startDate: at("14:30"), endDate: at("15:30"), isAllDay: false),
        CalendarEvent(id: "c", title: "Standup", startDate: at("16:00"), endDate: at("16:15"), isAllDay: false),
        CalendarEvent(id: "d", title: "Gym", startDate: at("16:45"), endDate: at("17:30"), isAllDay: false),
    ]
    private nonisolated static let slots = [
        FreeSlot(start: at("14:00"), end: at("14:30")),
        FreeSlot(start: at("15:30"), end: at("16:00")),
        FreeSlot(start: at("16:15"), end: at("16:45")),
    ]
    private nonisolated static let saved = SavedEvent(
        eventID: "new-1", title: "Coffee with Priya", start: at("15:30"), end: at("16:00"), calendarTitle: "Work"
    )

    private nonisolated static func at(_ hhmm: String) -> Date { instant(day, hhmm, calendar) }

    private func makeStore(
        _ state: ScheduleFeature.State = ScheduleFeature.State(),
        status: EKAuthorizationStatus = .fullAccess,
        clock: TestClock<Duration> = TestClock(),
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<ScheduleFeature> {
        TestStore(initialState: state) {
            ScheduleFeature()
        } withDependencies: {
            $0.date = .constant(Self.now)
            $0.uuid = .incrementing
            $0.continuousClock = clock
            $0.eventKitClient.authorizationStatus = { status }
            $0.eventKitClient.defaultWritableCalendar = { Self.work }
            $0.eventKitClient.fetchEventsInInterval = { _ in Self.busy }
            configure(&$0)
        }
    }

    private func choosing(selected: Int? = nil) -> ScheduleFeature.State {
        var state = ScheduleFeature.State()
        state.draft = Self.draft
        state.searchCalendar = Self.calendar
        state.phase = .choosing
        state.slots = Self.slots
        state.dayEvents = Self.busy
        state.calendar = Self.work
        state.selectedSlotIndex = selected
        return state
    }

    // MARK: - Search

    @Test
    func beginWithFullAccessFindsSlotsWithNothingSelected() async {
        let windows = LockIsolated<[DateInterval]>([])
        let store = makeStore { deps in
            deps.eventKitClient.fetchEventsInInterval = { window in
                windows.withValue { $0.append(window) }
                return Self.busy
            }
        }
        await store.send(.begin(Self.draft, Self.calendar)) {
            $0.draft = Self.draft
            $0.searchCalendar = Self.calendar
            $0.phase = .searching
            $0.searchID = UUID(0)
        }
        await store.receive(\.slotsLoaded) {
            $0.phase = .choosing
            $0.calendar = Self.work
            $0.slots = Self.slots
            $0.dayEvents = Self.busy
            $0.searchID = nil
        }
        #expect(store.state.selectedSlotIndex == nil)
        #expect(!store.state.canConfirm)
        #expect(windows.value == [DateInterval(start: Self.at("13:00"), end: Self.at("17:00"))])
    }

    @Test
    func staleSearchResultsAreDropped() async {
        var state = ScheduleFeature.State()
        state.draft = Self.draft
        state.phase = .searching
        state.searchID = UUID(7)
        let store = makeStore(state)
        await store.send(.slotsLoaded(searchID: UUID(3), calendar: Self.work, events: [], slots: Self.slots))
        await store.send(.slotsFailed(searchID: UUID(3), .searchFailed))
    }

    @Test
    func noWritableCalendarFails() async {
        let store = makeStore { $0.eventKitClient.defaultWritableCalendar = { nil } }
        await store.send(.begin(Self.draft, Self.calendar)) {
            $0.draft = Self.draft
            $0.searchCalendar = Self.calendar
            $0.phase = .searching
            $0.searchID = UUID(0)
        }
        await store.receive(\.slotsLoaded) {
            $0.phase = .failed(.noWritableCalendar)
            $0.searchID = nil
        }
    }

    @Test
    func fullyBookedWindowSaysNoSlots() async {
        let blocked = [CalendarEvent(id: "x", title: "Offsite", startDate: Self.at("12:00"),
                                     endDate: Self.at("18:00"), isAllDay: false)]
        let store = makeStore { $0.eventKitClient.fetchEventsInInterval = { _ in blocked } }
        await store.send(.begin(Self.draft, Self.calendar)) {
            $0.draft = Self.draft
            $0.searchCalendar = Self.calendar
            $0.phase = .searching
            $0.searchID = UUID(0)
        }
        await store.receive(\.slotsLoaded) {
            $0.phase = .noSlots
            $0.calendar = Self.work
            $0.dayEvents = blocked
            $0.searchID = nil
        }
    }

    @Test
    func searchFailureIsReported() async {
        struct Boom: Error {}
        let store = makeStore { $0.eventKitClient.fetchEventsInInterval = { _ in throw Boom() } }
        await store.send(.begin(Self.draft, Self.calendar)) {
            $0.draft = Self.draft
            $0.searchCalendar = Self.calendar
            $0.phase = .searching
            $0.searchID = UUID(0)
        }
        await store.receive(\.slotsFailed) {
            $0.phase = .failed(.searchFailed)
            $0.searchID = nil
        }
    }

    // MARK: - Permission

    @Test
    func notDeterminedAsksForAnExplicitTapAndDoesNotPrompt() async {
        let requests = LockIsolated(0)
        let store = makeStore(status: .notDetermined) { deps in
            deps.eventKitClient.requestAccess = {
                requests.withValue { $0 += 1 }
                return true
            }
        }
        await store.send(.begin(Self.draft, Self.calendar)) {
            $0.draft = Self.draft
            $0.searchCalendar = Self.calendar
            $0.phase = .needsAccess
        }
        #expect(requests.value == 0)
    }

    @Test(arguments: [EKAuthorizationStatus.denied, .restricted, .writeOnly])
    func unavailableAccessExplainsItself(_ status: EKAuthorizationStatus) async {
        let store = makeStore(status: status)
        await store.send(.begin(Self.draft, Self.calendar)) {
            $0.draft = Self.draft
            $0.searchCalendar = Self.calendar
            $0.phase = .accessUnavailable(status)
        }
    }

    @Test
    func allowingAccessRequestsOnceThenSearches() async {
        let requests = LockIsolated(0)
        let status = LockIsolated(EKAuthorizationStatus.notDetermined)
        var state = ScheduleFeature.State()
        state.draft = Self.draft
        state.searchCalendar = Self.calendar
        state.phase = .needsAccess
        let store = makeStore(state) { deps in
            deps.eventKitClient.authorizationStatus = { status.value }
            deps.eventKitClient.requestAccess = {
                requests.withValue { $0 += 1 }
                status.setValue(.fullAccess)
                return true
            }
        }
        await store.send(.allowAccessTapped) { $0.phase = .requestingAccess }
        await store.receive(\.accessResult) {
            $0.phase = .searching
            $0.searchID = UUID(0)
        }
        await store.receive(\.delegate.authorizationChanged)
        await store.receive(\.slotsLoaded) {
            $0.phase = .choosing
            $0.calendar = Self.work
            $0.slots = Self.slots
            $0.dayEvents = Self.busy
            $0.searchID = nil
        }
        #expect(requests.value == 1)
    }

    @Test
    func repeatedAllowWhileTheSystemPromptIsUpIsIgnored() async {
        let requests = LockIsolated(0)
        let gate = AsyncStream<Void>.makeStream()
        var state = ScheduleFeature.State()
        state.draft = Self.draft
        state.phase = .needsAccess
        let store = makeStore(state, status: .denied) { deps in
            deps.eventKitClient.requestAccess = {
                requests.withValue { $0 += 1 }
                for await _ in gate.stream { break }
                return false
            }
        }
        await store.send(.allowAccessTapped) { $0.phase = .requestingAccess }
        await store.send(.allowAccessTapped)
        await store.send(.allowAccessTapped)
        gate.continuation.yield()
        await store.receive(\.accessResult) { $0.phase = .accessUnavailable(.denied) }
        await store.receive(\.delegate.authorizationChanged)
        #expect(requests.value == 1)
    }

    @Test
    func deniedAfterPromptExplainsAndNotifiesParent() async {
        var state = ScheduleFeature.State()
        state.draft = Self.draft
        state.phase = .needsAccess
        let store = makeStore(state, status: .denied) { deps in
            deps.eventKitClient.requestAccess = { false }
        }
        await store.send(.allowAccessTapped) { $0.phase = .requestingAccess }
        await store.receive(\.accessResult) { $0.phase = .accessUnavailable(.denied) }
        await store.receive(\.delegate.authorizationChanged)
    }

    @Test
    func allowAccessOutsideNeedsAccessIsIgnored() async {
        let store = makeStore(choosing())
        await store.send(.allowAccessTapped)
    }

    // MARK: - Honest button

    @Test
    func confirmWithoutAPickNeverSaves() async {
        let saves = LockIsolated(0)
        let store = makeStore(choosing()) { deps in
            deps.eventKitClient.saveEvent = { _ in
                saves.withValue { $0 += 1 }
                return Self.saved
            }
        }
        await store.send(.confirmTapped)
        await store.send(.confirmTapped)
        #expect(saves.value == 0)
    }

    @Test
    func moveSelectionStartsAtTheEndsAndClamps() async {
        let store = makeStore(choosing())
        await store.send(.moveSelection(1)) { $0.selectedSlotIndex = 0 }
        await store.send(.moveSelection(1)) { $0.selectedSlotIndex = 1 }
        await store.send(.moveSelection(1)) { $0.selectedSlotIndex = 2 }
        await store.send(.moveSelection(1))
        await store.send(.moveSelection(-1)) { $0.selectedSlotIndex = 1 }
        await store.send(.moveSelection(-1)) { $0.selectedSlotIndex = 0 }
        await store.send(.moveSelection(-1))

        let fromBottom = makeStore(choosing())
        await fromBottom.send(.moveSelection(-1)) { $0.selectedSlotIndex = 2 }
        await fromBottom.send(.slotSelected(0)) { $0.selectedSlotIndex = 0 }
        await fromBottom.send(.slotSelected(9))
    }

    @Test
    func moveSelectionOnlyWhileChoosing() async {
        var state = choosing()
        state.phase = .searching
        let store = makeStore(state)
        await store.send(.moveSelection(1))
    }

    @Test
    func confirmSavesThePickedSlotAndOffersUndo() async {
        let requests = LockIsolated<[NewEvent]>([])
        let clock = TestClock()
        let store = makeStore(choosing(selected: 1), clock: clock) { deps in
            deps.eventKitClient.saveEvent = { new in
                requests.withValue { $0.append(new) }
                return Self.saved
            }
        }
        await store.send(.confirmTapped) { $0.phase = .saving }
        await store.receive(\.saveSucceeded) {
            $0 = ScheduleFeature.State()
            $0.searchCalendar = Self.calendar
            $0.undo = .init(event: Self.saved, remaining: ScheduleFeature.undoSeconds, status: .available)
        }
        await store.receive(\.delegate.eventsChanged)
        #expect(requests.value == [NewEvent(title: "Coffee with Priya", start: Self.at("15:30"),
                                            end: Self.at("16:00"), calendarID: "work")])
        await clock.advance(by: .seconds(1))
        await store.receive(\.undoTick) { $0.undo?.remaining = 9 }
        await store.skipInFlightEffects()
    }

    @Test
    func undoChipExpiresAfterTenSecondsWithoutRemoving() async {
        let removals = LockIsolated(0)
        let clock = TestClock()
        let saving = makeStore(choosing(selected: 0), clock: clock) { deps in
            deps.eventKitClient.saveEvent = { _ in Self.saved }
            deps.eventKitClient.removeEvent = { _ in removals.withValue { $0 += 1 } }
        }
        await saving.send(.slotActivated(0)) {
            $0.selectedSlotIndex = 0
            $0.phase = .saving
        }
        await saving.receive(\.saveSucceeded) {
            $0 = ScheduleFeature.State()
            $0.searchCalendar = Self.calendar
            $0.undo = .init(event: Self.saved, remaining: 10, status: .available)
        }
        await saving.receive(\.delegate.eventsChanged)
        for remaining in stride(from: 9, through: 1, by: -1) {
            await clock.advance(by: .seconds(1))
            await saving.receive(\.undoTick) { $0.undo?.remaining = remaining }
        }
        await clock.advance(by: .seconds(1))
        await saving.receive(\.undoTick) { $0.undo = nil }
        #expect(removals.value == 0)
    }

    @Test
    func undoRemovesTheSavedEvent() async {
        let removed = LockIsolated<[SavedEvent]>([])
        let clock = TestClock()
        let store = makeStore(choosing(selected: 1), clock: clock) { deps in
            deps.eventKitClient.saveEvent = { _ in Self.saved }
            deps.eventKitClient.removeEvent = { event in removed.withValue { $0.append(event) } }
        }
        await store.send(.confirmTapped) { $0.phase = .saving }
        await store.receive(\.saveSucceeded) {
            $0 = ScheduleFeature.State()
            $0.searchCalendar = Self.calendar
            $0.undo = .init(event: Self.saved, remaining: 10, status: .available)
        }
        await store.receive(\.delegate.eventsChanged)
        for remaining in [9, 8, 7, 6] {
            await clock.advance(by: .seconds(1))
            await store.receive(\.undoTick) { $0.undo?.remaining = remaining }
        }
        await store.send(.undoTapped) { $0.undo?.status = .undoing }
        await store.receive(\.undoSucceeded) {
            $0.undo?.status = .undone
            $0.undo?.remaining = 0
        }
        await store.receive(\.delegate.eventsChanged)
        #expect(removed.value == [Self.saved])
        await clock.advance(by: .seconds(10))
    }

    @Test(arguments: [ScheduleError.removeFailed, .eventMissing])
    func undoFailuresSaySo(_ error: ScheduleError) async {
        var state = ScheduleFeature.State()
        state.undo = .init(event: Self.saved, remaining: 5, status: .available)
        let store = makeStore(state) { $0.eventKitClient.removeEvent = { _ in throw error } }
        await store.send(.undoTapped) { $0.undo?.status = .undoing }
        await store.receive(\.undoFailed) { $0.undo?.status = .failed(error) }
        if error == .eventMissing { await store.receive(\.delegate.eventsChanged) }
    }

    @Test
    func takenSlotIsRemovedAndUserPicksAgain() async {
        let store = makeStore(choosing(selected: 1)) { $0.eventKitClient.saveEvent = { _ in throw ScheduleError.slotTaken } }
        await store.send(.confirmTapped) { $0.phase = .saving }
        await store.receive(\.saveFailed) {
            $0.phase = .choosing
            $0.slots = [Self.slots[0], Self.slots[2]]
            $0.selectedSlotIndex = nil
            $0.notice = ScheduleError.slotTaken.message
        }
        await store.send(.moveSelection(1)) {
            $0.selectedSlotIndex = 0
            $0.notice = nil
        }
    }

    @Test
    func lastSlotTakenLeavesNoSlots() async {
        var state = choosing(selected: 0)
        state.slots = [Self.slots[0]]
        let store = makeStore(state) { $0.eventKitClient.saveEvent = { _ in throw ScheduleError.slotTaken } }
        await store.send(.confirmTapped) { $0.phase = .saving }
        await store.receive(\.saveFailed) {
            $0.phase = .noSlots
            $0.slots = []
            $0.selectedSlotIndex = nil
            $0.notice = ScheduleError.slotTaken.message
        }
    }

    @Test
    func saveFailureSaysNothingWasSavedAndOffersNoUndo() async {
        struct Opaque: Error {}
        let store = makeStore(choosing(selected: 0)) { $0.eventKitClient.saveEvent = { _ in throw Opaque() } }
        await store.send(.confirmTapped) { $0.phase = .saving }
        await store.receive(\.saveFailed) {
            $0.phase = .failed(.saveFailed)
            $0.selectedSlotIndex = nil
        }
        #expect(store.state.undo == nil)
    }

    // MARK: - Dismiss

    @Test
    func dismissDuringSavingDoesNotCancelTheSave() async {
        let gate = AsyncStream<Void>.makeStream()
        let clock = TestClock()
        let store = makeStore(choosing(selected: 0), clock: clock) { deps in
            deps.eventKitClient.saveEvent = { _ in
                for await _ in gate.stream { break }
                return Self.saved
            }
            deps.eventKitClient.removeEvent = { _ in }
        }
        await store.send(.confirmTapped) { $0.phase = .saving }
        await store.send(.confirmTapped)
        await store.send(.slotActivated(1))
        await store.send(.dismiss)
        await store.send(.begin(Self.draft, Self.calendar))
        gate.continuation.yield()
        await store.receive(\.saveSucceeded) {
            $0 = ScheduleFeature.State()
            $0.searchCalendar = Self.calendar
            $0.undo = .init(event: Self.saved, remaining: 10, status: .available)
        }
        await store.receive(\.delegate.eventsChanged)
        await store.send(.dismiss)
        #expect(store.state.undo != nil)
        await store.send(.undoTapped) { $0.undo?.status = .undoing }
        await store.receive(\.undoSucceeded) {
            $0.undo?.status = .undone
            $0.undo?.remaining = 0
        }
        await store.receive(\.delegate.eventsChanged)
    }

    @Test
    func dismissClearsTheProposalButKeepsAnAvailableUndo() async {
        var state = choosing(selected: 2)
        state.undo = .init(event: Self.saved, remaining: 4, status: .available)
        let store = makeStore(state)
        await store.send(.dismiss) {
            $0.draft = nil
            $0.phase = .idle
            $0.slots = []
            $0.selectedSlotIndex = nil
            $0.dayEvents = []
            $0.calendar = nil
        }
    }

    @Test
    func dismissDropsAFinishedUndoChip() async {
        var state = ScheduleFeature.State()
        state.undo = .init(event: Self.saved, remaining: 0, status: .undone)
        let store = makeStore(state)
        await store.send(.dismiss) { $0.undo = nil }
    }

    @Test
    func beginReplacesAnEarlierProposal() async {
        let store = makeStore(choosing(selected: 1))
        let other = EventDraft(title: "Lunch", day: civil("2026-11-13"), window: .exact(clock("12:00")), durationMinutes: 60)
        await store.send(.begin(other, Self.calendar)) {
            $0.draft = other
            $0.phase = .searching
            $0.slots = []
            $0.selectedSlotIndex = nil
            $0.dayEvents = []
            $0.calendar = nil
            $0.searchID = UUID(0)
        }
        await store.receive(\.slotsLoaded) {
            $0.phase = .choosing
            $0.calendar = Self.work
            $0.dayEvents = []
            $0.slots = [
                FreeSlot(start: instant("2026-11-13", "12:00", Self.calendar), end: instant("2026-11-13", "13:00", Self.calendar)),
                FreeSlot(start: instant("2026-11-13", "11:00", Self.calendar), end: instant("2026-11-13", "12:00", Self.calendar)),
                FreeSlot(start: instant("2026-11-13", "13:00", Self.calendar), end: instant("2026-11-13", "14:00", Self.calendar)),
            ]
            $0.searchID = nil
        }
    }
}
