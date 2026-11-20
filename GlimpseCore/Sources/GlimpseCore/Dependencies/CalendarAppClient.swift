import ComposableArchitecture
import CoreServices
import Foundation

/// Opens URLs in Apple's Calendar app (the only registered `ical` handler).
@DependencyClient
public struct CalendarAppClient: Sendable {
    public enum OpenError: LocalizedError, Equatable, Sendable {
        case invalidURL
        case launchServices(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .invalidURL: "The Calendar link couldn't be built."
            case let .launchServices(status): "Calendar couldn't be opened (LaunchServices \(status))."
            }
        }
    }

    public var open: @Sendable (URL) async throws -> Void
}

extension CalendarAppClient: DependencyKey {
    public static var liveValue: Self {
        Self(open: { url in
            // LaunchServices (CoreServices, not AppKit) is permitted in the App Sandbox
            // without an entitlement; it activates Calendar and delivers the URL.
            let status = LSOpenCFURLRef(url as CFURL, nil)
            guard status == noErr else { throw OpenError.launchServices(status) }
        })
    }

    public static let testValue = Self()
}

extension DependencyValues {
    public var calendarApp: CalendarAppClient {
        get { self[CalendarAppClient.self] }
        set { self[CalendarAppClient.self] = newValue }
    }
}
