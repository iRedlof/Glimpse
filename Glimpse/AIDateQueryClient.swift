import Foundation
import GlimpseCore

/// Operational failures contain no query, response, endpoint or error payload.
enum AIDateFailure: Error, Sendable, Equatable, CaseIterable {
    case requestPreparation
    case transport
    case nonHTTPResponse
    case nonSuccessResponse
    case unusableResponse
    case onDeviceRequest
    case unavailable

    /// Auto retries the other provider once only for these: the provider was
    /// unavailable, answered unusably, or the request failed on the way.
    /// A local request-preparation fault would fail the same way again.
    var allowsAutoFallback: Bool {
        switch self {
        case .unavailable, .onDeviceRequest, .unusableResponse,
             .transport, .nonHTTPResponse, .nonSuccessResponse: true
        case .requestPreparation: false
        }
    }
}

struct AIDateQueryClient: Sendable {
    var resolveProvider: @Sendable (AIProvider) -> AIDateHelper.Provider
    /// nil: the provider answered but nothing usable came back.
    var interpret: @Sendable (String, AIDateHelper.Provider) async throws -> AIIntent?

    /// Configuration and provider work are evaluated only when these closures
    /// execute. Synthetic clients supply both closures explicitly.
    static var live: Self {
        Self(
            resolveProvider: {
                AIDateHelper.provider(
                    for: $0, onDeviceSupported: AIDateHelper.onDeviceSupported()
                )
            },
            interpret: {
                try await AIDateHelper.interpret(
                    $0, provider: $1, dependencies: .live
                )
            }
        )
    }
}
