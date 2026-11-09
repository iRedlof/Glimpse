import Foundation

/// Reads the days a request names ("Thursday", "next Friday", "Mar 1",
/// "tomorrow", "in 10 days", "next 3 Fridays") straight from the user's
/// words. Weekday and year arithmetic is deterministic Swift, so a small
/// on-device model that miscounts weekdays cannot move the user to the
/// wrong day. Phrases it does not know are left to the model's dates.
public enum DayPhraseParser {
    /// Replies longer than this are not scanned (the query is capped earlier).
    static let maximumTextLength = 512

    /// Every day the text names, in the order written.
    public static func days(in text: String, today: CivilDate) -> [CivilDate] {
        let tokens = tokenize(text)
        var found: [CivilDate] = []
        var index = 0
        while index < tokens.count {
            if let match = day(at: index, in: tokens, today: today) {
                found.append(match.date)
                index = match.next
            } else {
                index += 1
            }
        }
        return found
    }

    /// "next 3 Fridays", "the next two Mondays", "every Monday in December".
    public static func weekdaySeries(in text: String, today: CivilDate) -> [CivilDate]? {
        let tokens = tokenize(text)
        for index in tokens.indices {
            if let series = countedSeries(at: index, in: tokens, today: today) { return series }
            if let series = monthSeries(at: index, in: tokens, today: today) { return series }
        }
        return nil
    }

    /// The count or lookup a question asks for, from its wording.
    public static func questionKind(in text: String) -> String? {
        let tokens = tokenize(text)
        let words = Set(tokens)
        let phrase = " " + tokens.joined(separator: " ") + " "
        let has: (String) -> Bool = { phrase.contains(" \($0) ") }
        if has("week number") || has("what week") || has("which week") { return "weekNumber" }
        if has("what day") || has("which day") || has("what weekday") || has("which weekday")
            || has("day of the week") { return "weekday" }
        if !words.isDisjoint(with: ["workday", "workdays", "weekdays", "business", "working"]) {
            return "countWorkdays"
        }
        if !words.isDisjoint(with: ["weekend", "weekends"]) { return "countWeekendDays" }
        if !words.isDisjoint(with: ["day", "days"]) { return "countDays" }
        return nil
    }

    /// The next `count` dates on `weekday` strictly after `today`.
    public static func upcoming(weekday: Int, count: Int, after today: CivilDate) -> [CivilDate] {
        guard (1...7).contains(weekday), count > 0 else { return [] }
        let first = forward(to: weekday, from: today, includingToday: false)
        return (0..<min(count, DateRangeHighlight.maximumDates)).compactMap { first?.adding(days: $0 * 7) }
    }

    // MARK: - Single days

    private struct Match {
        let date: CivilDate
        let next: Int
    }

    private static func day(at index: Int, in tokens: [String], today: CivilDate) -> Match? {
        let token = tokens[index]
        if let date = CivilDate(iso: token) { return Match(date: date, next: index + 1) }
        if let match = relativeWord(at: index, in: tokens, today: today) { return match }
        if let match = offset(at: index, in: tokens, today: today) { return match }
        if let match = holiday(at: index, in: tokens, today: today) { return match }
        if let match = monthDay(at: index, in: tokens, today: today) { return match }
        return namedWeekday(at: index, in: tokens, today: today)
    }

    private static func relativeWord(at index: Int, in tokens: [String], today: CivilDate) -> Match? {
        switch tokens[index] {
        case "today", "tonight": return Match(date: today, next: index + 1)
        case "yesterday": return today.adding(days: -1).map { Match(date: $0, next: index + 1) }
        case "tomorrow":
            let afterTomorrow = index >= 2 && tokens[index - 2] == "day" && tokens[index - 1] == "after"
            return today.adding(days: afterTomorrow ? 2 : 1).map { Match(date: $0, next: index + 1) }
        default: return nil
        }
    }

    /// "in 10 days", "in a week", "in 2 weeks".
    private static func offset(at index: Int, in tokens: [String], today: CivilDate) -> Match? {
        guard tokens[index] == "in", index + 2 < tokens.count,
              let amount = number(tokens[index + 1]) ?? (["a", "an"].contains(tokens[index + 1]) ? 1 : nil)
        else { return nil }
        let unit: Int
        switch tokens[index + 2] {
        case "day", "days": unit = 1
        case "week", "weeks": unit = 7
        default: return nil
        }
        guard amount * unit <= 3_650 else { return nil }
        return today.adding(days: amount * unit).map { Match(date: $0, next: index + 3) }
    }

    private static func holiday(at index: Int, in tokens: [String], today: CivilDate) -> Match? {
        let next = index + 1 < tokens.count ? tokens[index + 1] : ""
        let monthDay: (Int, Int, Int)?
        switch tokens[index] {
        case "christmas", "xmas":
            monthDay = next == "eve" ? (12, 24, 2) : (12, 25, next == "day" ? 2 : 1)
        case "halloween": monthDay = (10, 31, 1)
        case "valentines", "valentine": monthDay = (2, 14, next == "day" ? 2 : 1)
        case "new":
            guard ["year", "years"].contains(next) else { return nil }
            let after = index + 2 < tokens.count ? tokens[index + 2] : ""
            monthDay = after == "eve" ? (12, 31, 3) : (1, 1, after == "day" ? 3 : 2)
        default: monthDay = nil
        }
        guard let (month, day, length) = monthDay,
              let date = nextOccurrence(month: month, day: day, onOrAfter: today) else { return nil }
        return Match(date: date, next: index + length)
    }

    /// "Mar 1", "March 1st 2027", "1 March", "the 1st of March".
    private static func monthDay(at index: Int, in tokens: [String], today: CivilDate) -> Match? {
        guard let month = month(tokens[index]) else { return nil }
        if index + 1 < tokens.count, let day = dayNumber(tokens[index + 1]) {
            let (year, next) = explicitYear(at: index + 2, in: tokens)
            return resolve(month: month, day: day, year: year, at: index, in: tokens, today: today, next: next)
        }
        var before = index - 1
        if before >= 0, tokens[before] == "of" { before -= 1 }
        if before >= 0, let day = dayNumber(tokens[before]) {
            let (year, next) = explicitYear(at: index + 1, in: tokens)
            return resolve(month: month, day: day, year: year, at: before, in: tokens, today: today, next: next)
        }
        return nil
    }

    /// A four-digit year at `index`, and the index after the phrase.
    private static func explicitYear(at index: Int, in tokens: [String]) -> (Int?, Int) {
        guard index < tokens.count, tokens[index].count == 4, let year = Int(tokens[index]),
              (1900...2200).contains(year) else { return (nil, index) }
        return (year, index + 1)
    }

    private static func resolve(month: Int, day: Int, year: Int?, at start: Int, in tokens: [String],
                                today: CivilDate, next: Int) -> Match? {
        if let year {
            return CivilDate(year: year, month: month, day: day).map { Match(date: $0, next: next) }
        }
        let backward = looksBackward(before: start, in: tokens)
        let date = backward
            ? previousOccurrence(month: month, day: day, onOrBefore: today)
            : nextOccurrence(month: month, day: day, onOrAfter: today)
        return date.map { Match(date: $0, next: next) }
    }

    private static func namedWeekday(at index: Int, in tokens: [String], today: CivilDate) -> Match? {
        let token = tokens[index]
        guard let weekday = weekday(token) else { return nil }
        let modifier = index > 0 ? tokens[index - 1] : ""
        // "sat"/"sun" are ordinary words too; only read them after a day modifier.
        if ["sat", "sun"].contains(token), !["on", "next", "this", "last", "coming", "every"].contains(modifier) {
            return nil
        }
        let afterNext = index + 2 < tokens.count && tokens[index + 1] == "after" && tokens[index + 2] == "next"
        let date: CivilDate?
        if ["last", "past", "previous"].contains(modifier) || looksBackward(before: index, in: tokens) {
            date = backward(to: weekday, from: today)
        } else if modifier == "next" || afterNext {
            date = forward(to: weekday, from: today, includingToday: false)
                .flatMap { afterNext ? $0.adding(days: 7) : $0 }
        } else {
            date = forward(to: weekday, from: today, includingToday: true)
        }
        return date.map { Match(date: $0, next: afterNext ? index + 3 : index + 1) }
    }

    private static func looksBackward(before index: Int, in tokens: [String]) -> Bool {
        tokens[max(0, index - 2)..<index].contains { ["since", "last", "ago", "past"].contains($0) }
    }

    // MARK: - Series

    /// "next 3 Fridays", "the next two Mondays", "following 4 Tuesdays".
    private static func countedSeries(at index: Int, in tokens: [String], today: CivilDate) -> [CivilDate]? {
        guard ["next", "coming", "following", "upcoming"].contains(tokens[index]), index + 2 < tokens.count,
              let count = number(tokens[index + 1]), count > 0,
              let weekday = weekday(tokens[index + 2]) else { return nil }
        return upcoming(weekday: weekday, count: count, after: today)
    }

    /// "every Monday in December", "all Fridays in March".
    private static func monthSeries(at index: Int, in tokens: [String], today: CivilDate) -> [CivilDate]? {
        guard ["every", "all"].contains(tokens[index]), index + 3 < tokens.count,
              let weekday = weekday(tokens[index + 1]), tokens[index + 2] == "in",
              let month = month(tokens[index + 3]) else { return nil }
        let year = month < today.month ? today.year + 1 : today.year
        let days = (1...CivilDate.daysInMonth(year: year, month: month)).compactMap {
            CivilDate(year: year, month: month, day: $0)
        }
        let matches = days.filter { $0.weekday == weekday }
        return matches.isEmpty ? nil : matches
    }

    // MARK: - Arithmetic

    static func forward(to weekday: Int, from today: CivilDate, includingToday: Bool) -> CivilDate? {
        var delta = (weekday - today.weekday + 7) % 7
        if delta == 0, !includingToday { delta = 7 }
        return today.adding(days: delta)
    }

    static func backward(to weekday: Int, from today: CivilDate) -> CivilDate? {
        let delta = (today.weekday - weekday + 7) % 7
        return today.adding(days: -(delta == 0 ? 7 : delta))
    }

    /// Eight years always contain a Feb 29 (leap years skip at most one in eight).
    private static let leapSearchYears = 0...8

    static func nextOccurrence(month: Int, day: Int, onOrAfter today: CivilDate) -> CivilDate? {
        for offset in leapSearchYears {
            if let date = CivilDate(year: today.year + offset, month: month, day: day), date >= today { return date }
        }
        return nil
    }

    static func previousOccurrence(month: Int, day: Int, onOrBefore today: CivilDate) -> CivilDate? {
        for offset in leapSearchYears {
            if let date = CivilDate(year: today.year - offset, month: month, day: day), date <= today { return date }
        }
        return nil
    }

    // MARK: - Words

    static func tokenize(_ text: String) -> [String] {
        let capped = String(text.prefix(maximumTextLength)).lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let separated = String(capped.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" ? Character(scalar) : " "
        })
        return separated.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6, "saturday": 7, "sat": 7,
    ]

    /// Singular or plural day name (plural only for full names: "fridays").
    static func weekday(_ token: String) -> Int? {
        if let day = weekdays[token] { return day }
        guard token.hasSuffix("s"), token.count > 6 else { return nil }
        return weekdays[String(token.dropLast())]
    }

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12,
    ]

    static func month(_ token: String) -> Int? { months[token] }

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]

    static func number(_ token: String) -> Int? {
        if let word = numberWords[token] { return word }
        guard token.count <= 4, token.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(token)
    }

    /// 1–31 with an optional ordinal suffix: "1", "1st", "22nd", "3rd", "4th".
    static func dayNumber(_ token: String) -> Int? {
        let digits = token.prefix { $0.isASCIIDigit }
        let suffix = token.dropFirst(digits.count)
        guard (1...2).contains(digits.count), ["", "st", "nd", "rd", "th"].contains(String(suffix)),
              let day = Int(digits), (1...31).contains(day) else { return nil }
        return day
    }
}
