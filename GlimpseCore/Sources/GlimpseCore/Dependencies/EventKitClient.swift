import ComposableArchitecture
import EventKit
import Foundation

@DependencyClient
public struct EventKitClient: Sendable {
    public var requestAccess: @Sendable () async throws -> Bool = { false }
    public var fetchEvents: @Sendable (Date) async throws -> [CalendarEvent] = { _ in [] }
    public var authorizationStatus: @Sendable () -> EKAuthorizationStatus = { .notDetermined }

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
            isAllDay: event.isAllDay
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
            }
        )
    }

    public static let testValue = Self()
}

/// Own the event store and EventKit objects on one serial actor. Only Sendable
/// event models cross its boundary; synchronous queries run away from the UI.
private actor EventStore {
    private let store = EKEventStore()

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func fetchEvents(for date: Date) throws -> [CalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw EventKitClient.QueryError.accessUnavailable
        }
        let interval = try EventKitClient.eventsInterval(for: date)
        let predicate = store.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: nil
        )
        return store.events(matching: predicate)
            .compactMap(EventKitClient.calendarEvent(from:))
            .sorted { $0.startDate < $1.startDate }
    }
}

extension DependencyValues {
    public var eventKitClient: EventKitClient {
        get { self[EventKitClient.self] }
        set { self[EventKitClient.self] = newValue }
    }
}
