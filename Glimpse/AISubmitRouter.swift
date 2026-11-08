import Foundation
import GlimpseCore

enum AISubmitAction: Equatable, Sendable {
    /// Save the time the user picked.
    case confirm
    /// The explicit "Allow calendar access" action.
    case allowAccess
    /// Do nothing: no time picked yet, or work is already in flight.
    case ignore
    /// Send the draft to the AI.
    case submit
}

/// Decides what Return in the AI field means. Pure so the honest-button rule
/// (never book without an explicit pick) is testable without UI.
enum AISubmitRouter {
    static func route(phase: ScheduleFeature.Phase, canConfirm: Bool) -> AISubmitAction {
        if canConfirm { return .confirm }
        switch phase {
        case .needsAccess: return .allowAccess
        case .choosing, .saving, .searching, .requestingAccess: return .ignore
        case .idle, .noSlots, .failed, .accessUnavailable: return .submit
        }
    }
}
