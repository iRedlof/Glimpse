import ComposableArchitecture
import CoreServices
import Foundation

/// Opens a validated meeting link (Zoom/Meet/Teams/Webex) in its handler app or browser.
/// Only ever called from an explicit user action (Join button, Return on it, or ⌘J).
@DependencyClient
public struct MeetingLinkClient: Sendable {
    public enum OpenError: LocalizedError, Equatable, Sendable {
        case launchServices(OSStatus)

        public var errorDescription: String? {
            switch self {
            case let .launchServices(status): "The meeting link couldn't be opened (LaunchServices \(status))."
            }
        }
    }

    public var open: @Sendable (MeetingLink) async throws -> Void
}

extension MeetingLinkClient: DependencyKey {
    public static var liveValue: Self {
        Self(open: { link in
            // LaunchServices (CoreServices) is allowed in the App Sandbox without an
            // entitlement, like CalendarAppClient. The URL was validated as a strict
            // https meeting link when the event was read.
            let status = LSOpenCFURLRef(link.url as CFURL, nil)
            guard status == noErr else { throw OpenError.launchServices(status) }
        })
    }

    public static let testValue = Self()
}

extension DependencyValues {
    public var meetingLinks: MeetingLinkClient {
        get { self[MeetingLinkClient.self] }
        set { self[MeetingLinkClient.self] = newValue }
    }
}
