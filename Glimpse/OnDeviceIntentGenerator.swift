import Foundation
import GlimpseCore

#if canImport(FoundationModels)
import FoundationModels

/// Structured on-device output. One case per request type keeps the small
/// model from mixing fields across intents (a flat schema made it file
/// questions as events). Every case maps onto `AIIntentWire`, so both
/// providers go through the same `AIIntentDecoder.validate`.
@available(macOS 26, *)
@Generable(description: "One calendar request")
enum GeneratedRequest {
    case navigate(GeneratedDay)
    case range(GeneratedRange)
    case count(GeneratedCount)
    case weekNumber(GeneratedDay)
    case weekdayOf(GeneratedDay)
    case create(GeneratedCreate)
    case clarify(GeneratedClarify)

    var wire: AIIntentWire {
        switch self {
        case let .navigate(day):
            AIIntentWire(intent: "navigate", date: day.date)
        case let .range(range):
            AIIntentWire(intent: "range", dates: Array(range.dates.prefix(DateRangeHighlight.maximumDates)),
                         weekday: range.weekday, count: range.count, label: range.label)
        case let .count(count):
            AIIntentWire(intent: "question", question: count.question, from: count.from, to: count.to)
        case let .weekNumber(day):
            AIIntentWire(intent: "question", date: day.date, question: "weekNumber")
        case let .weekdayOf(day):
            AIIntentWire(intent: "question", date: day.date, question: "weekday")
        case let .create(create):
            AIIntentWire(intent: "create", date: create.date, title: create.title, start: create.start,
                         end: create.end, partOfDay: create.partOfDay, durationMinutes: create.durationMinutes)
        case let .clarify(clarify):
            AIIntentWire(intent: "clarify", message: clarify.message)
        }
    }
}

@available(macOS 26, *)
@Generable
struct GeneratedDay {
    @Guide(description: "The day, yyyy-MM-dd, copied from the date table")
    var date: String
}

@available(macOS 26, *)
@Generable
struct GeneratedRange {
    @Guide(description: "The dates, yyyy-MM-dd, copied from the date table", .maximumCount(31))
    var dates: [String]
    @Guide(description: "For one repeated weekday: its name",
           .anyOf(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]))
    var weekday: String?
    @Guide(description: "For one repeated weekday: how many dates", .range(1...31))
    var count: Int?
    @Guide(description: "Short label, e.g. Next 3 Fridays")
    var label: String
}

@available(macOS 26, *)
@Generable
struct GeneratedCount {
    @Guide(description: "What to count", .anyOf(["days", "workdays", "weekendDays"]))
    var kind: String
    @Guide(description: "Start day, yyyy-MM-dd; leave empty for today")
    var from: String?
    @Guide(description: "End day, yyyy-MM-dd")
    var to: String

    var question: String {
        switch kind {
        case "workdays": "countWorkdays"
        case "weekendDays": "countWeekendDays"
        default: "countDays"
        }
    }
}

@available(macOS 26, *)
@Generable
struct GeneratedCreate {
    @Guide(description: "The event title from the request, e.g. Coffee with Priya")
    var title: String
    @Guide(description: "The day, yyyy-MM-dd, copied from the date table")
    var date: String
    @Guide(description: "Start, 24-hour HH:mm, only if the request gives a clock time")
    var start: String?
    @Guide(description: "End, 24-hour HH:mm, only if the request gives an end time")
    var end: String?
    @Guide(description: "Part of day the request names", .anyOf(["morning", "midday", "afternoon", "evening"]))
    var partOfDay: String?
    @Guide(description: "Length in minutes, only if the request gives one", .range(5...480))
    var durationMinutes: Int?
}

@available(macOS 26, *)
@Generable
struct GeneratedClarify {
    @Guide(description: "One short question back to the user, at most 12 words")
    var message: String
}

@available(macOS 26, *)
enum OnDeviceIntentGenerator {
    static func generate(instructions: String, prompt: String) async throws -> AIIntentWire {
        guard case .available = SystemLanguageModel.default.availability else {
            throw AIDateFailure.unavailable
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: GeneratedRequest.self)
        return response.content.wire
    }
}
#endif
