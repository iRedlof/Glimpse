import ComposableArchitecture
import Foundation

@Reducer
public struct PreferencesFeature: Sendable {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var startOfWeekday: Int = 1
        public var workdays: Set<Int> = [2, 3, 4, 5, 6]
        public var displayOptions: MenuBarDisplayOptions = .default
        public var launchAtLoginStatus: LaunchAtLoginClient.Status = .notRegistered
        public var isUpdatingLaunchAtLogin = false
        public var launchAtLoginError: String?
        public var showAISearch: Bool = true
        public var aiProvider: AIProvider = .auto

        public var launchAtLogin: Bool { launchAtLoginStatus == .enabled }

        public init() {}

        /// Factory for live usage - loads real preferences from UserDefaults.
        /// Use plain init() in tests to get deterministic defaults.
        public static func live() -> State {
            let prefs = PreferencesClient.liveValue
            var state = State()
            state.startOfWeekday = prefs.loadStartOfWeekday()
            state.workdays = prefs.loadWorkdays()
            state.displayOptions = prefs.loadDisplayOptions()
            state.showAISearch = prefs.loadShowAISearch()
            state.aiProvider = prefs.loadAIProvider()
            state.launchAtLoginStatus = LaunchAtLoginClient.liveValue.status()
            return state
        }
    }

    public enum Action: Sendable {
        case onAppear
        case setStartOfWeekday(Int)
        case toggleWorkday(Int)
        case setShowAISearch(Bool)
        case setAIProvider(AIProvider)
        case setShowIcon(Bool)
        case setShowDayOfWeek(Bool)
        case setShowMonth(Bool)
        case setShowDate(Bool)
        case setShowYear(Bool)
        case setShowFilledBackground(Bool)
        case setLaunchAtLogin(Bool)
        case refreshLaunchAtLogin
        case launchAtLoginSucceeded(LaunchAtLoginClient.Status)
        case launchAtLoginFailed(String, LaunchAtLoginClient.Status)

        // Delegate actions for parent to react to
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable {
            case preferencesChanged
            case displayOptionsChanged(MenuBarDisplayOptions)
        }
    }

    @Dependency(\.preferencesClient) var preferencesClient
    @Dependency(\.launchAtLoginClient) var launchAtLoginClient

    private enum CancelID { case launchAtLogin }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.startOfWeekday = preferencesClient.loadStartOfWeekday()
                state.workdays = preferencesClient.loadWorkdays()
                state.displayOptions = preferencesClient.loadDisplayOptions()
                if !state.isUpdatingLaunchAtLogin {
                    state.launchAtLoginStatus = launchAtLoginClient.status()
                }
                state.showAISearch = preferencesClient.loadShowAISearch()
                state.aiProvider = preferencesClient.loadAIProvider()
                return .none

            case let .setShowAISearch(enabled):
                state.showAISearch = enabled
                preferencesClient.saveShowAISearch(enabled)
                return .send(.delegate(.preferencesChanged))

            case let .setAIProvider(provider):
                state.aiProvider = provider
                preferencesClient.saveAIProvider(provider)
                return .none

            case let .setStartOfWeekday(day):
                state.startOfWeekday = day
                preferencesClient.saveStartOfWeekday(day)
                return .send(.delegate(.preferencesChanged))

            case let .toggleWorkday(weekday):
                if state.workdays.contains(weekday) {
                    state.workdays.remove(weekday)
                } else {
                    state.workdays.insert(weekday)
                }
                preferencesClient.saveWorkdays(state.workdays)
                return .send(.delegate(.preferencesChanged))

            case let .setShowIcon(value):
                state.displayOptions.showIcon = value
                preferencesClient.saveDisplayOptions(state.displayOptions)
                return .send(.delegate(.displayOptionsChanged(state.displayOptions)))

            case let .setShowDayOfWeek(value):
                state.displayOptions.showDayOfWeek = value
                preferencesClient.saveDisplayOptions(state.displayOptions)
                return .send(.delegate(.displayOptionsChanged(state.displayOptions)))

            case let .setShowMonth(value):
                state.displayOptions.showMonth = value
                preferencesClient.saveDisplayOptions(state.displayOptions)
                return .send(.delegate(.displayOptionsChanged(state.displayOptions)))

            case let .setShowDate(value):
                state.displayOptions.showDate = value
                preferencesClient.saveDisplayOptions(state.displayOptions)
                return .send(.delegate(.displayOptionsChanged(state.displayOptions)))

            case let .setShowYear(value):
                state.displayOptions.showYear = value
                preferencesClient.saveDisplayOptions(state.displayOptions)
                return .send(.delegate(.displayOptionsChanged(state.displayOptions)))

            case let .setShowFilledBackground(value):
                state.displayOptions.showFilledBackground = value
                preferencesClient.saveDisplayOptions(state.displayOptions)
                return .send(.delegate(.displayOptionsChanged(state.displayOptions)))

            case let .setLaunchAtLogin(enabled):
                guard !state.isUpdatingLaunchAtLogin else { return .none }
                state.isUpdatingLaunchAtLogin = true
                state.launchAtLoginError = nil
                return .run { send in
                    do {
                        try await launchAtLoginClient.setEnabled(enabled)
                        await send(.launchAtLoginSucceeded(launchAtLoginClient.status()))
                    } catch {
                        AppLogger.preferences.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
                        await send(.launchAtLoginFailed(error.localizedDescription, launchAtLoginClient.status()))
                    }
                }
                .cancellable(id: CancelID.launchAtLogin)

            case .refreshLaunchAtLogin:
                guard !state.isUpdatingLaunchAtLogin else { return .none }
                let status = launchAtLoginClient.status()
                if status != state.launchAtLoginStatus {
                    state.launchAtLoginError = nil
                }
                state.launchAtLoginStatus = status
                return .none

            case let .launchAtLoginSucceeded(status):
                guard state.isUpdatingLaunchAtLogin else { return .none }
                state.isUpdatingLaunchAtLogin = false
                state.launchAtLoginStatus = status
                state.launchAtLoginError = nil
                return .none

            case let .launchAtLoginFailed(errorMessage, status):
                guard state.isUpdatingLaunchAtLogin else { return .none }
                state.isUpdatingLaunchAtLogin = false
                state.launchAtLoginError = errorMessage
                state.launchAtLoginStatus = status
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
