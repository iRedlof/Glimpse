import ComposableArchitecture
import EventKit
import Foundation

@Reducer
public struct CalendarFeature: Sendable {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var displayedMonth: Date
        public var days: [CalendarDay] = []
        public var gridInfo: GridInfo = GridInfo(startCol: 0, endCol: 6, endRow: 5)
        public var startOfWeekday: Int = 1
        public var workdays: Set<Int> = [2, 3, 4, 5, 6]
        public var isPinned: Bool = false
        // Temporary reducer-only compatibility for existing reopen/reset fixtures.
        // Settings presentation is owned by SettingsWindowController; no live view reads this.
        public var showingPreferences: Bool = false
        public var events: [CalendarEvent] = []
        public var eventsDate: Date?
        public var eventsRequestID: UUID?
        public var isLoadingEvents = false
        public var eventsError: String?
        public var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
        public var isRequestingCalendarAccess = false
        public var calendarAccessError: String?
        public var selectedDate: Date?
        public var showAISearch: Bool = true

        public var calendarAccessGranted: Bool { calendarAuthorizationStatus == .fullAccess }

        public var selectedDateInfo: String? {
            guard let date = selectedDate else { return nil }
            let cal = Calendar.current
            let week = cal.component(.weekOfYear, from: date)
            let formatted = date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
            return "\(formatted) - Week \(week)"
        }

        public var calendar: Calendar {
            var cal = Calendar.current
            cal.firstWeekday = startOfWeekday
            return cal
        }

        public var isShowingCurrentMonth: Bool {
            Calendar.current.isDate(displayedMonth, equalTo: .now, toGranularity: .month)
        }

        public var monthYearString: String {
            displayedMonth.formatted(.dateTime.month(.wide).year())
        }

        public init(displayedMonth: Date = Date()) {
            self.displayedMonth = displayedMonth
        }
    }

    public enum Action: Sendable {
        case onAppear
        case goToPreviousMonth
        case goToNextMonth
        case goToPreviousYear
        case goToNextYear
        case goToToday
        case dateTapped(Date)
        case togglePin
        case togglePreferences
        case closePanel
        case onDisappear
        /// Hidden without resetting month/date; `.prepareForReopen` resets on the next show.
        case hiddenPreservingContext
        case prepareForReopen
        case requestCalendarAccess
        case calendarAccessResult(EKAuthorizationStatus)
        case calendarAccessFailed(String, EKAuthorizationStatus)
        case refreshCalendarAuthorization
        case retryEvents
        case eventsLoaded(date: Date, requestID: UUID, events: [CalendarEvent])
        case eventsFailed(date: Date, requestID: UUID, message: String)
        case aiDateResult(Date?)
        case reloadPreferences
    }

    @Dependency(\.date) var date
    @Dependency(\.calendarClient) var calendarClient
    @Dependency(\.preferencesClient) var preferencesClient
    @Dependency(\.eventKitClient) var eventKitClient
    @Dependency(\.uuid) var uuid

    private enum CancelID { case events, calendarAccess }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.startOfWeekday = preferencesClient.loadStartOfWeekday()
                state.workdays = preferencesClient.loadWorkdays()
                state.showAISearch = preferencesClient.loadShowAISearch()
                recomputeDays(&state)
                return loadEvents(&state)

            case .goToPreviousMonth:
                if let prev = state.calendar.date(
                    byAdding: .month, value: -1, to: state.displayedMonth
                ) {
                    state.displayedMonth = prev
                    recomputeDays(&state)
                }
                return .none

            case .goToNextMonth:
                if let next = state.calendar.date(
                    byAdding: .month, value: 1, to: state.displayedMonth
                ) {
                    state.displayedMonth = next
                    recomputeDays(&state)
                }
                return .none

            case .goToPreviousYear:
                if let prev = state.calendar.date(
                    byAdding: .year, value: -1, to: state.displayedMonth
                ) {
                    state.displayedMonth = prev
                    recomputeDays(&state)
                }
                return .none

            case .goToNextYear:
                if let next = state.calendar.date(
                    byAdding: .year, value: 1, to: state.displayedMonth
                ) {
                    state.displayedMonth = next
                    recomputeDays(&state)
                }
                return .none

            case .goToToday:
                state.displayedMonth = date.now
                state.selectedDate = date.now
                recomputeDays(&state)
                return loadEvents(&state)

            case let .dateTapped(date):
                // Toggle selection: tap again to deselect
                if let current = state.selectedDate,
                   state.calendar.isDate(current, inSameDayAs: date) {
                    state.selectedDate = nil
                } else {
                    state.selectedDate = date
                }
                return loadEvents(&state)

            case .togglePin:
                state.isPinned.toggle()
                return .none

            case .togglePreferences:
                state.showingPreferences.toggle()
                return .none

            case .closePanel:
                state.isPinned = false
                state.isLoadingEvents = false
                state.eventsRequestID = nil
                return .cancel(id: CancelID.events)

            case .requestCalendarAccess:
                guard !state.isRequestingCalendarAccess else { return .none }
                let status = eventKitClient.authorizationStatus()
                guard status == .notDetermined else {
                    return loadEvents(&state, authorizationStatus: status)
                }
                state.calendarAuthorizationStatus = status
                state.isRequestingCalendarAccess = true
                state.calendarAccessError = nil
                return .run { send in
                    do {
                        _ = try await eventKitClient.requestAccess()
                        try Task.checkCancellation()
                        await send(.calendarAccessResult(eventKitClient.authorizationStatus()))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        AppLogger.calendar.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
                        await send(.calendarAccessFailed(error.localizedDescription, eventKitClient.authorizationStatus()))
                    }
                }
                .cancellable(id: CancelID.calendarAccess)

            case let .calendarAccessResult(status):
                state.isRequestingCalendarAccess = false
                state.calendarAccessError = nil
                return loadEvents(&state, authorizationStatus: status)

            case let .calendarAccessFailed(message, status):
                state.isRequestingCalendarAccess = false
                let effect = loadEvents(&state, authorizationStatus: status)
                state.calendarAccessError = message
                return effect

            case .refreshCalendarAuthorization:
                return loadEvents(&state)

            case .retryEvents:
                return loadEvents(&state)

            case let .eventsLoaded(requestedDate, requestID, events):
                guard state.eventsRequestID == requestID,
                      state.eventsDate == requestedDate else { return .none }
                let status = eventKitClient.authorizationStatus()
                guard status == .fullAccess else {
                    return loadEvents(&state, authorizationStatus: status)
                }
                state.isLoadingEvents = false
                state.eventsRequestID = nil
                state.events = events
                state.eventsError = nil
                return .none

            case let .eventsFailed(requestedDate, requestID, message):
                guard state.eventsRequestID == requestID,
                      state.eventsDate == requestedDate else { return .none }
                let status = eventKitClient.authorizationStatus()
                guard status == .fullAccess else {
                    return loadEvents(&state, authorizationStatus: status)
                }
                state.isLoadingEvents = false
                state.eventsRequestID = nil
                state.eventsError = message
                return .none

            case .reloadPreferences:
                state.startOfWeekday = preferencesClient.loadStartOfWeekday()
                state.workdays = preferencesClient.loadWorkdays()
                state.showAISearch = preferencesClient.loadShowAISearch()
                recomputeDays(&state)
                return .none

            case let .aiDateResult(date):
                if let date {
                    state.displayedMonth = date
                    state.selectedDate = date
                    recomputeDays(&state)
                    return loadEvents(&state)
                }
                return .none

            case .onDisappear:
                state.showingPreferences = false
                state.displayedMonth = date.now
                recomputeDays(&state)
                state.isLoadingEvents = false
                state.eventsRequestID = nil
                return .cancel(id: CancelID.events)

            case .hiddenPreservingContext:
                state.showingPreferences = false
                state.isLoadingEvents = false
                state.eventsRequestID = nil
                return .cancel(id: CancelID.events)

            case .prepareForReopen:
                // The NSPanel is reused via orderOut/orderFront, so SwiftUI
                // onAppear/onDisappear do not fire (see gotchas.md). This action
                // is invoked from the show path to reset the reused store: return
                // to the current month with today selected, and pick up any
                // preference changes made while the panel was hidden.
                state.showingPreferences = false
                state.displayedMonth = date.now
                state.selectedDate = date.now
                state.startOfWeekday = preferencesClient.loadStartOfWeekday()
                state.workdays = preferencesClient.loadWorkdays()
                state.showAISearch = preferencesClient.loadShowAISearch()
                recomputeDays(&state)
                return loadEvents(&state)
            }
        }
    }

    private func recomputeDays(_ state: inout State) {
        state.days = calendarClient.calendarDays(state.displayedMonth, state.calendar)
        state.gridInfo = calendarClient.gridInfo(state.days)
    }

    private func loadEvents(
        _ state: inout State,
        authorizationStatus: EKAuthorizationStatus? = nil
    ) -> Effect<Action> {
        let status = authorizationStatus ?? eventKitClient.authorizationStatus()
        if status != state.calendarAuthorizationStatus {
            state.calendarAccessError = nil
        }
        state.calendarAuthorizationStatus = status
        state.events = []
        state.eventsError = nil
        guard status == .fullAccess else {
            state.eventsDate = nil
            state.eventsRequestID = nil
            state.isLoadingEvents = false
            return .cancel(id: CancelID.events)
        }

        let requestedDate = state.calendar.startOfDay(for: state.selectedDate ?? date.now)
        let requestID = uuid()
        state.eventsDate = requestedDate
        state.eventsRequestID = requestID
        state.isLoadingEvents = true
        return .run { send in
            do {
                let events = try await eventKitClient.fetchEvents(requestedDate)
                try Task.checkCancellation()
                await send(.eventsLoaded(date: requestedDate, requestID: requestID, events: events))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.calendar.error("Calendar event query failed: \(error.localizedDescription, privacy: .public)")
                await send(.eventsFailed(date: requestedDate, requestID: requestID, message: error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.events, cancelInFlight: true)
    }
}
