import Foundation

/// Sends date-parsing prompts through the shared AI proxy.
/// The proxy injects API keys server-side — no credentials in the app.
enum ProxyProvider {
    struct Dependencies: Sendable {
        var endpoint: String
        var authorize: @Sendable (inout URLRequest) -> Void
        var now: @Sendable () -> Date
        var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

        static var live: Self {
            Self(
                endpoint: ProxyConfig.refineEndpoint,
                authorize: { ProxyConfig.addAuthHeaders(to: &$0) },
                now: { Date() },
                transport: { try await URLSession.shared.data(for: $0) }
            )
        }
    }

    static func parseDate(_ query: String, dependencies: Dependencies) async throws -> Date? {
        try Task.checkCancellation()
        let today = ISO8601DateFormatter().string(from: dependencies.now())
        let prompt = "Respond with ONLY a date in yyyy-MM-dd format, nothing else. If the query is relative, today is \(today). Query: \(query)"

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

        let date = DateParser.extractDate(from: text)
        try Task.checkCancellation()
        return date
    }
}
