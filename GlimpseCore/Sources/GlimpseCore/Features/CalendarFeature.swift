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
        /// Set when Calendar couldn't be opened for an agenda event; cleared on the next try.
        public var eventOpenError: String?
        /// The agenda's next/current meeting today when it has a meeting link: its row
        /// shows Join and ⌘J opens it. Nil for other days and link-less meetings.
        public var joinableEventID: String?
        public var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
        public var isRequestingCalendarAccess = false
        public var calendarAccessError: String?
        public var selectedDate: Date?
        public var showAISearch: Bool = true
        /// Free-time proposals and the Undo chip for AI "create" requests.
        public var schedule = ScheduleFeature.State()
        /// The AI range shown on the grid, e.g. "Next 3 Fridays".
        public var highlight: DateRangeHighlight?
        /// Start-of-day dates drawn highlighted; derived here so cells do O(1) lookups.
        public var highlightedDays: Set<Date> = []
        /// A locally computed answer to an AI date question.
        public var aiAnswer: DateAnswer?

        public var calendarAccessGranted: Bool { calendarAuthorizationStatus == .fullAccess }

        /// The agenda event Join (and ⌘J) opens, if any.
        public var joinableEvent: CalendarEvent? {
            guard let joinableEventID else { return nil }
            return events.first { $0.id == joinableEventID && $0.meetingLink != nil }
        }

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
        /// The app became active (⌘G, the AI editor, a return from System Settings).
        /// Reloads only when calendar authorization changed; EKEventStoreChanged
        /// already covers data changes.
        case applicationDidBecomeActive
        case retryEvents
        case eventsLoaded(date: Date, requestID: UUID, events: [CalendarEvent])
        case eventsFailed(date: Date, requestID: UUID, message: String)
        case aiIntent(AIIntent)
        /// The AI draft changed, was discarded, or the panel hid.
        case aiResultsCleared
        case schedule(ScheduleFeature.Action)
        case reloadPreferences
        /// An agenda event row was activated: reveal it in Apple's Calendar app.
        case openEventInCalendar(CalendarEvent)
        case openEventInCalendarFailed(String)
        /// Join was activated (button, Return on it, or ⌘J): open the meeting link.
        case joinMeeting(CalendarEvent)
        case joinMeetingFailed(String)
        /// A meeting started, ended or came within the imminent window: re-pick Join.
        case refreshJoinableMeeting
    }

    @Dependency(\.date) var date
    @Dependency(\.calendarClient) var calendarClient
    @Dependency(\.preferencesClient) var preferencesClient
    @Dependency(\.eventKitClient) var eventKitClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.scheduleEvents) var scheduleEvents
    @Dependency(\.calendarApp) var calendarApp
    @Dependency(\.meetingLinks) var meetingLinks
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case events, calendarAccess, joinableMeeting }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.schedule, action: \.schedule) {
            ScheduleFeature()
        }
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
                // A new day makes any proposal for the old day stale.
                clearAIResults(&state)
                let dismissal = dismissSchedule(&state)
                // Toggle selection: tap again to deselect
                if let current = state.selectedDate,
                   state.calendar.isDate(current, inSameDayAs: date) {
                    state.selectedDate = nil
                } else {
                    state.selectedDate = date
                }
                return .merge(loadEvents(&state), dismissal)

            case .togglePin:
                state.isPinned.toggle()
                return .none

            case let .openEventInCalendar(event):
                state.eventOpenError = nil
                let url = CalendarEventLink.url(for: event)
                return .run { [calendarApp] send in
                    do {
                        guard let url else { throw CalendarAppClient.OpenError.invalidURL }
                        try await calendarApp.open(url)
                    } catch {
                        AppLogger.calendar.error(
                            "Opening event in Calendar failed: \(error.localizedDescription, privacy: .public)"
                        )
                        await send(.openEventInCalendarFailed("Couldn’t open Calendar."))
                    }
                }

            case let .openEventInCalendarFailed(message):
                state.eventOpenError = message
                return .none

            case let .joinMeeting(event):
                // Only the current joinable event, with its already-validated link.
                guard event.id == state.joinableEventID, let link = event.meetingLink else { return .none }
                state.eventOpenError = nil
                return .run { [meetingLinks] send in
                    do {
                        try await meetingLinks.open(link)
                    } catch {
                        AppLogger.calendar.error(
                            "Joining meeting failed: \(error.localizedDescription, privacy: .public)"
                        )
                        await send(.joinMeetingFailed("Couldn’t open the meeting link."))
                    }
                }

            case let .joinMeetingFailed(message):
                state.eventOpenError = message
                return .none

            case .refreshJoinableMeeting:
                return refreshJoinableMeeting(&state)

            case .togglePreferences:
                state.showingPreferences.toggle()
                return .none

            case .closePanel:
                state.isPinned = false
                state.isLoadingEvents = false
                state.eventsRequestID = nil
                return .merge(.cancel(id: CancelID.events), .cancel(id: CancelID.joinableMeeting))

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

            case .applicationDidBecomeActive:
                let status = eventKitClient.authorizationStatus()
                guard status != state.calendarAuthorizationStatus else { return .none }
                return loadEvents(&state, authorizationStatus: status)

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
                if state.events != events { state.eventOpenError = nil }
                state.events = events
                state.eventsError = nil
                return refreshJoinableMeeting(&state)

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

            case let .aiIntent(intent):
                return handle(intent, &state)

            case .aiResultsCleared:
                clearAIResults(&state)
                return dismissSchedule(&state)

            case let .schedule(.delegate(.authorizationChanged(status))):
                return loadEvents(&state, authorizationStatus: status)

            case .schedule(.delegate(.eventsChanged)):
                return loadEvents(&state)

            case let .schedule(.delegate(.eventSaved(event))):
                return .merge(
                    loadEvents(&state),
                    .run { [scheduleEvents] _ in await scheduleEvents.eventSaved(event) }
                )

            case .schedule:
                return .none

            case .onDisappear:
                state.showingPreferences = false
                state.displayedMonth = date.now
                recomputeDays(&state)
                state.isLoadingEvents = false
                state.eventsRequestID = nil
                state.eventOpenError = nil
                clearAIResults(&state)
                return .merge(
                    .cancel(id: CancelID.events), .cancel(id: CancelID.joinableMeeting),
                    dismissSchedule(&state)
                )

            case .hiddenPreservingContext:
                state.showingPreferences = false
                state.isLoadingEvents = false
                state.eventsRequestID = nil
                return .merge(.cancel(id: CancelID.events), .cancel(id: CancelID.joinableMeeting))

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
                state.eventOpenError = nil
                recomputeDays(&state)
                clearAIResults(&state)
                return .merge(loadEvents(&state), dismissSchedule(&state))
            }
        }
    }

    // MARK: - Join

    /// Picks the agenda's joinable meeting (today only) and, while one of today's
    /// meetings has a link, wakes once at the next start/end/imminent instant to re-pick.
    private func refreshJoinableMeeting(_ state: inout State) -> Effect<Action> {
        // Link-less agendas never read the clock or schedule anything.
        guard state.events.contains(where: { $0.meetingLink != nil }), let eventsDate = state.eventsDate
        else {
            state.joinableEventID = nil
            return .cancel(id: CancelID.joinableMeeting)
        }
        let now = date.now
        let calendar = state.calendar
        guard calendar.isDate(eventsDate, inSameDayAs: now) else {
            state.joinableEventID = nil
            return .cancel(id: CancelID.joinableMeeting)
        }
        let meeting = NextMeetingSelector.select(state.events, now: now, calendar: calendar)
        state.joinableEventID = meeting?.event.meetingLink != nil ? meeting?.event.id : nil
        guard let transition = NextMeetingSelector.nextTransition(state.events, now: now, calendar: calendar)
        else { return .cancel(id: CancelID.joinableMeeting) }
        let delay = transition.timeIntervalSince(now) + NextMeetingSelector.tickLeeway
        return .run { [clock] send in
            try await clock.sleep(for: .milliseconds(Int((delay * 1000).rounded(.up))))
            await send(.refreshJoinableMeeting)
        }
        .cancellableLatestWins(id: CancelID.joinableMeeting)
    }

    // MARK: - AI intents

    private func handle(_ intent: AIIntent, _ state: inout State) -> Effect<Action> {
        clearAIResults(&state)
        switch intent {
        case let .navigate(day):
            return .merge(show(day, &state), dismissSchedule(&state))
        case let .range(highlight):
            let calendar = state.calendar
            state.highlight = highlight
            state.highlightedDays = Set(highlight.dates.compactMap { $0.date(in: calendar) })
            guard let first = highlight.dates.first else { return dismissSchedule(&state) }
            return .merge(show(first, &state), dismissSchedule(&state))
        case let .question(question):
            let calendar = state.calendar
            state.aiAnswer = DateAnswerer.answer(
                question, today: CivilDate(date.now, calendar: calendar), calendar: calendar,
                workdays: state.workdays
            )
            return dismissSchedule(&state)
        case let .create(draft):
            let navigation = show(draft.day, &state)
            if let day = draft.day.date(in: state.calendar) { state.highlightedDays = [day] }
            let calendar = state.calendar
            let proposal = ScheduleFeature().begin(draft, calendar: calendar, &state.schedule)
            return .merge(navigation, proposal.map(Action.schedule))
        case .clarify:
            // The query model shows the clarification; it never changes the
            // calendar, and results for the previous query no longer apply.
            return dismissSchedule(&state)
        }
    }

    private func show(_ day: CivilDate, _ state: inout State) -> Effect<Action> {
        guard let date = day.date(in: state.calendar) else {
            AppLogger.calendar.error("AI date could not be resolved in the current calendar")
            return .none
        }
        state.displayedMonth = date
        state.selectedDate = date
        recomputeDays(&state)
        return loadEvents(&state)
    }

    private func clearAIResults(_ state: inout State) {
        state.highlight = nil
        state.highlightedDays = []
        state.aiAnswer = nil
    }

    /// Uses the child's shared helper so resets need no extra action round-trip.
    private func dismissSchedule(_ state: inout State) -> Effect<Action> {
        ScheduleFeature().dismiss(&state.schedule).map(Action.schedule)
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
        let hadAccess = state.calendarAuthorizationStatus == .fullAccess
        state.calendarAuthorizationStatus = status
        guard status == .fullAccess else {
            state.events = []
            state.joinableEventID = nil
            state.eventsError = nil
            state.eventsDate = nil
            state.eventsRequestID = nil
            state.isLoadingEvents = false
            return .cancel(id: CancelID.events)
        }

        let requestedDate = state.calendar.startOfDay(for: state.selectedDate ?? date.now)
        // Stale-while-revalidate: re-fetching the day already shown (reopen, store
        // change, refresh) keeps its events and skips the loading state, so the agenda
        // doesn't flash or re-layout. A new day, lost access or a failed load resets.
        let isRevalidating = hadAccess && state.eventsDate == requestedDate && state.eventsError == nil
        if !isRevalidating {
            state.events = []
            state.joinableEventID = nil
            state.eventsError = nil
            state.isLoadingEvents = true
        }
        let requestID = uuid()
        state.eventsDate = requestedDate
        state.eventsRequestID = requestID
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
        .cancellableLatestWins(id: CancelID.events)
    }
}
