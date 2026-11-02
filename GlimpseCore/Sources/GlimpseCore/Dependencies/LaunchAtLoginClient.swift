import ComposableArchitecture
import ServiceManagement

@DependencyClient
public struct LaunchAtLoginClient: Sendable {
    public enum Status: String, Sendable, Equatable {
        case enabled
        case requiresApproval
        case notRegistered
        case notFound
        case unavailable
    }

    public var status: @Sendable () -> Status = { .notRegistered }
    public var setEnabled: @Sendable (Bool) async throws -> Void
}

extension LaunchAtLoginClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            status: {
                switch SMAppService.mainApp.status {
                case .enabled: .enabled
                case .requiresApproval: .requiresApproval
                case .notRegistered: .notRegistered
                case .notFound: .notFound
                @unknown default: .unavailable
                }
            },
            setEnabled: { enabled in
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }
            }
        )
    }

    public static let testValue = Self()
}

extension DependencyValues {
    public var launchAtLoginClient: LaunchAtLoginClient {
        get { self[LaunchAtLoginClient.self] }
        set { self[LaunchAtLoginClient.self] = newValue }
    }
}
