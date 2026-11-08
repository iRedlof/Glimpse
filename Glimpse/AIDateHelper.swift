import Foundation
import GlimpseCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Routes AI calendar queries to the best available provider:
/// 1. Cloud AI via proxy (no API key needed) — works on any macOS 14+
/// 2. Apple FoundationModels (macOS 26+) — on-device, free
/// 3. Error if neither is available
/// Both providers return the same structured intent and share one validator.
enum AIDateHelper {
    enum Provider: Equatable, Sendable {
        case proxy
        case foundationModels
        case none
    }

    struct Dependencies: Sendable {
        var interpretProxy: @Sendable (String) async throws -> AIIntent?
        var now: @Sendable () -> Date
        var calendar: Calendar = .current
        /// Structured on-device generation: (instructions, user prompt) → wire intent.
        var generateOnDevice: @Sendable (String, String) async throws -> AIIntentWire

        static var live: Self {
            Self(
                interpretProxy: {
                    try await ProxyProvider.interpret($0, dependencies: .live)
                },
                now: { Date() },
                calendar: .autoupdatingCurrent,
                generateOnDevice: { instructions, prompt in
                    #if canImport(FoundationModels)
                    if #available(macOS 26, *) {
                        return try await OnDeviceIntentGenerator.generate(instructions: instructions, prompt: prompt)
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

    /// The validated intent; nil means the provider answered but nothing usable came back.
    static func interpret(
        _ query: String, provider: Provider, dependencies: Dependencies
    ) async throws -> AIIntent? {
        try Task.checkCancellation()
        switch provider {
        case .proxy:
            do {
                let result = try await dependencies.interpretProxy(query)
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
                let today = CivilDate(dependencies.now(), calendar: dependencies.calendar)
                let instructions = AIIntentPrompt.instructions(
                    today: today, timeZone: dependencies.calendar.timeZone
                )
                try Task.checkCancellation()
                let wire = try await dependencies.generateOnDevice(instructions, AIIntentPrompt.user(query))
                try Task.checkCancellation()
                let intent = AIIntentDecoder.validate(wire, today: today)
                if intent == nil { AppLogger.general.info("AI intent unparsed") }
                return intent
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
