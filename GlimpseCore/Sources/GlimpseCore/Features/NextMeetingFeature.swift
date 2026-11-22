import ComposableArchitecture
import EventKit
import Foundation

/// Drives the opt-in "next meeting" segment of the menu bar item.
///
/// EventKit is queried only on `.refresh` (enable, calendar change, wake, midnight,
/// clock/time-zone change, panel close): one predicate for today. Minute ticks only
/// recompute from the cached events, and tick only while a meeting remains today.
@Reducer
public struct NextMeetingFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var isEnabled = false
        /// Today's events from the last fetch (empty when disabled or without access).
        public var events: [CalendarEvent] = []
        /// Start of the day `events` belong to.
        public var eventsDay: Date?
        public var requestID: UUID?
        public var meeting: NextMeeting?
        /// Leave-by buffer in minutes, or nil when "Show leave-by time" is off.
        public var leaveByMinutes: Int?

        public init() {}
    }

    public enum Action: Sendable {
        case setEnabled(Bool)
        /// The leave-by buffer changed (nil: off). Recomputes from the cached events.
        case setLeaveBy(minutes: Int?)
        /// Re-read today's events (calendar changed, wake, day or clock change).
        case refresh
        /// A minute boundary passed: recompute from the cached events.
        case tick
        case eventsLoaded(day: Date, requestID: UUID, events: [CalendarEvent])
        case eventsFailed(day: Date, requestID: UUID)
    }

    @Dependency(\.date) var date
    @Dependency(\.calendar) var calendar
    @Dependency(\.eventKitClient) var eventKitClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.uuid) var uuid

    private enum CancelID { case fetch, tick }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setEnabled(enabled):
                guard enabled != state.isEnabled else { return .none }
                state.isEnabled = enabled
                return enabled ? fetch(&state) : clear(&state)

            case let .setLeaveBy(minutes):
                let minutes = minutes.map(LeaveBy.validatedBuffer)
                guard minutes != state.leaveByMinutes else { return .none }
                state.leaveByMinutes = minutes
                guard state.isEnabled, state.eventsDay != nil else { return .none }
                return recompute(&state, now: date.now)

            case .refresh:
                guard state.isEnabled else { return .none }
                return fetch(&state)

            case .tick:
                guard state.isEnabled else { return .none }
                let now = date.now
                // Crossing midnight while ticking: today is a new day, so re-read it.
                if state.eventsDay != calendar.startOfDay(for: now) { return fetch(&state) }
                return recompute(&state, now: now)

            case let .eventsLoaded(day, requestID, events):
                guard state.isEnabled, state.requestID == requestID else { return .none }
                state.requestID = nil
                state.eventsDay = day
                state.events = events
                return recompute(&state, now: date.now)

            case let .eventsFailed(day, requestID):
                guard state.isEnabled, state.requestID == requestID else { return .none }
                state.requestID = nil
                state.eventsDay = day
                state.events = []
                state.meeting = nil
                return .cancel(id: CancelID.tick)
            }
        }
    }

    private func clear(_ state: inout State) -> Effect<Action> {
        state.events = []
        state.eventsDay = nil
        state.requestID = nil
        state.meeting = nil
        return .merge(.cancel(id: CancelID.fetch), .cancel(id: CancelID.tick))
    }

    private func fetch(_ state: inout State) -> Effect<Action> {
        // Never prompts: without full access the segment simply stays hidden.
        guard eventKitClient.authorizationStatus() == .fullAccess else { return clear(&state) }
        let day = calendar.startOfDay(for: date.now)
        let requestID = uuid()
        state.requestID = requestID
        return .run { [eventKitClient] send in
            do {
                let events = try await eventKitClient.fetchEvents(day)
                try Task.checkCancellation()
                await send(.eventsLoaded(day: day, requestID: requestID, events: events))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.calendar.error(
                    "Next meeting query failed: \(error.localizedDescription, privacy: .public)"
                )
                await send(.eventsFailed(day: day, requestID: requestID))
            }
        }
        .cancellableLatestWins(id: CancelID.fetch)
    }

    private func recompute(_ state: inout State, now: Date) -> Effect<Action> {
        let meeting = NextMeetingSelector.select(
            state.events, now: now, calendar: calendar, leaveByMinutes: state.leaveByMinutes
        )
        if state.meeting != meeting { state.meeting = meeting }
        // Nothing left today: stop ticking. Midnight and calendar changes send `.refresh`.
        guard meeting != nil else { return .cancel(id: CancelID.tick) }
        let delay = NextMeetingSelector.delayUntilNextMinute(after: now)
        return .run { [clock] send in
            // One sleep to the next minute boundary per tick: no polling loop.
            try await clock.sleep(for: .milliseconds(Int((delay * 1000).rounded(.up))))
            await send(.tick)
        }
        .cancellableLatestWins(id: CancelID.tick)
    }
}
