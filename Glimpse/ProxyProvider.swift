import Foundation
import GlimpseCore

/// Sends calendar-intent prompts through the shared AI proxy.
/// The proxy injects API keys server-side — no credentials in the app.
enum ProxyProvider {
    struct Dependencies: Sendable {
        var endpoint: String
        var authorize: @Sendable (inout URLRequest) -> Void
        var now: @Sendable () -> Date
        var calendar: Calendar = .current
        var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

        static var live: Self {
            Self(
                endpoint: ProxyConfig.refineEndpoint,
                authorize: { ProxyConfig.addAuthHeaders(to: &$0) },
                now: { Date() },
                calendar: .autoupdatingCurrent,
                transport: { try await URLSession.shared.data(for: $0) }
            )
        }
    }

    /// The validated intent, or nil when the model replied but nothing usable
    /// could be read (the caller asks the user to rephrase).
    static func interpret(_ query: String, dependencies: Dependencies) async throws -> AIIntent? {
        try Task.checkCancellation()
        // "Today" is the local civil date, never UTC (gotchas.md: ISO 8601 off-by-one).
        let today = CivilDate(dependencies.now(), calendar: dependencies.calendar)
        let prompt = AIIntentPrompt.full(query: query, today: today, timeZone: dependencies.calendar.timeZone)

        guard let url = URL(string: dependencies.endpoint) else {
            try Task.checkCancellation()
            AppLogger.general.error("AI date failure: requestPreparation")
            throw AIDateFailure.requestPreparation
        }

        let body: [String: Any] = [
            "tier": "balanced",
            "prompt": prompt,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            try Task.checkCancellation()
            AppLogger.general.error("AI date failure: requestPreparation")
            throw AIDateFailure.requestPreparation
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        dependencies.authorize(&request)

        let result: (Data, URLResponse)
        do {
            try Task.checkCancellation()
            result = try await dependencies.transport(request)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            AppLogger.general.error("AI date failure: transport")
            throw AIDateFailure.transport
        }
        try Task.checkCancellation()
        let (data, response) = result

        guard let httpResponse = response as? HTTPURLResponse else {
            try Task.checkCancellation()
            AppLogger.general.error("AI date failure: nonHTTPResponse")
            throw AIDateFailure.nonHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            try Task.checkCancellation()
            AppLogger.general.error("AI date failure: nonSuccessResponse")
            throw AIDateFailure.nonSuccessResponse
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            try Task.checkCancellation()
            AppLogger.general.error("AI date failure: unusableResponse")
            throw AIDateFailure.unusableResponse
        }

        // Days the query names are resolved in Swift, not by the model.
        let intent = AIIntentDecoder.decode(text: text, today: today, query: AIIntentPrompt.sanitized(query))
        try Task.checkCancellation()
        if intent == nil { AppLogger.general.info("AI intent unparsed") }
        return intent
    }
}
