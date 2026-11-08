import Foundation

public struct FreeSlot: Equatable, Hashable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// Finds free times locally from busy intervals. Pure: the caller supplies
/// "now" and the calendar, so every edge case is unit-testable.
public enum FreeSlotFinder {
    public static let step: TimeInterval = 15 * 60
    public static let maximumSlots = 3

    // MARK: - Windows

    /// The search window for a draft on its day, or nil when the day or
    /// times cannot be resolved. Windows never extend past the day.
    public static func window(for draft: EventDraft, calendar: Calendar) -> DateInterval? {
        guard let dayStart = draft.day.date(in: calendar),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let bounds: (Date?, Date?)
        switch draft.window {
        case let .exact(time):
            guard let start = moment(time.minutesSinceMidnight, on: dayStart, calendar) else { return nil }
            bounds = (max(dayStart, start.addingTimeInterval(-TimeWindow.exactSearchRadius)),
                      min(dayEnd, start.addingTimeInterval(TimeWindow.exactSearchRadius + draft.duration)))
        case let .between(from, to):
            bounds = (moment(from.minutesSinceMidnight, on: dayStart, calendar),
                      moment(to.minutesSinceMidnight, on: dayStart, calendar))
        case let .partOfDay(part):
            bounds = hourBounds(part.hours, on: dayStart, dayEnd: dayEnd, calendar)
        case .unspecified:
            bounds = hourBounds(TimeWindow.workingHours, on: dayStart, dayEnd: dayEnd, calendar)
        }
        guard let start = bounds.0, let end = bounds.1, end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The draft's exact start time, when it named one.
    public static func preferredStart(for draft: EventDraft, calendar: Calendar) -> Date? {
        guard case let .exact(time) = draft.window, let dayStart = draft.day.date(in: calendar) else { return nil }
        return moment(time.minutesSinceMidnight, on: dayStart, calendar)
    }

    private static func moment(_ minutes: Int, on dayStart: Date, _ calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dayStart)
    }

    private static func hourBounds(_ hours: Range<Int>, on dayStart: Date, dayEnd: Date,
                                   _ calendar: Calendar) -> (Date?, Date?) {
        let end = hours.upperBound >= 24 ? dayEnd : moment(hours.upperBound * 60, on: dayStart, calendar)
        return (moment(hours.lowerBound * 60, on: dayStart, calendar), end)
    }

    // MARK: - Busy time

    /// Busy intervals from events that block time; malformed ranges are skipped.
    public static func busyIntervals(from events: [CalendarEvent]) -> [DateInterval] {
        events
            .filter { $0.blocksTime && !$0.isAllDay && $0.endDate > $0.startDate }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
    }

    public static func isFree(_ slot: FreeSlot, busy: [DateInterval]) -> Bool {
        !busy.contains { $0.start < slot.end && $0.end > slot.start }
    }

    // MARK: - Slots

    public static func slots(for draft: EventDraft, events: [CalendarEvent], now: Date,
                             calendar: Calendar) -> [FreeSlot] {
        guard let window = window(for: draft, calendar: calendar) else { return [] }
        return slots(busy: busyIntervals(from: events), window: window, duration: draft.duration,
                     notBefore: now, preferredStart: preferredStart(for: draft, calendar: calendar))
    }

    /// Up to three free slots of `duration` inside `window`, starting no
    /// earlier than `notBefore`. With a `preferredStart` the slots are the
    /// nearest non-overlapping times to it, nearest first; otherwise the
    /// earliest time in each gap comes first, then back-to-back fill-ins,
    /// in chronological order.
    public static func slots(busy: [DateInterval], window: DateInterval, duration: TimeInterval,
                             notBefore: Date, preferredStart: Date? = nil) -> [FreeSlot] {
        guard duration > 0 else { return [] }
        let start = max(window.start, notBefore)
        guard start < window.end else { return [] }
        let merged = merge(busy, clippedTo: DateInterval(start: start, end: window.end))
        if let preferredStart {
            return nearest(to: preferredStart, from: start, to: window.end, busy: merged, duration: duration)
        }
        let gaps = gaps(from: start, to: window.end, busy: merged)
        var firsts: [FreeSlot] = []
        var fillIns: [FreeSlot] = []
        for gap in gaps {
            var candidate = roundUp(gap.start)
            var isFirst = true
            while candidate.addingTimeInterval(duration) <= gap.end {
                let slot = FreeSlot(start: candidate, end: candidate.addingTimeInterval(duration))
                if isFirst { firsts.append(slot) } else { fillIns.append(slot) }
                isFirst = false
                candidate = roundUp(slot.end)
            }
        }
        return Array((firsts + fillIns).prefix(maximumSlots)).sorted { $0.start < $1.start }
    }

    private static func nearest(to target: Date, from start: Date, to end: Date,
                                busy: [DateInterval], duration: TimeInterval) -> [FreeSlot] {
        var candidates: [Date] = []
        var cursor = roundUp(start)
        while cursor.addingTimeInterval(duration) <= end {
            candidates.append(cursor)
            cursor = cursor.addingTimeInterval(step)
        }
        if target >= start, target.addingTimeInterval(duration) <= end, !candidates.contains(target) {
            candidates.append(target)
        }
        let ranked = candidates
            .map { FreeSlot(start: $0, end: $0.addingTimeInterval(duration)) }
            .filter { isFree($0, busy: busy) }
            .sorted {
                let lhs = abs($0.start.timeIntervalSince(target))
                let rhs = abs($1.start.timeIntervalSince(target))
                return lhs == rhs ? $0.start < $1.start : lhs < rhs
            }
        var picked: [FreeSlot] = []
        for slot in ranked where picked.count < maximumSlots {
            if picked.allSatisfy({ $0.end <= slot.start || $0.start >= slot.end }) {
                picked.append(slot)
            }
        }
        return picked
    }

    static func merge(_ busy: [DateInterval], clippedTo window: DateInterval) -> [DateInterval] {
        let clipped = busy.compactMap { interval -> DateInterval? in
            let start = max(interval.start, window.start)
            let end = min(interval.end, window.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in clipped {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func gaps(from start: Date, to end: Date, busy: [DateInterval]) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var cursor = start
        for interval in busy {
            if interval.start > cursor { gaps.append(DateInterval(start: cursor, end: interval.start)) }
            cursor = max(cursor, interval.end)
        }
        if end > cursor { gaps.append(DateInterval(start: cursor, end: end)) }
        return gaps
    }

    /// Rounds up to the next quarter hour. Absolute alignment equals local
    /// alignment because every time zone offset is a multiple of 15 minutes.
    static func roundUp(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / step).rounded(.up) * step)
    }
}
