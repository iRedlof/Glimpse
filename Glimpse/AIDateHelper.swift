import Foundation
import GlimpseCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Routes AI date queries to the best available provider:
/// 1. Cloud AI via proxy (no API key needed) — works on any macOS 14+
/// 2. Apple FoundationModels (macOS 26+) — on-device, free
/// 3. Error if neither is available
enum AIDateHelper {
    enum Provider: Equatable, Sendable {
        case proxy
        case foundationModels
        case none
    }

    struct Dependencies: Sendable {
        var parseProxy: @Sendable (String) async throws -> Date?
        var now: @Sendable () -> Date
        var generateOnDevice: @Sendable (String) async throws -> String

        static var live: Self {
            Self(
                parseProxy: {
                    try await ProxyProvider.parseDate($0, dependencies: .live)
                },
                now: { Date() },
                generateOnDevice: { prompt in
                    #if canImport(FoundationModels)
                    if #available(macOS 26, *) {
                        let session = LanguageModelSession()
                        return try await session.respond(to: prompt).content
                    }
                    #endif
                    throw AIDateFailure.unavailable
                }
            )
        }
    }

    static func provider(for preference: AIProvider, onDeviceSupported: Bool) -> Provider {
        switch preference {
        case .proxy:
            return .proxy
        case .onDevice:
            return onDeviceSupported ? .foundationModels : .none
        case .auto:
            return .proxy
        }
    }

    static func activeProvider() -> Provider {
        provider(
            for: PreferencesClient.liveValue.loadAIProvider(),
            onDeviceSupported: onDeviceSupported()
        )
    }

    static func parseNaturalLanguageDate(
        _ query: String, provider: Provider, dependencies: Dependencies
    ) async throws -> Date? {
        try Task.checkCancellation()
        switch provider {
        case .proxy:
            do {
                let result = try await dependencies.parseProxy(query)
                try Task.checkCancellation()
                return result
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                if let failure = error as? AIDateFailure {
                    throw failure
                }
                AppLogger.general.error("AI date failure: transport")
                throw AIDateFailure.transport
            }
        case .foundationModels:
            do {
                let today = ISO8601DateFormatter().string(from: dependencies.now())
                let prompt = "Respond with ONLY a date in yyyy-MM-dd format, nothing else. If the query is relative, today is \(today). Query: \(query)"
                try Task.checkCancellation()
                let response = try await dependencies.generateOnDevice(prompt)
                try Task.checkCancellation()
                let date = DateParser.extractDate(from: response)
                try Task.checkCancellation()
                return date
            } catch {
                try Task.checkCancellation()
                if error is CancellationError {
                    throw CancellationError()
                }
                if (error as? AIDateFailure) == .unavailable {
                    AppLogger.general.error("AI date failure: unavailable")
                    throw AIDateFailure.unavailable
                }
                AppLogger.general.error("AI date failure: onDeviceRequest")
                throw AIDateFailure.onDeviceRequest
            }
        case .none:
            try Task.checkCancellation()
            AppLogger.general.error("AI date failure: unavailable")
            throw AIDateFailure.unavailable
        }
    }

    static func providerName() -> String {
        switch activeProvider() {
        case .proxy: "Cloud AI"
        case .foundationModels: "On-device AI"
        case .none: "None"
        }
    }

    static func onDeviceSupported() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

}

// MARK: - Shared Date Parser

enum DateParser {
    static func extractDate(from text: String) -> Date? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: "\\d{4}-\\d{2}-\\d{2}"),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let matchRange = Range(match.range, in: raw)
        else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: String(raw[matchRange]))
    }
}
