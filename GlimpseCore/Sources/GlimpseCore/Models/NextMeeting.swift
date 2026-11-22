import Foundation

/// Today's next (or current) meeting, as shown in the menu bar.
public struct NextMeeting: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Starts in `minutesUntil` whole minutes (rounded up, so never 0).
        case upcoming(minutesUntil: Int)
        /// Started and not yet ended.
        case inProgress
        /// Has a place and leave-by is on: leave at `at`, `minutesUntil` whole minutes
        /// from now (rounded up). Becomes `.upcoming` once `at` passes.
        case leaveBy(at: Date, minutesUntil: Int)
    }

    public let event: CalendarEvent
    public let phase: Phase

    public init(event: CalendarEvent, phase: Phase) {
        self.event = event
        self.phase = phase
    }

    /// Starts (or must be left for) within `NextMeetingSelector.imminentMinutes`:
    /// the menu bar turns amber.
    public var isImminent: Bool {
        switch phase {
        case let .upcoming(minutes), let .leaveBy(_, minutes):
            return minutes <= NextMeetingSelector.imminentMinutes
        case .inProgress:
            return false
        }
    }
}

/// Picks today's next meeting from a day's events. Pure: all time comes in as arguments.
///
/// Rules:
/// - Only timed, busy (not "free"), not-declined events count; all-day events and
///   timed events of a day or longer never do.
/// - "Today" is `calendar`'s day containing `now` (so DST and time-zone changes
///   follow the calendar); an event counts if it overlaps today and has not ended.
/// - With leave-by on (`leaveByMinutes`), the soonest upcoming meeting with a place reads
///   "leave by" until start − buffer, amber in the 5 minutes before; then the countdown.
/// - A meeting starting within the imminent window wins, even over one in progress,
///   because that is the one to switch to. Otherwise the meeting in progress that
///   started most recently, otherwise the soonest upcoming one.
/// - After the last meeting of the day: nil.
public enum NextMeetingSelector {
    public static let imminentMinutes = 5
    static let secondsPerMinute: TimeInterval = 60
    static let maximumMeetingDuration: TimeInterval = 24 * 60 * 60
    /// Minute-boundary ticks fire this much after the boundary so a slightly early
    /// wake-up can never round a countdown up to the previous minute.
    static let tickLeeway: TimeInterval = 0.25

    public static func candidates(
        _ events: [CalendarEvent], now: Date, calendar: Calendar
    ) -> [CalendarEvent] {
        guard let today = calendar.dateInterval(of: .day, for: now) else { return [] }
        return events.filter { event in
            event.blocksTime && !event.isAllDay && !event.isDeclined
                && event.endDate > event.startDate
                && event.endDate.timeIntervalSince(event.startDate) < maximumMeetingDuration
                && event.endDate > now
                && event.startDate < today.end && event.endDate > today.start
        }
    }

    public static func select(
        _ events: [CalendarEvent], now: Date, calendar: Calendar, leaveByMinutes: Int? = nil
    ) -> NextMeeting? {
        let eligible = candidates(events, now: now, calendar: calendar)
        let upcoming = eligible
            .filter { $0.startDate > now }
            .min { ($0.startDate, $0.endDate, $0.id) < ($1.startDate, $1.endDate, $1.id) }
        let current = eligible
            .filter { $0.startDate <= now }
            .min { ($1.startDate, $0.endDate, $0.id) < ($0.startDate, $1.endDate, $1.id) }

        let next = upcoming.map { event in
            if let leaveAt = LeaveBy.leaveTime(for: event, bufferMinutes: leaveByMinutes), leaveAt > now {
                return NextMeeting(event: event, phase: .leaveBy(
                    at: leaveAt, minutesUntil: minutesUntil(leaveAt, from: now)
                ))
            }
            return NextMeeting(event: event, phase: .upcoming(minutesUntil: minutesUntil(event.startDate, from: now)))
        }
        if let next, next.isImminent { return next }
        if let current { return NextMeeting(event: current, phase: .inProgress) }
        return next
    }

    /// Whole minutes until `start`, rounded up (start - now in (0, 60] s is 1 minute).
    static func minutesUntil(_ start: Date, from now: Date) -> Int {
        max(1, Int((start.timeIntervalSince(now) / secondsPerMinute).rounded(.up)))
    }

    /// Seconds from `now` until just after the next wall-clock minute boundary.
    public static func delayUntilNextMinute(after now: Date) -> TimeInterval {
        let seconds = now.timeIntervalSinceReferenceDate
        let next = (seconds / secondsPerMinute).rounded(.down) * secondsPerMinute + secondsPerMinute
        return next - seconds + tickLeeway
    }

    /// The next instant `select` can change its event or phase kind: an imminent
    /// window opening, a leave-by window or instant, a start, or an end. Nil when
    /// nothing is left today.
    public static func nextTransition(
        _ events: [CalendarEvent], now: Date, calendar: Calendar, leaveByMinutes: Int? = nil
    ) -> Date? {
        let imminentWindow = TimeInterval(imminentMinutes) * secondsPerMinute
        return candidates(events, now: now, calendar: calendar)
            .flatMap { event -> [Date] in
                let leave = LeaveBy.leaveTime(for: event, bufferMinutes: leaveByMinutes)
                    .map { [$0.addingTimeInterval(-imminentWindow), $0] } ?? []
                return leave + [event.startDate.addingTimeInterval(-imminentWindow), event.startDate, event.endDate]
            }
            .filter { $0 > now }
            .min()
    }
}

/// Menu bar wording for a `NextMeeting`.
public enum NextMeetingText {
    /// Titles longer than this are cut with an ellipsis so the item stays compact.
    public static let maximumTitleLength = 20
    static let fallbackTitle = "Meeting"

    /// "Standup in 12m", "Planning in 1h 5m", "Standup ends 10:30 AM",
    /// "Dentist · leave by 8:40".
    public static func menuBarText(
        for meeting: NextMeeting, calendar: Calendar, locale: Locale
    ) -> String {
        let title = truncatedTitle(meeting.event.title)
        switch meeting.phase {
        case let .upcoming(minutes):
            return "\(title) \(countdown(minutes: minutes))"
        case .inProgress:
            return "\(title) ends \(endTime(meeting.event.endDate, calendar: calendar, locale: locale))"
        case let .leaveBy(leaveAt, _):
            return "\(title) · leave by \(LeaveBy.clockText(leaveAt, calendar: calendar, locale: locale))"
        }
    }

    /// "in 12m", "in 1h", "in 1h 5m".
    public static func countdown(minutes: Int) -> String {
        let minutes = max(1, minutes)
        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, _): return "in \(remainder)m"
        case (_, 0): return "in \(hours)h"
        default: return "in \(hours)h \(remainder)m"
        }
    }

    /// Whitespace collapsed; longer than `maximumTitleLength` characters ends in "…".
    public static func truncatedTitle(_ title: String) -> String {
        let collapsed = title
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return fallbackTitle }
        guard collapsed.count > maximumTitleLength else { return collapsed }
        let cut = collapsed.prefix(maximumTitleLength - 1)
            .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return (cut.isEmpty ? String(collapsed.prefix(maximumTitleLength - 1)) : cut) + "…"
    }

    static func endTime(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return date.formatted(style)
    }
}
