import ComposableArchitecture
import EventKit
import Foundation

/// Proposes free times for an `EventDraft` and saves only the time the user
/// explicitly picks. Nothing is preselected, a started save is never
/// cancelled, and a saved event can be undone for `undoSeconds`.
@Reducer
public struct ScheduleFeature: Sendable {
    public static let undoSeconds = 10

    @ObservableState
    public struct State: Equatable, Sendable {
        public var draft: EventDraft?
        public var searchCalendar: Calendar = .current
        public var phase: Phase = .idle
        public var slots: [FreeSlot] = []
        /// nil until the user picks; Return cannot book an unpicked time.
        public var selectedSlotIndex: Int?
        /// Timed events in the search window, shown as timeline context.
        public var dayEvents: [CalendarEvent] = []
        public var calendar: WritableCalendar?
        public var searchID: UUID?
        /// One inline line after a recoverable failure (e.g. slot taken).
        public var notice: String?
        public var undo: UndoChip?

        public init() {}

        public var canConfirm: Bool { phase == .choosing && selectedSlot != nil && calendar != nil }
        public var isProposing: Bool { draft != nil || phase != .idle }
        public var canUndo: Bool { undo?.status == .available && (undo?.remaining ?? 0) > 0 }

        public var selectedSlot: FreeSlot? {
            guard let index = selectedSlotIndex, slots.indices.contains(index) else { return nil }
            return slots[index]
        }
    }

    public struct UndoChip: Equatable, Sendable {
        public var event: SavedEvent
        public var remaining: Int
        public var status: UndoStatus

        public init(event: SavedEvent, remaining: Int, status: UndoStatus) {
            self.event = event
            self.remaining = remaining
            self.status = status
        }
    }

    public enum UndoStatus: Equatable, Sendable {
        case available, undoing, undone
        case failed(ScheduleError)
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case needsAccess
        case requestingAccess
        case accessUnavailable(EKAuthorizationStatus)
        case searching
        case noSlots
        case choosing
        case saving
        case failed(ScheduleError)
    }

    public enum Action: Sendable {
        case begin(EventDraft, Calendar)
        case allowAccessTapped
        case accessResult(EKAuthorizationStatus)
        case slotsLoaded(searchID: UUID, calendar: WritableCalendar?, events: [CalendarEvent], slots: [FreeSlot])
        case slotsFailed(searchID: UUID, ScheduleError)
        /// ↑ = -1, ↓ = +1. With nothing picked, ↓ picks the first and ↑ the last.
        case moveSelection(Int)
        case slotSelected(Int)
        /// Return: saves only when a time has been picked.
        case confirmTapped
        /// Click or VoiceOver activation: an explicit pick that saves.
        case slotActivated(Int)
        case saveSucceeded(SavedEvent)
        case saveFailed(ScheduleError)
        case undoTick
        case undoTapped
        case undoSucceeded
        case undoFailed(ScheduleError)
        /// Escape, an edited draft, or a new query. Never interrupts a save.
        case dismiss
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable {
            case authorizationChanged(EKAuthorizationStatus)
            case eventsChanged
        }
    }

    @Dependency(\.eventKitClient) var eventKitClient
    @Dependency(\.date) var date
    @Dependency(\.uuid) var uuid
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case search, access, undoTimer }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .begin(draft, calendar):
                return begin(draft, calendar: calendar, &state)

            case .allowAccessTapped:
                guard state.phase == .needsAccess else { return .none }
                state.phase = .requestingAccess
                return .run { [eventKitClient] send in
                    do {
                        _ = try await eventKitClient.requestAccess()
                    } catch is CancellationError {
                        return
                    } catch {
                        AppLogger.calendar.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
                    }
                    try Task.checkCancellation()
                    await send(.accessResult(eventKitClient.authorizationStatus()))
                }
                .cancellable(id: CancelID.access, cancelInFlight: true)

            case let .accessResult(status):
                guard state.phase == .requestingAccess else { return .none }
                let notify = Effect<Action>.send(.delegate(.authorizationChanged(status)))
                guard status == .fullAccess else {
                    state.phase = .accessUnavailable(status)
                    return notify
                }
                return .merge(notify, startSearch(&state))

            case let .slotsLoaded(searchID, calendar, events, slots):
                guard state.searchID == searchID else { return .none }
                state.searchID = nil
                guard let calendar else {
                    state.phase = .failed(.noWritableCalendar)
                    return .none
                }
                state.calendar = calendar
                state.dayEvents = events
                state.slots = slots
                state.selectedSlotIndex = nil
                state.phase = slots.isEmpty ? .noSlots : .choosing
                return .none

            case let .slotsFailed(searchID, error):
                guard state.searchID == searchID else { return .none }
                state.searchID = nil
                state.phase = error == .accessUnavailable
                    ? .accessUnavailable(eventKitClient.authorizationStatus())
                    : .failed(error)
                return .none

            case let .moveSelection(delta):
                guard state.phase == .choosing, !state.slots.isEmpty, delta != 0 else { return .none }
                let last = state.slots.count - 1
                let next = state.selectedSlotIndex.map { min(max($0 + delta, 0), last) }
                    ?? (delta > 0 ? 0 : last)
                guard next != state.selectedSlotIndex else { return .none }
                state.selectedSlotIndex = next
                state.notice = nil
                return .none

            case let .slotSelected(index):
                guard state.phase == .choosing, state.slots.indices.contains(index),
                      state.selectedSlotIndex != index else { return .none }
                state.selectedSlotIndex = index
                state.notice = nil
                return .none

            case .confirmTapped:
                guard state.canConfirm else { return .none }
                return save(&state)

            case let .slotActivated(index):
                guard state.phase == .choosing, state.slots.indices.contains(index) else { return .none }
                state.selectedSlotIndex = index
                state.notice = nil
                return save(&state)

            case let .saveSucceeded(event):
                let calendar = state.searchCalendar
                state = State()
                state.searchCalendar = calendar
                state.undo = UndoChip(event: event, remaining: Self.undoSeconds, status: .available)
                return .merge(
                    .send(.delegate(.eventsChanged)),
                    .run { [clock] send in
                        for _ in 0..<Self.undoSeconds {
                            try await clock.sleep(for: .seconds(1))
                            await send(.undoTick)
                        }
                    }
                    .cancellable(id: CancelID.undoTimer, cancelInFlight: true)
                )

            case let .saveFailed(error):
                guard state.phase == .saving else { return .none }
                // Selection cannot move while saving, so it is still the slot that failed.
                let attempted = state.selectedSlot
                state.selectedSlotIndex = nil
                if error == .slotTaken, let taken = attempted {
                    state.slots.removeAll { $0 == taken }
                    state.notice = error.message
                    state.phase = state.slots.isEmpty ? .noSlots : .choosing
                } else {
                    state.phase = .failed(error)
                }
                return .none

            case .undoTick:
                guard var undo = state.undo, undo.status == .available else { return .none }
                undo.remaining -= 1
                guard undo.remaining > 0 else {
                    state.undo = nil
                    return .cancel(id: CancelID.undoTimer)
                }
                state.undo = undo
                return .none

            case .undoTapped:
                guard state.canUndo, let event = state.undo?.event else { return .none }
                state.undo?.status = .undoing
                return .merge(
                    .cancel(id: CancelID.undoTimer),
                    // Not cancellable: once removal is asked for, its outcome is reported.
                    .run { [eventKitClient] send in
                        do {
                            try await eventKitClient.removeEvent(event)
                            await send(.undoSucceeded)
                        } catch {
                            AppLogger.calendar.error("Undo failed: \(error.localizedDescription, privacy: .public)")
                            await send(.undoFailed(ScheduleError.from(error, fallback: .removeFailed)))
                        }
                    }
                )

            case .undoSucceeded:
                state.undo?.status = .undone
                state.undo?.remaining = 0
                return .send(.delegate(.eventsChanged))

            case let .undoFailed(error):
                state.undo?.status = .failed(error)
                return error == .eventMissing ? .send(.delegate(.eventsChanged)) : .none

            case .dismiss:
                return dismiss(&state)

            case .delegate:
                return .none
            }
        }
    }

    /// Shared with the parent so it can start a proposal without an extra action round-trip.
    func begin(_ draft: EventDraft, calendar: Calendar, _ state: inout State) -> Effect<Action> {
        guard state.phase != .saving else {
            AppLogger.calendar.info("Schedule request ignored while saving")
            return .none
        }
        clearProposal(&state)
        state.draft = draft
        state.searchCalendar = calendar
        return .merge(.cancel(id: CancelID.access), startSearch(&state))
    }

    /// Clears the proposal; never interrupts a save and keeps a usable Undo chip.
    func dismiss(_ state: inout State) -> Effect<Action> {
        guard state.phase != .saving else { return .none }
        clearProposal(&state)
        return .merge(.cancel(id: CancelID.search), .cancel(id: CancelID.access))
    }

    private func clearProposal(_ state: inout State) {
        state.draft = nil
        state.phase = .idle
        state.slots = []
        state.selectedSlotIndex = nil
        state.dayEvents = []
        state.calendar = nil
        state.searchID = nil
        state.notice = nil
        if let status = state.undo?.status, status != .available, status != .undoing {
            state.undo = nil
        }
    }

    private func startSearch(_ state: inout State) -> Effect<Action> {
        guard let draft = state.draft else { return .none }
        let status = eventKitClient.authorizationStatus()
        switch status {
        case .fullAccess:
            break
        case .notDetermined:
            state.phase = .needsAccess
            return .cancel(id: CancelID.search)
        default:
            state.phase = .accessUnavailable(status)
            return .cancel(id: CancelID.search)
        }
        let calendar = state.searchCalendar
        guard let window = FreeSlotFinder.window(for: draft, calendar: calendar) else {
            state.phase = .failed(.searchFailed)
            return .cancel(id: CancelID.search)
        }
        let now = date.now
        let searchID = uuid()
        state.phase = .searching
        state.searchID = searchID
        return .run { [eventKitClient] send in
            do {
                guard let target = try await eventKitClient.defaultWritableCalendar() else {
                    await send(.slotsLoaded(searchID: searchID, calendar: nil, events: [], slots: []))
                    return
                }
                let events = try await eventKitClient.fetchEventsInInterval(window)
                try Task.checkCancellation()
                let slots = FreeSlotFinder.slots(for: draft, events: events, now: now, calendar: calendar)
                let context = events.filter {
                    !$0.isAllDay && $0.startDate < window.end && $0.endDate > window.start
                }
                await send(.slotsLoaded(searchID: searchID, calendar: target, events: context, slots: slots))
            } catch is CancellationError {
                return
            } catch {
                AppLogger.calendar.error("Free-time search failed: \(error.localizedDescription, privacy: .public)")
                await send(.slotsFailed(searchID: searchID, ScheduleError.from(error, fallback: .searchFailed)))
            }
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }

    private func save(_ state: inout State) -> Effect<Action> {
        guard let draft = state.draft, let slot = state.selectedSlot, let calendar = state.calendar else {
            return .none
        }
        state.phase = .saving
        state.notice = nil
        let request = NewEvent(title: draft.title, start: slot.start, end: slot.end, calendarID: calendar.id)
        // Deliberately not cancellable: once EventKit is asked, "Saving…" must
        // end in the real outcome, even if the editor or panel closes.
        return .run { [eventKitClient] send in
            do {
                let saved = try await eventKitClient.saveEvent(request)
                await send(.saveSucceeded(saved))
            } catch {
                AppLogger.calendar.error("Event save failed: \(error.localizedDescription, privacy: .public)")
                await send(.saveFailed(ScheduleError.from(error, fallback: .saveFailed)))
            }
        }
    }
}
