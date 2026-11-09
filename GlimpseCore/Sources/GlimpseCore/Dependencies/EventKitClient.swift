import ComposableArchitecture
import EventKit
import Foundation

@DependencyClient
public struct EventKitClient: Sendable {
    public var requestAccess: @Sendable () async throws -> Bool = { false }
    public var fetchEvents: @Sendable (Date) async throws -> [CalendarEvent] = { _ in [] }
    public var authorizationStatus: @Sendable () -> EKAuthorizationStatus = { .notDetermined }
    /// Events overlapping `interval`, for free-time search. Throws `ScheduleError`.
    public var fetchEventsInInterval: @Sendable (DateInterval) async throws -> [CalendarEvent] = { _ in [] }
    /// The calendar new events go to, or nil when none accepts new events.
    public var defaultWritableCalendar: @Sendable () async throws -> WritableCalendar? = { nil }
    /// Re-checks the time is still free, then saves and commits. Throws `ScheduleError`.
    public var saveEvent: @Sendable (NewEvent) async throws -> SavedEvent
    /// Removes a just-saved event (Undo). Throws `ScheduleError`.
    public var removeEvent: @Sendable (SavedEvent) async throws -> Void

    enum QueryError: LocalizedError, Sendable {
        case accessUnavailable
        case invalidDate

        var errorDescription: String? {
            switch self {
            case .accessUnavailable: "Calendar access is unavailable."
            case .invalidDate: "The selected calendar day is unavailable."
            }
        }
    }

    static func eventsInterval(for date: Date, calendar: Calendar = .current) throws -> DateInterval {
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            throw QueryError.invalidDate
        }
        return interval
    }

    static func calendarEvent(from event: EKEvent) -> CalendarEvent? {
        guard let startDate = event.startDate, let endDate = event.endDate else {
            AppLogger.calendar.error("Skipping calendar event with missing dates")
            return nil
        }
        // Event identifiers can be nil. The item identifier plus occurrence date
        // remains stable across repeated queries, including recurring instances.
        let identifier = event.eventIdentifier
            ?? "\(event.calendarItemIdentifier)-\(startDate.timeIntervalSinceReferenceDate)"
        return CalendarEvent(
            id: identifier,
            title: event.title ?? "Untitled",
            startDate: startDate,
            endDate: endDate,
            isAllDay: event.isAllDay,
            blocksTime: blocksTime(isAllDay: event.isAllDay, availability: event.availability)
        )
    }

    /// Only timed events not marked "free" make a time busy.
    static func blocksTime(isAllDay: Bool, availability: EKEventAvailability) -> Bool {
        !isAllDay && availability != .free
    }

    /// A Sendable snapshot of an `EKCalendar`, so selection logic is pure.
    struct CalendarCandidate: Equatable, Sendable {
        let id: String
        let title: String
        let allowsModifications: Bool

        init(id: String, title: String, allowsModifications: Bool) {
            self.id = id
            self.title = title
            self.allowsModifications = allowsModifications
        }

        init(_ calendar: EKCalendar) {
            self.init(id: calendar.calendarIdentifier, title: calendar.title,
                      allowsModifications: calendar.allowsContentModifications)
        }
    }

    /// The default calendar when it accepts new events, otherwise the first one that does.
    static func preferredWritableCalendar(default preferred: CalendarCandidate?,
                                          all: [CalendarCandidate]) -> WritableCalendar? {
        let chosen = [preferred].compactMap { $0 }.first(where: \.allowsModifications)
            ?? all.first(where: \.allowsModifications)
        return chosen.map { WritableCalendar(id: $0.id, title: $0.title) }
    }

    static func savedEvent(identifier: String?, itemIdentifier: String? = nil, new: NewEvent,
                           calendarTitle: String) -> SavedEvent? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let itemID = itemIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        return SavedEvent(eventID: identifier, itemID: itemID, title: new.title, start: new.start,
                          end: new.end, calendarTitle: calendarTitle)
    }

    /// How Undo found the event it removes.
    enum UndoLookup: Equatable, Sendable {
        /// The object kept from the save, still in the store.
        case retained
        case eventIdentifier
        /// The identifier changed after a sync; found by `calendarItemIdentifier`.
        case itemIdentifier
    }

    /// Finds the saved event for Undo: the retained object first, then the
    /// event identifier, then the item identifier. Generic so the order is
    /// testable without a live event store.
    static func undoTarget<Event>(
        for saved: SavedEvent, retained: Event?,
        byEventIdentifier: (String) -> Event?, byItemIdentifier: (String) -> Event?
    ) -> (event: Event, lookup: UndoLookup)? {
        if let retained { return (retained, .retained) }
        if let event = byEventIdentifier(saved.eventID) { return (event, .eventIdentifier) }
        if let itemID = saved.itemID, let event = byItemIdentifier(itemID) { return (event, .itemIdentifier) }
        return nil
    }
}

extension EventKitClient {
    /// A read-only client (fixtures and previews). Any scheduling call is a
    /// programming error: it reports an issue and fails without writing.
    public init(
        requestAccess: @escaping @Sendable () async throws -> Bool,
        fetchEvents: @escaping @Sendable (Date) async throws -> [CalendarEvent],
        authorizationStatus: @escaping @Sendable () -> EKAuthorizationStatus
    ) {
        self.init(
            requestAccess: requestAccess,
            fetchEvents: fetchEvents,
            authorizationStatus: authorizationStatus,
            fetchEventsInInterval: { _ in
                reportIssue("Read-only EventKitClient cannot search free time")
                throw ScheduleError.accessUnavailable
            },
            defaultWritableCalendar: {
                reportIssue("Read-only EventKitClient has no writable calendar")
                throw ScheduleError.accessUnavailable
            },
            saveEvent: { _ in
                reportIssue("Read-only EventKitClient cannot save events")
                throw ScheduleError.accessUnavailable
            },
            removeEvent: { _ in
                reportIssue("Read-only EventKitClient cannot remove events")
                throw ScheduleError.accessUnavailable
            }
        )
    }
}

extension EventKitClient: DependencyKey {
    private static let eventStore = EventStore()

    public static var liveValue: Self {
        Self(
            requestAccess: { try await eventStore.requestAccess() },
            fetchEvents: { try await eventStore.fetchEvents(for: $0) },
            authorizationStatus: {
                EKEventStore.authorizationStatus(for: .event)
            },
            fetchEventsInInterval: { try await eventStore.fetchEvents(in: $0) },
            defaultWritableCalendar: { try await eventStore.defaultWritableCalendar() },
            saveEvent: { try await eventStore.save($0) },
            removeEvent: { try await eventStore.remove($0) }
        )
    }

    public static let testValue = Self()
}

/// Own the event store and EventKit objects on one serial actor. Only Sendable
/// event models cross its boundary; synchronous queries run away from the UI.
actor EventStore {
    private let store = EKEventStore()
    /// The last saved event, kept so Undo does not depend on identifiers a
    /// sync may change inside the Undo window.
    private var lastSaved: (id: String, event: EKEvent)?
    private let authorizationStatus: @Sendable () -> EKAuthorizationStatus

    init(
        authorizationStatus: @escaping @Sendable () -> EKAuthorizationStatus = {
            EKEventStore.authorizationStatus(for: .event)
        }
    ) {
        self.authorizationStatus = authorizationStatus
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func fetchEvents(for date: Date) throws -> [CalendarEvent] {
        try Task.checkCancellation()
        guard authorizationStatus() == .fullAccess else {
            throw EventKitClient.QueryError.accessUnavailable
        }
        let interval = try EventKitClient.eventsInterval(for: date)
        let predicate = store.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: nil
        )
        let events = store.events(matching: predicate)
        try Task.checkCancellation()
        return events
            .compactMap(EventKitClient.calendarEvent(from:))
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Scheduling (full access only; writes are always explicit picks)

    private func requireFullAccess() throws {
        guard authorizationStatus() == .fullAccess else { throw ScheduleError.accessUnavailable }
    }

    func fetchEvents(in interval: DateInterval) throws -> [CalendarEvent] {
        try requireFullAccess()
        try Task.checkCancellation()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate)
            .compactMap(EventKitClient.calendarEvent(from:))
            .sorted { $0.startDate < $1.startDate }
    }

    func defaultWritableCalendar() throws -> WritableCalendar? {
        try requireFullAccess()
        return EventKitClient.preferredWritableCalendar(
            default: store.defaultCalendarForNewEvents.map(EventKitClient.CalendarCandidate.init),
            all: store.calendars(for: .event).map(EventKitClient.CalendarCandidate.init)
        )
    }

    func save(_ new: NewEvent) throws -> SavedEvent {
        try requireFullAccess()
        guard let calendar = store.calendar(withIdentifier: new.calendarID) else {
            AppLogger.calendar.error("Event save failed: calendar missing")
            throw ScheduleError.noWritableCalendar
        }
        guard calendar.allowsContentModifications else {
            AppLogger.calendar.error("Event save failed: calendar read-only")
            throw ScheduleError.calendarReadOnly
        }
        let slot = FreeSlot(start: new.start, end: new.end)
        let current = try fetchEvents(in: DateInterval(start: new.start, end: new.end))
        guard FreeSlotFinder.isFree(slot, busy: FreeSlotFinder.busyIntervals(from: current)) else {
            AppLogger.calendar.info("Event save skipped: slot no longer free")
            throw ScheduleError.slotTaken
        }
        let event = EKEvent(eventStore: store)
        event.title = new.title
        event.startDate = new.start
        event.endDate = new.end
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            AppLogger.calendar.error("Event save failed: \(error.localizedDescription, privacy: .public)")
            throw ScheduleError.saveFailed
        }
        guard let saved = EventKitClient.savedEvent(identifier: event.eventIdentifier,
                                                    itemIdentifier: event.calendarItemIdentifier,
                                                    new: new, calendarTitle: calendar.title) else {
            // Without an identifier Undo is impossible, so roll back to keep "Nothing was saved" true.
            AppLogger.calendar.error("Event save returned no identifier; rolling back")
            do { try store.remove(event, span: .thisEvent, commit: true) } catch {
                AppLogger.calendar.error("Rollback failed: \(error.localizedDescription, privacy: .public)")
            }
            throw ScheduleError.saveFailed
        }
        lastSaved = (saved.eventID, event)
        AppLogger.calendar.info("Event saved: \(new.title, privacy: .private)")
        return saved
    }

    func remove(_ saved: SavedEvent) throws {
        try requireFullAccess()
        // refresh() is false once the event is gone from the store.
        let retained = lastSaved.flatMap { $0.id == saved.eventID && $0.event.refresh() ? $0.event : nil }
        guard let target = EventKitClient.undoTarget(
            for: saved, retained: retained,
            byEventIdentifier: { store.event(withIdentifier: $0) },
            byItemIdentifier: { store.calendarItem(withIdentifier: $0) as? EKEvent }
        ) else {
            AppLogger.calendar.info("Event undo: no event for the saved identifiers; already gone")
            throw ScheduleError.eventMissing
        }
        if target.lookup == .itemIdentifier {
            AppLogger.calendar.info("Event undo: event identifier changed after sync; found by item identifier")
        } else if target.lookup == .eventIdentifier, lastSaved?.id == saved.eventID {
            AppLogger.calendar.info("Event undo: kept event was stale; found by event identifier")
        }
        do {
            try store.remove(target.event, span: .thisEvent, commit: true)
        } catch {
            AppLogger.calendar.error("Event undo failed: \(error.localizedDescription, privacy: .public)")
            throw ScheduleError.removeFailed
        }
        if lastSaved?.id == saved.eventID { lastSaved = nil }
        AppLogger.calendar.info("Event removed: \(saved.title, privacy: .private)")
    }
}

extension DependencyValues {
    public var eventKitClient: EventKitClient {
        get { self[EventKitClient.self] }
        set { self[EventKitClient.self] = newValue }
    }
}
