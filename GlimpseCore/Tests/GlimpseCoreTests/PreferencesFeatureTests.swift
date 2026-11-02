import ComposableArchitecture
import Foundation
import Testing

@testable import GlimpseCore

@MainActor
struct PreferencesFeatureTests {

    @Test
    func onAppear_loadsAllPreferences() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.loadStartOfWeekday = { 2 }
            $0.preferencesClient.loadWorkdays = { [2, 3] }
            $0.preferencesClient.loadDisplayOptions = {
                MenuBarDisplayOptions(showIcon: false, showYear: true)
            }
            $0.preferencesClient.loadShowAISearch = { false }
            $0.preferencesClient.loadAIProvider = { .proxy }
            $0.launchAtLoginClient.status = { .enabled }
        }

        await store.send(.onAppear) {
            $0.startOfWeekday = 2
            $0.workdays = [2, 3]
            $0.displayOptions = MenuBarDisplayOptions(showIcon: false, showYear: true)
            $0.launchAtLoginStatus = .enabled
            $0.aiProvider = .proxy
            $0.showAISearch = false
        }
    }

    @Test
    func setStartOfWeekday_savesAndNotifies() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveStartOfWeekday = { _ in }
        }

        await store.send(.setStartOfWeekday(2)) {
            $0.startOfWeekday = 2
        }

        await store.receive(\.delegate.preferencesChanged)
    }

    @Test
    func toggleWorkday_addsAndRemoves() async {
        var state = PreferencesFeature.State()
        state.workdays = [2, 3, 4, 5, 6]

        let store = TestStore(initialState: state) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveWorkdays = { _ in }
        }

        await store.send(.toggleWorkday(7)) {
            $0.workdays = [2, 3, 4, 5, 6, 7]
        }

        await store.receive(\.delegate.preferencesChanged)

        await store.send(.toggleWorkday(6)) {
            $0.workdays = [2, 3, 4, 5, 7]
        }

        await store.receive(\.delegate.preferencesChanged)
    }

    @Test
    func setShowIcon_savesAndNotifies() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveDisplayOptions = { _ in }
        }

        await store.send(.setShowIcon(false)) {
            $0.displayOptions.showIcon = false
        }

        await store.receive(\.delegate.displayOptionsChanged)
    }

    @Test
    func setShowDayOfWeek_savesAndNotifies() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveDisplayOptions = { _ in }
        }

        await store.send(.setShowDayOfWeek(false)) {
            $0.displayOptions.showDayOfWeek = false
        }

        await store.receive(\.delegate.displayOptionsChanged)
    }

    @Test
    func setShowMonth_savesAndNotifies() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveDisplayOptions = { _ in }
        }

        await store.send(.setShowMonth(false)) {
            $0.displayOptions.showMonth = false
        }

        await store.receive(\.delegate.displayOptionsChanged)
    }

    @Test
    func setShowDate_savesAndNotifies() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveDisplayOptions = { _ in }
        }

        await store.send(.setShowDate(false)) {
            $0.displayOptions.showDate = false
        }

        await store.receive(\.delegate.displayOptionsChanged)
    }

    @Test
    func setShowYear_savesAndNotifies() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveDisplayOptions = { _ in }
        }

        await store.send(.setShowYear(true)) {
            $0.displayOptions.showYear = true
        }

        await store.receive(\.delegate.displayOptionsChanged)
    }

    @Test
    func setLaunchAtLogin_success_readsActualStatus() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.launchAtLoginClient.setEnabled = { _ in }
            $0.launchAtLoginClient.status = { .enabled }
        }

        await store.send(.setLaunchAtLogin(true)) {
            $0.isUpdatingLaunchAtLogin = true
        }

        await store.receive(\.launchAtLoginSucceeded) {
            $0.isUpdatingLaunchAtLogin = false
            $0.launchAtLoginStatus = .enabled
        }
        #expect(store.state.launchAtLogin)
    }

    @Test
    func setLaunchAtLogin_failure_preservesObservedStatusAndShowsError() async {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "test error" }
        }

        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.launchAtLoginClient.setEnabled = { _ in throw TestError() }
            $0.launchAtLoginClient.status = { .notFound }
        }

        await store.send(.setLaunchAtLogin(true)) {
            $0.isUpdatingLaunchAtLogin = true
        }

        await store.receive(\.launchAtLoginFailed) {
            $0.isUpdatingLaunchAtLogin = false
            $0.launchAtLoginError = "test error"
            $0.launchAtLoginStatus = .notFound
        }
        #expect(!store.state.launchAtLogin)
    }

    @Test(arguments: [
        LaunchAtLoginClient.Status.requiresApproval,
        .notRegistered,
        .notFound,
        .unavailable,
    ])
    func setLaunchAtLogin_success_doesNotClaimEnabledForOtherStatuses(
        status: LaunchAtLoginClient.Status
    ) async {
        let store = TestStore(initialState: PreferencesFeature.State()) {
            PreferencesFeature()
        } withDependencies: {
            $0.launchAtLoginClient.setEnabled = { _ in }
            $0.launchAtLoginClient.status = { status }
        }

        await store.send(.setLaunchAtLogin(true)) {
            $0.isUpdatingLaunchAtLogin = true
        }
        await store.receive(\.launchAtLoginSucceeded) {
            $0.isUpdatingLaunchAtLogin = false
            $0.launchAtLoginStatus = status
        }
        #expect(!store.state.launchAtLogin)
    }

    @Test
    func setLaunchAtLogin_disable_readsActualStatus() async {
        var state = PreferencesFeature.State()
        state.launchAtLoginStatus = .enabled
        let store = TestStore(initialState: state) {
            PreferencesFeature()
        } withDependencies: {
            $0.launchAtLoginClient.setEnabled = { enabled in
                #expect(!enabled)
            }
            $0.launchAtLoginClient.status = { .notRegistered }
        }

        await store.send(.setLaunchAtLogin(false)) {
            $0.isUpdatingLaunchAtLogin = true
        }
        #expect(store.state.launchAtLogin)
        await store.receive(\.launchAtLoginSucceeded) {
            $0.isUpdatingLaunchAtLogin = false
            $0.launchAtLoginStatus = .notRegistered
        }
    }

    @Test
    func setLaunchAtLogin_pendingChangeIgnoresRapidToggleAndRefresh() async {
        let operation = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: PreferencesFeature.State()) {
            PreferencesFeature()
        } withDependencies: {
            $0.launchAtLoginClient.setEnabled = { enabled in
                #expect(enabled)
                for await _ in operation.stream {
                    return
                }
            }
            $0.launchAtLoginClient.status = { .enabled }
        }

        await store.send(.setLaunchAtLogin(true)) {
            $0.isUpdatingLaunchAtLogin = true
        }
        await store.send(.setLaunchAtLogin(false))
        await store.send(.refreshLaunchAtLogin)
        #expect(!store.state.launchAtLogin)

        operation.continuation.yield()
        operation.continuation.finish()
        await store.receive(\.launchAtLoginSucceeded) {
            $0.isUpdatingLaunchAtLogin = false
            $0.launchAtLoginStatus = .enabled
        }
        await store.finish()
    }

    @Test(arguments: [
        LaunchAtLoginClient.Status.enabled,
        .requiresApproval,
        .notRegistered,
        .notFound,
        .unavailable,
    ])
    func refreshLaunchAtLogin_readsExternalChangesWithoutRegistering(
        status: LaunchAtLoginClient.Status
    ) async {
        var state = PreferencesFeature.State()
        state.launchAtLoginError = "previous error"
        state.launchAtLoginStatus = .requiresApproval
        let store = TestStore(initialState: state) {
            PreferencesFeature()
        } withDependencies: {
            $0.launchAtLoginClient.status = { status }
            // setEnabled remains unimplemented: refresh must never change system settings.
        }

        if status == .requiresApproval {
            await store.send(.refreshLaunchAtLogin)
        } else {
            await store.send(.refreshLaunchAtLogin) {
                $0.launchAtLoginStatus = status
                $0.launchAtLoginError = nil
            }
        }
    }

    @Test
    func launchAtLoginCompletion_withoutPendingOperationIsIgnored() async {
        var state = PreferencesFeature.State()
        state.launchAtLoginStatus = .enabled
        let store = TestStore(initialState: state) {
            PreferencesFeature()
        }

        await store.send(.launchAtLoginSucceeded(.notRegistered))
        await store.send(.launchAtLoginFailed("old failure", .notFound))
    }

    // MARK: - AI Search Toggle

    @Test
    func setShowAISearch_savesAndNotifies() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveShowAISearch = { _ in }
        }

        await store.send(.setShowAISearch(false)) {
            $0.showAISearch = false
        }

        await store.receive(\.delegate.preferencesChanged)
    }




    @Test
    func setShowFilledBackground_savesAndNotifies() async {
        let store = TestStore(
            initialState: PreferencesFeature.State()
        ) {
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient.saveDisplayOptions = { _ in }
        }

        await store.send(.setShowFilledBackground(true)) {
            $0.displayOptions.showFilledBackground = true
        }

        await store.receive(\.delegate.displayOptionsChanged)
    }
}
