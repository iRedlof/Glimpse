import Foundation

public enum AIProvider: String, Equatable, Sendable, CaseIterable, Codable {
    case auto = "auto"
    case proxy = "proxy"
    case onDevice = "onDevice"

    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .proxy: "Cloud AI"
        case .onDevice: "On-device AI"
        }
    }

    /// Tooltip for the Settings provider picker. Only Auto falls back.
    public var helpText: String {
        switch self {
        case .auto: "Uses on-device AI when available and falls back to Cloud AI if it can’t answer. Uses Cloud AI otherwise."
        case .proxy: "Always uses Cloud AI."
        case .onDevice: "Always uses on-device AI (macOS 26 with Apple Intelligence)."
        }
    }
}
