import Foundation

/// Decodes and validates provider replies. Both providers go through here,
/// so a reply means the same thing whichever model produced it.
public enum AIIntentDecoder {
    public static let maximumClarifyLength = 120
    /// Accepted dates lie within this many years of today.
    public static let yearBound = 100

    public static let defaultClarifyMessage = "What should I do with that? Try a date, a plan or a question."
    public static let unsupportedQuestionMessage = "I can count days or workdays, or give a week number or weekday."
    public static let titleMessage = "What should the event be called?"
    public static let dayMessage = "Which day should I add it to?"
    public static let pastDayMessage = "That day has passed. Which day did you mean?"
    public static let durationMessage = "How long should it be? Up to 8 hours."
    public static let timeMessage = "What time should it start?"

    /// Extracts the first decodable JSON object (tolerating code fences and
    /// prose), then validates it. A bare `yyyy-MM-dd` reply is a legacy
    /// navigate. Anything unusable returns nil.
    public static func decode(text: String, today: CivilDate) -> AIIntent? {
        for candidate in jsonObjectCandidates(in: text) {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                let wire = try JSONDecoder().decode(AIIntentWire.self, from: data)
                return validate(wire, today: today)
            } catch {
                // Not the reply object (e.g. braces in prose); keep scanning.
                continue
            }
        }
        let bare = text.trimmingCharacters(in: legacyTrimSet)
        guard let date = CivilDate(iso: bare), isInBounds(date, today: today) else { return nil }
        return .navigate(date)
    }

    public static func validate(_ wire: AIIntentWire, today: CivilDate) -> AIIntent? {
        switch wire.intent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "navigate":
            return day(wire.date, today: today).map(AIIntent.navigate)
        case "range":
            return range(wire, today: today)
        case "question":
            return question(wire, today: today).map(AIIntent.question) ?? .clarify(unsupportedQuestionMessage)
        case "create":
            return create(wire, today: today)
        case "clarify":
            let message = sanitize(wire.message ?? "", limit: maximumClarifyLength, ellipsis: true)
            return .clarify(message.isEmpty ? defaultClarifyMessage : message)
        default:
            return nil
        }
    }

    // MARK: - Intents

    private static func range(_ wire: AIIntentWire, today: CivilDate) -> AIIntent? {
        let dates = (wire.dates ?? []).compactMap { day($0, today: today) }
        guard !dates.isEmpty else { return nil }
        let label = sanitize(wire.label ?? "", limit: DateRangeHighlight.maximumLabelLength, ellipsis: true)
        return .range(DateRangeHighlight(
            dates: dates, label: label.isEmpty ? DateRangeHighlight.defaultLabel : label
        ))
    }

    private static func question(_ wire: AIIntentWire, today: CivilDate) -> DateQuestion? {
        let kind = (wire.question ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let countKinds: [String: DayKind] = [
            "countdays": .days, "countworkdays": .workdays, "countweekenddays": .weekendDays,
        ]
        if let dayKind = countKinds[kind] {
            guard let to = day(wire.to, today: today) else { return nil }
            let from = wire.from == nil ? today : day(wire.from, today: today)
            guard let from else { return nil }
            return .count(dayKind, from: min(from, to), to: max(from, to))
        }
        let date = wire.date == nil ? today : day(wire.date, today: today)
        guard let date else { return nil }
        switch kind {
        case "weeknumber": return .weekNumber(date)
        case "weekday": return .weekday(date)
        default: return nil
        }
    }

    private static func create(_ wire: AIIntentWire, today: CivilDate) -> AIIntent {
        let title = sanitize(wire.title ?? "", limit: EventDraft.maximumTitleLength, ellipsis: false)
        guard !title.isEmpty else { return .clarify(titleMessage) }
        guard let date = day(wire.date, today: today) else { return .clarify(dayMessage) }
        guard date >= today else { return .clarify(pastDayMessage) }
        switch window(wire) {
        case let .success(window, minutes):
            return .create(EventDraft(title: title, day: date, window: window, durationMinutes: minutes))
        case let .failure(message):
            return .clarify(message)
        }
    }

    private enum WindowResult {
        case success(TimeWindow, Int)
        case failure(String)
    }

    private static func window(_ wire: AIIntentWire) -> WindowResult {
        guard let start = clockTime(wire.start), let end = clockTime(wire.end) else {
            return .failure(timeMessage)
        }
        if let duration = wire.durationMinutes, !EventDraft.durationRange.contains(duration) {
            return .failure(durationMessage)
        }
        let requested = wire.durationMinutes
        switch (start, end) {
        case let (.some(start), .some(end)):
            let span = end.minutesSinceMidnight - start.minutesSinceMidnight
            guard span > 0 else { return .failure(timeMessage) }
            let minutes = requested ?? span
            if minutes == span {
                guard EventDraft.durationRange.contains(span) else { return .failure(durationMessage) }
                return .success(.exact(start), span)
            }
            guard minutes < span else { return .failure(timeMessage) }
            return .success(.between(start, end), minutes)
        case let (.some(start), nil):
            return .success(.exact(start), requested ?? EventDraft.defaultDurationMinutes)
        case let (nil, .some(end)):
            let minutes = requested ?? EventDraft.defaultDurationMinutes
            let startMinute = end.minutesSinceMidnight - minutes
            guard startMinute >= 0,
                  let start = ClockTime(hour: startMinute / 60, minute: startMinute % 60)
            else { return .failure(timeMessage) }
            return .success(.exact(start), minutes)
        case (nil, nil):
            let minutes = requested ?? EventDraft.defaultDurationMinutes
            let part = (wire.partOfDay?.trimmingCharacters(in: .whitespaces).lowercased())
                .flatMap(PartOfDay.init(rawValue:))
            return .success(part.map(TimeWindow.partOfDay) ?? .unspecified, minutes)
        }
    }

    // MARK: - Field helpers

    /// `.some(nil)` when missing or blank; nil when present but malformed.
    private static func clockTime(_ text: String?) -> ClockTime?? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return .some(nil) }
        guard let time = ClockTime(hhmm: text) else { return nil }
        return .some(time)
    }

    private static func day(_ text: String?, today: CivilDate) -> CivilDate? {
        guard let text, let date = CivilDate(iso: text.trimmingCharacters(in: .whitespaces)),
              isInBounds(date, today: today) else { return nil }
        return date
    }

    static func isInBounds(_ date: CivilDate, today: CivilDate) -> Bool {
        let lower = shifted(today, years: -yearBound)
        let upper = shifted(today, years: yearBound)
        return (lower...upper).contains(date)
    }

    private static func shifted(_ date: CivilDate, years: Int) -> CivilDate {
        let year = date.year + years
        return CivilDate(year: year, month: date.month, day: date.day)
            ?? CivilDate(year: year, month: date.month, day: CivilDate.daysInMonth(year: year, month: date.month))
            ?? date
    }

    /// Single line, control characters removed, whitespace collapsed, capped.
    static func sanitize(_ text: String, limit: Int, ellipsis: Bool) -> String {
        let flattened = String(text.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar)
                ? " " : Character(scalar)
        })
        let collapsed = flattened.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        if ellipsis {
            let head = collapsed.prefix(limit - 1).trimmingCharacters(in: .whitespaces)
            return head + "…"
        }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }

    private static let legacyTrimSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "`\"'."))

    /// Every balanced `{…}` substring in order, skipping braces inside strings.
    static func jsonObjectCandidates(in text: String) -> [String] {
        let characters = Array(text)
        var candidates: [String] = []
        var index = 0
        while index < characters.count {
            guard characters[index] == "{" else {
                index += 1
                continue
            }
            if let end = matchingBrace(in: characters, from: index) {
                candidates.append(String(characters[index...end]))
            }
            index += 1
        }
        return candidates
    }

    private static func matchingBrace(in characters: [Character], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        for index in start..<characters.count {
            let character = characters[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }
}
