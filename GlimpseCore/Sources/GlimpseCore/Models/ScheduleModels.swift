import Foundation

/// The calendar a new event will be written to.
public struct WritableCalendar: Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// An event the user explicitly picked, not yet saved.
public struct NewEvent: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarID: String

    public init(title: String, start: Date, end: Date, calendarID: String) {
        self.title = title
        self.start = start
        self.end = end
        self.calendarID = calendarID
    }
}

/// An event EventKit confirmed it saved; enough to undo it.
public struct SavedEvent: Equatable, Sendable {
    public let eventID: String
    /// `calendarItemIdentifier`, the fallback when a sync changes `eventID`
    /// (iCloud and Exchange can reassign it after the first sync).
    public let itemID: String?
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarTitle: String

    public init(eventID: String, itemID: String? = nil, title: String, start: Date, end: Date,
                calendarTitle: String) {
        self.eventID = eventID
        self.itemID = itemID
        self.title = title
        self.start = start
        self.end = end
        self.calendarTitle = calendarTitle
    }
}

public enum ScheduleError: Error, Equatable, Sendable {
    case accessUnavailable
    case noWritableCalendar
    case calendarReadOnly
    case slotTaken
    case saveFailed
    case eventMissing
    case removeFailed
    case searchFailed

    /// User-facing, never includes payloads.
    public var message: String {
        switch self {
        case .accessUnavailable: "Glimpse can't use your calendar. Nothing was saved."
        case .noWritableCalendar: "No calendar accepts new events. Set a default calendar in Calendar settings."
        case .calendarReadOnly: "That calendar is read-only. Nothing was saved."
        case .slotTaken: "That time just filled up. Pick another."
        case .saveFailed: "Couldn't add the event. Nothing was saved."
        case .eventMissing: "The event was already removed."
        case .removeFailed: "Couldn't undo. The event is still in your calendar."
        case .searchFailed: "Couldn't check your calendar for free times."
        }
    }

    /// Keeps known schedule errors and maps everything else to `fallback`.
    public static func from(_ error: any Error, fallback: ScheduleError) -> ScheduleError {
        if let error = error as? ScheduleError { return error }
        if case .accessUnavailable? = error as? EventKitClient.QueryError { return .accessUnavailable }
        return fallback
    }
}
