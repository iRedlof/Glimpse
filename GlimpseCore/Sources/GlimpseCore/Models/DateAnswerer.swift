import Foundation

public struct DateAnswer: Equatable, Sendable {
    public let text: String
    /// States the counting convention so the number is honest.
    public let detail: String?

    public init(text: String, detail: String?) {
        self.text = text
        self.detail = detail
    }

    public var accessibilityLabel: String {
        guard let detail else { return "Answer: \(text)" }
        let spoken = detail
            .replacingOccurrences(of: " → ", with: " to ")
            .replacingOccurrences(of: " · ", with: ", ")
        return "Answer: \(text). \(spoken)"
    }
}

/// Answers date questions locally. The AI only says *what* to count; the
/// counting is deterministic so the number can be trusted.
public enum DateAnswerer {
    /// Weekday numbers (1 = Sunday) in Monday-first display order.
    static let displayOrder = [2, 3, 4, 5, 6, 7, 1]
    static let minimumRunForRange = 3

    public static func answer(
        _ question: DateQuestion, today: CivilDate, calendar: Calendar, workdays: Set<Int>
    ) -> DateAnswer {
        switch question {
        case let .count(kind, from, to):
            return count(kind, from: from, to: to, today: today, calendar: calendar, workdays: workdays)
        case let .weekNumber(day):
            let week = day.date(in: calendar).map { calendar.component(.weekOfYear, from: $0) }
            guard let week else { return unavailable }
            return DateAnswer(text: "Week \(week)",
                              detail: format(day, today: today, calendar: calendar, weekday: true))
        case let .weekday(day):
            let symbols = calendar.weekdaySymbols
            guard symbols.indices.contains(day.weekday - 1) else { return unavailable }
            return DateAnswer(text: symbols[day.weekday - 1],
                              detail: format(day, today: today, calendar: calendar, weekday: false))
        }
    }

    static let unavailable = DateAnswer(text: "Couldn't work that out", detail: nil)

    private static func count(
        _ kind: DayKind, from: CivilDate, to: CivilDate, today: CivilDate,
        calendar: Calendar, workdays: Set<Int>
    ) -> DateAnswer {
        let span = "\(format(from, today: today, calendar: calendar, weekday: false)) → "
            + format(to, today: today, calendar: calendar, weekday: false)
        let locale = calendar.locale ?? .current
        switch kind {
        case .days:
            let total = max(0, CivilDate.daysBetween(from, to))
            return DateAnswer(text: phrase(total, "day", locale: locale), detail: span)
        case .workdays:
            let total = countDays(in: workdays, from: from, to: to)
            let detail = "\(span) · \(describe(workdays, calendar: calendar)) · holidays not counted"
            return DateAnswer(text: phrase(total, "workday", locale: locale), detail: detail)
        case .weekendDays:
            let weekend = Set(1...7).subtracting(workdays)
            let total = countDays(in: weekend, from: from, to: to)
            return DateAnswer(text: phrase(total, "weekend day", locale: locale),
                              detail: "\(span) · \(describe(weekend, calendar: calendar))")
        }
    }

    /// Days in [from, to) whose weekday is in `weekdays`, computed per whole
    /// week so century-long ranges cost the same as short ones.
    static func countDays(in weekdays: Set<Int>, from: CivilDate, to: CivilDate) -> Int {
        let total = CivilDate.daysBetween(from, to)
        guard total > 0 else { return 0 }
        let fullWeeks = total / 7
        var count = fullWeeks * weekdays.intersection(1...7).count
        let startWeekday = from.weekday
        for offset in 0..<(total % 7) {
            let weekday = (startWeekday - 1 + fullWeeks * 7 + offset) % 7 + 1
            if weekdays.contains(weekday) { count += 1 }
        }
        return count
    }

    private static func phrase(_ count: Int, _ noun: String, locale: Locale) -> String {
        "\(count.formatted(.number.locale(locale))) \(noun)\(count == 1 ? "" : "s")"
    }

    /// "Mon–Fri" for a contiguous run, otherwise "Mon, Wed, Fri".
    static func describe(_ weekdays: Set<Int>, calendar: Calendar) -> String {
        let ordered = displayOrder.filter(weekdays.contains)
        let symbols = calendar.shortWeekdaySymbols
        let names = ordered.compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
        guard let first = names.first, let last = names.last else { return "no days" }
        let positions = ordered.compactMap { displayOrder.firstIndex(of: $0) }
        let contiguous = zip(positions, positions.dropFirst()).allSatisfy { $1 == $0 + 1 }
        if contiguous, names.count >= minimumRunForRange { return "\(first)–\(last)" }
        return names.joined(separator: ", ")
    }

    private static func format(_ day: CivilDate, today: CivilDate, calendar: Calendar, weekday: Bool) -> String {
        guard let date = day.date(in: calendar) else { return day.iso }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: calendar.locale ?? .current,
                                     calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day()
        if weekday { style = style.weekday(.abbreviated) }
        if day.year != today.year { style = style.year() }
        return date.formatted(style)
    }
}
