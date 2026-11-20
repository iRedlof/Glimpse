import Testing

@testable import GlimpseCore

/// The linear candidate scan must yield exactly what scanning fresh from every
/// `{` yields (the original quadratic definition), including braces and quotes
/// inside strings, escapes and unmatched braces.
struct AIIntentCandidateScanTests {
    private static let alphabet: [Character] = ["{", "}", "\"", "\\", "a", " "]
    private static let samples = 1_500
    private static let maximumLength = 24

    @Test
    func linearScanMatchesFreshScanFromEveryBrace() {
        var generator = SplitMix64(seed: 0x5EED_CAFE)
        for _ in 0..<Self.samples {
            let length = Int.random(in: 0...Self.maximumLength, using: &generator)
            let text = String((0..<length).map { _ in Self.alphabet.randomElement(using: &generator)! })
            #expect(AIIntentDecoder.jsonObjectCandidates(in: text) == Self.referenceCandidates(in: text),
                    "text: \(text.debugDescription)")
        }
    }

    @Test
    func goldenCandidates() {
        let cases: [(String, [String])] = [
            (#"{ oops {"intent":"navigate"}"#, [#"{"intent":"navigate"}"#]),
            (#"{"a":"}"} {"b":{}}"#, [#"{"a":"}"}"#, #"{"b":{}}"#, "{}"]),
            (#""{x}" {"#, ["{x}"]),
            (#"{"\"}"}"#, [#"{"\"}"}"#]),
            (String(repeating: "{", count: 4), []),
        ]
        for (text, expected) in cases {
            #expect(AIIntentDecoder.jsonObjectCandidates(in: text) == expected, "text: \(text)")
        }
    }

    /// The original definition: an independent fresh scan from each `{`.
    private static func referenceCandidates(in text: String) -> [String] {
        let characters = Array(text)
        return characters.indices.compactMap { start in
            guard characters[start] == "{" else { return nil }
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
                    if depth == 0 { return String(characters[start...index]) }
                default: break
                }
            }
            return nil
        }
    }
}

/// Deterministic generator so failures reproduce.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
