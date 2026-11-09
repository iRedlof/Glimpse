import Foundation
import GlimpseCore

enum AISubmitAction: Equatable, Sendable {
    /// Save the time the user picked.
    case confirm
    /// Do nothing: no time picked yet, access not yet granted, or work in flight.
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
        // The calendar prompt comes only from the "Allow calendar access"
        // button (click, or Return/Space while it has focus). A second Return
        // in the field, out of habit, must not raise a system prompt.
        case .needsAccess, .choosing, .saving, .searching, .requestingAccess: return .ignore
        case .idle, .noSlots, .failed, .accessUnavailable: return .submit
        }
    }
}
