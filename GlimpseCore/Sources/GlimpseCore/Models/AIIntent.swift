import Foundation

/// What the user asked the ⌘G field for. Providers only ever produce this
/// structure; counting, free-time search and saving are deterministic Swift.
public enum AIIntent: Equatable, Sendable {
    case navigate(CivilDate)
    case range(DateRangeHighlight)
    case question(DateQuestion)
    case create(EventDraft)
    /// One short, sanitized, single-line question back to the user.
    case clarify(String)
}

public struct DateRangeHighlight: Equatable, Sendable {
    public static let maximumDates = 31
    public static let maximumLabelLength = 60
    public static let defaultLabel = "Highlighted dates"

    /// Sorted, deduplicated, 1…31 entries.
    public let dates: [CivilDate]
    public let label: String

    public init(dates: [CivilDate], label: String) {
        self.dates = Array(Set(dates).sorted().prefix(Self.maximumDates))
        self.label = label
    }
}

public enum DateQuestion: Equatable, Sendable {
    /// Days of `kind` in the half-open range [from, to).
    case count(DayKind, from: CivilDate, to: CivilDate)
    case weekNumber(CivilDate)
    case weekday(CivilDate)
}

public enum DayKind: String, Equatable, Sendable, Codable {
    case days, workdays, weekendDays
}

public struct EventDraft: Equatable, Sendable {
    public static let defaultDurationMinutes = 30
    public static let durationRange = 5...480
    public static let maximumTitleLength = 120

    public let title: String
    public let day: CivilDate
    public let window: TimeWindow
    public let durationMinutes: Int

    public init(title: String, day: CivilDate, window: TimeWindow, durationMinutes: Int) {
        self.title = title
        self.day = day
        self.window = window
        self.durationMinutes = durationMinutes
    }

    public var duration: TimeInterval { TimeInterval(durationMinutes * 60) }
}

public enum TimeWindow: Equatable, Sendable {
    case exact(ClockTime)
    case between(ClockTime, ClockTime)
    case partOfDay(PartOfDay)
    /// No time given: search working hours.
    case unspecified

    /// Hours searched when no time is given.
    public static let workingHours = 9..<17
    /// How far either side of an exact time alternatives are searched.
    public static let exactSearchRadius: TimeInterval = 2 * 60 * 60
}

public enum PartOfDay: String, Equatable, Sendable, Codable, CaseIterable {
    case morning, midday, afternoon, evening

    /// Search bounds in whole hours. The afternoon starts at 13:00 so a
    /// lunch hour that runs long still leaves early-afternoon options.
    public var hours: Range<Int> {
        switch self {
        case .morning: 9..<12
        case .midday: 12..<14
        case .afternoon: 13..<17
        case .evening: 17..<21
        }
    }
}
