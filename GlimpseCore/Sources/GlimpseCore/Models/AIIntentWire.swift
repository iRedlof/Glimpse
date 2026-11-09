import Foundation

/// The one JSON shape both AI providers must produce. Unknown keys are
/// ignored and a malformed optional field reads as absent, so one sloppy
/// field cannot sink an otherwise usable reply. Validation happens only in
/// `AIIntentDecoder.validate`.
public struct AIIntentWire: Decodable, Equatable, Sendable {
    public var intent: String
    public var date: String?
    public var dates: [String]?
    /// For a range of one weekday: its name ("friday") and how many.
    public var weekday: String?
    public var count: Int?
    public var label: String?
    public var question: String?
    public var from: String?
    public var to: String?
    public var title: String?
    public var start: String?
    public var end: String?
    public var partOfDay: String?
    public var durationMinutes: Int?
    public var message: String?

    public init(
        intent: String, date: String? = nil, dates: [String]? = nil, weekday: String? = nil,
        count: Int? = nil, label: String? = nil,
        question: String? = nil, from: String? = nil, to: String? = nil, title: String? = nil,
        start: String? = nil, end: String? = nil, partOfDay: String? = nil,
        durationMinutes: Int? = nil, message: String? = nil
    ) {
        self.intent = intent
        self.date = date
        self.dates = dates
        self.weekday = weekday
        self.count = count
        self.label = label
        self.question = question
        self.from = from
        self.to = to
        self.title = title
        self.start = start
        self.end = end
        self.partOfDay = partOfDay
        self.durationMinutes = durationMinutes
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case intent, date, dates, weekday, count, label, question, from, to, title, start, end, partOfDay,
             durationMinutes, message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intent = try container.decode(String.self, forKey: .intent)
        date = Self.lenientString(container, .date)
        dates = Self.lenientStrings(container, .dates)
        weekday = Self.lenientString(container, .weekday)
        count = Self.lenientInt(container, .count)
        label = Self.lenientString(container, .label)
        question = Self.lenientString(container, .question)
        from = Self.lenientString(container, .from)
        to = Self.lenientString(container, .to)
        title = Self.lenientString(container, .title)
        start = Self.lenientString(container, .start)
        end = Self.lenientString(container, .end)
        partOfDay = Self.lenientString(container, .partOfDay)
        durationMinutes = Self.lenientInt(container, .durationMinutes)
        message = Self.lenientString(container, .message)
    }

    // `try?` here is deliberate: the reply is untrusted model output, and a
    // wrongly typed optional field must behave exactly like a missing one.
    private static func lenientString(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
    }

    private static func lenientStrings(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String]? {
        (try? container.decodeIfPresent([String].self, forKey: key)) ?? nil
    }

    private static func lenientInt(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let value = (try? container.decodeIfPresent(Int.self, forKey: key)) ?? nil { return value }
        if let value = (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil,
           value.isFinite, value.rounded() == value, abs(value) < 1_000_000 {
            return Int(value)
        }
        if let text = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
