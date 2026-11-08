import Foundation

/// A calendar day with no time or time zone. It is resolved against a
/// `Calendar` only at the edge, so AI replies and prompts never drift by a
/// day near midnight (ISO 8601 formatters default to UTC, see gotchas.md).
public struct CivilDate: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    static let validYears = 1...9999

    public init?(year: Int, month: Int, day: Int) {
        guard Self.validYears.contains(year), (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Strict `yyyy-MM-dd`; anything else (extra text, missing padding) is rejected.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The local day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        // Calendar always yields these components for a Gregorian date; the
        // fallbacks only guard non-Gregorian calendars and keep this total.
        self.year = parts.year ?? 2000
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    private init(unchecked year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Start of this day in `calendar`; nil when the calendar cannot represent it.
    public func date(in calendar: Calendar) -> Date? {
        guard let noon = calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        ) else { return nil }
        // Noon avoids DST gaps at midnight; startOfDay then finds the real start.
        let start = calendar.startOfDay(for: noon)
        return CivilDate(start, calendar: calendar) == self ? start : nil
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: - Pure day arithmetic (proleptic Gregorian, no time zones)

    /// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    public var dayNumber: Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let monthIndex = (month + 9) % 12
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public init?(dayNumber: Int) {
        let shifted = dayNumber + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.init(year: year, month: month, day: day)
    }

    /// Gregorian weekday, 1 = Sunday … 7 = Saturday (same numbering as `Calendar`).
    public var weekday: Int {
        // 1970-01-01 was a Thursday (5).
        let offset = (dayNumber + 4) % 7
        return (offset < 0 ? offset + 7 : offset) + 1
    }

    public func adding(days: Int) -> CivilDate? {
        CivilDate(dayNumber: dayNumber + days)
    }

    public static func daysBetween(_ start: CivilDate, _ end: CivilDate) -> Int {
        end.dayNumber - start.dayNumber
    }

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

/// A wall-clock time of day with minute precision.
public struct ClockTime: Hashable, Comparable, Sendable, Codable {
    public let hour: Int
    public let minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Strict 24-hour `H:mm` or `HH:mm`.
    public init?(hhmm: String) {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
