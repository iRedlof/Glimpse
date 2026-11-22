import Foundation

/// "Leave by 8:40": start − a user-chosen buffer, for timed events with a physical place.
/// Pure and local: no maps, no traffic, no network. Hearth uses the same 20-minute default.
public enum LeaveBy {
    public static let bufferChoices = [10, 15, 20, 30, 45, 60]
    public static let defaultBufferMinutes = 20
    /// A located event spanning this many calendar days or more is a trip ("Away 5 days").
    public static let minimumTripDays = 2
    static let secondsPerMinute: TimeInterval = 60
    static let maximumSingleEventDuration: TimeInterval = 24 * 60 * 60

    /// `minutes` when it is one of `bufferChoices`, else the default.
    public static func validatedBuffer(_ minutes: Int) -> Int {
        bufferChoices.contains(minutes) ? minutes : defaultBufferMinutes
    }

    /// Start − buffer for a timed, not-declined event with a place shorter than a day.
    /// Nil when leave-by is off (`bufferMinutes` nil) or the event doesn't qualify.
    public static func leaveTime(for event: CalendarEvent, bufferMinutes: Int?) -> Date? {
        guard let bufferMinutes, event.location != nil, !event.isAllDay, !event.isDeclined,
              event.endDate > event.startDate,
              event.endDate.timeIntervalSince(event.startDate) < maximumSingleEventDuration
        else { return nil }
        return event.startDate.addingTimeInterval(-TimeInterval(validatedBuffer(bufferMinutes)) * secondsPerMinute)
    }

    /// Calendar days a located event covers when that is `minimumTripDays` or more.
    /// All-day ends are exclusive midnights, so the last instant before the end counts.
    public static func tripDays(for event: CalendarEvent, calendar: Calendar) -> Int? {
        guard event.location != nil, !event.isDeclined, event.endDate > event.startDate else { return nil }
        let first = calendar.startOfDay(for: event.startDate)
        let last = calendar.startOfDay(for: event.endDate.addingTimeInterval(-1))
        guard let span = calendar.dateComponents([.day], from: first, to: last).day else { return nil }
        let days = span + 1
        return days >= minimumTripDays ? days : nil
    }

    /// Compact clock time without the day period ("8:40", "20:05"): leave-by is always
    /// within the next hour or so, and the menu bar item stays short.
    public static func clockText(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted)
            .hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return date.formatted(style)
    }

    /// Full clock time for VoiceOver ("8:40 AM").
    public static func spokenClockText(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return date.formatted(style)
    }
}

/// The trailing chip on an agenda row.
public enum AgendaBadge: Equatable, Sendable {
    /// "Leave by 8:40": a located event that hasn't started, with leave-by on.
    case leaveBy(Date)
    /// "Away 5 days": a located event covering two or more days.
    case away(days: Int)

    /// A trip wins over leave-by; leave-by shows until the event starts.
    public static func badge(
        for event: CalendarEvent, leaveByMinutes: Int?, now: Date, calendar: Calendar
    ) -> AgendaBadge? {
        if let days = LeaveBy.tripDays(for: event, calendar: calendar) { return .away(days: days) }
        guard event.startDate > now,
              let leaveAt = LeaveBy.leaveTime(for: event, bufferMinutes: leaveByMinutes)
        else { return nil }
        return .leaveBy(leaveAt)
    }

    public func text(calendar: Calendar, locale: Locale) -> String {
        switch self {
        case let .leaveBy(date): "Leave by \(LeaveBy.clockText(date, calendar: calendar, locale: locale))"
        case let .away(days): "Away \(days) days"
        }
    }

    public func accessibilityText(calendar: Calendar, locale: Locale) -> String {
        switch self {
        case let .leaveBy(date): "Leave by \(LeaveBy.spokenClockText(date, calendar: calendar, locale: locale))"
        case let .away(days): "Away \(days) days"
        }
    }
}
