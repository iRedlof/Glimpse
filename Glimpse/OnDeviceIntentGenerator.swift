import Foundation
import GlimpseCore

#if canImport(FoundationModels)
import FoundationModels

/// Structured on-device output. Mirrors `AIIntentWire` field for field so
/// both providers go through the same `AIIntentDecoder.validate`.
@available(macOS 26, *)
@Generable(description: "One calendar request turned into a structured intent")
struct GeneratedIntent {
    @Guide(description: "What the user wants", .anyOf(["navigate", "range", "question", "create", "clarify"]))
    var intent: String
    @Guide(description: "A single date, yyyy-MM-dd")
    var date: String?
    @Guide(description: "Dates to highlight, yyyy-MM-dd, at most 31")
    var dates: [String]?
    @Guide(description: "Short label for highlighted dates, e.g. Next 3 Fridays")
    var label: String?
    @Guide(description: "countDays, countWorkdays, countWeekendDays, weekNumber or weekday")
    var question: String?
    @Guide(description: "Start date of a count, yyyy-MM-dd")
    var from: String?
    @Guide(description: "End date of a count, yyyy-MM-dd")
    var to: String?
    @Guide(description: "Event title")
    var title: String?
    @Guide(description: "Event start, 24-hour HH:mm")
    var start: String?
    @Guide(description: "Event end, 24-hour HH:mm")
    var end: String?
    @Guide(description: "morning, midday, afternoon or evening")
    var partOfDay: String?
    @Guide(description: "Event length in minutes, 5 to 480")
    var durationMinutes: Int?
    @Guide(description: "One short clarifying question, at most 12 words")
    var message: String?

    var wire: AIIntentWire {
        AIIntentWire(
            intent: intent, date: date, dates: dates.map { Array($0.prefix(DateRangeHighlight.maximumDates)) },
            label: label, question: question, from: from, to: to, title: title, start: start, end: end,
            partOfDay: partOfDay, durationMinutes: durationMinutes, message: message
        )
    }
}

@available(macOS 26, *)
enum OnDeviceIntentGenerator {
    static func generate(instructions: String, prompt: String) async throws -> AIIntentWire {
        guard case .available = SystemLanguageModel.default.availability else {
            throw AIDateFailure.unavailable
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: GeneratedIntent.self)
        return response.content.wire
    }
}
#endif
