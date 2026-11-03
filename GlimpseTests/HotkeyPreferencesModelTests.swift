import Carbon
import Observation
import Testing
@testable import Glimpse

@MainActor
struct HotkeyPreferencesModelTests {
    private let replacement = HotkeyCombo(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))

    @Test
    func failedEnableShowsActualOffAndDoesNotSaveSuccessfulIntent() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.hotkeyFixture.defaults.set(false, forKey: "hotkeyEnabled")
        fixture.hotkeyFixture.backend.registrationResults = [.init(status: -50, hasReference: false)]
        fixture.model.setEnabled(true)
        #expect(!fixture.model.isEnabled)
        #expect(!fixture.model.isRequested)
        #expect(fixture.model.errorMessage != nil)
    }

    @Test
    func startupFailureKeepsSavedIntentAndIsVisibleOnPreferencesReopen() {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        fixture.defaults.set(true, forKey: "hotkeyEnabled")
        fixture.backend.registrationResults = [.init(status: -50, hasReference: false)]
        _ = fixture.hotkey.register(combo: .default) {}
        let firstView = HotkeyPreferencesModel(hotkey: fixture.hotkey, defaults: fixture.defaults) {}
        let reopenedView = HotkeyPreferencesModel(hotkey: fixture.hotkey, defaults: fixture.defaults) {}
        #expect(firstView.isRequested)
        #expect(!firstView.isEnabled)
        #expect(firstView.errorMessage != nil)
        #expect(reopenedView.isRequested)
        #expect(!reopenedView.isEnabled)
        #expect(reopenedView.errorMessage != nil)
        #expect(fixture.defaults.bool(forKey: "hotkeyEnabled"))
    }

    @Test(arguments: [false, true])
    func failedStartupCanBeKeptOffWithoutHidingPendingCleanup(failedCleanup: Bool) {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.hotkeyFixture.defaults.set(true, forKey: "hotkeyEnabled")
        fixture.hotkeyFixture.backend.registrationResults = [.init(status: -50, hasReference: false)]
        if failedCleanup { fixture.hotkeyFixture.backend.removeHandlerResults = [-50, -50] }
        _ = fixture.hotkeyFixture.hotkey.register(combo: .default) {}
        #expect(fixture.model.isRequested)
        #expect(!fixture.model.isEnabled)
        fixture.model.setEnabled(false)
        #expect(!fixture.model.isEnabled)
        #expect(!fixture.model.isRequested)
        #expect(fixture.model.displayedCombo == .default)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect((fixture.model.errorMessage != nil) == failedCleanup)
        if failedCleanup {
            #expect(fixture.hotkeyFixture.backend.handlers.count == 1)
            fixture.model.setEnabled(false)
            #expect(fixture.model.errorMessage == nil)
            #expect(fixture.hotkeyFixture.backend.handlers.isEmpty)
        }
    }

    @Test
    func failedRecordingKeepsWorkingShortcutAndRecorderOpenUntilRetry() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.setEnabled(true)
        fixture.model.beginRecording(using: fixture.monitor.client)
        fixture.hotkeyFixture.backend.registrationResults = [
            .init(status: OSStatus(eventHotKeyExistsErr), hasReference: false)
        ]
        #expect(fixture.monitor.send(.init(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))))
        #expect(fixture.model.isRecording)
        #expect(fixture.model.recordingError == .registration(.conflict))
        #expect(fixture.model.displayedCombo == .default)
        #expect(HotkeyCombo.load(defaults: fixture.hotkeyFixture.defaults) == .default)
        #expect(fixture.model.isEnabled)
        #expect(fixture.monitor.notifications == [true])

        #expect(fixture.monitor.send(.init(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))))
        #expect(!fixture.model.isRecording)
        #expect(fixture.model.displayedCombo == replacement)
        #expect(fixture.model.isEnabled)
        #expect(fixture.model.isRequested)
        #expect(HotkeyCombo.load(defaults: fixture.hotkeyFixture.defaults) == replacement)
        #expect(fixture.monitor.notifications == [true, false])
        #expect(fixture.monitor.removalCount == 1)
    }

    @Test
    func inactiveRecorderEnablesOnlyAcceptedCombo() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.hotkeyFixture.defaults.set(false, forKey: "hotkeyEnabled")
        fixture.model.beginRecording(using: fixture.monitor.client)
        #expect(fixture.monitor.send(.init(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))))
        #expect(fixture.model.isEnabled)
        #expect(fixture.model.isRequested)
        #expect(fixture.model.displayedCombo == replacement)
        #expect(!fixture.model.isRecording)
    }

    @Test
    func inactiveFailedRecordingPreservesSavedOffAndAbsentComboKeys() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.hotkeyFixture.defaults.set(false, forKey: "hotkeyEnabled")
        fixture.hotkeyFixture.backend.registrationResults = [.init(status: -50, hasReference: false)]
        fixture.model.beginRecording(using: fixture.monitor.client)
        #expect(fixture.monitor.send(.init(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))))
        #expect(!fixture.model.isEnabled)
        #expect(!fixture.model.isRequested)
        #expect(fixture.model.isRecording)
        #expect(fixture.model.displayedCombo == .default)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyModifiers") == nil)
        #expect(fixture.model.recordingError == .registration(.registrationFailed(-50)))
    }

    @Test
    func reservedShortcutDoesNotReachCarbonOrPersist() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        let originalOperations = fixture.hotkeyFixture.backend.operations
        fixture.model.beginRecording(using: fixture.monitor.client)
        #expect(fixture.monitor.send(.init(keyCode: 12, modifiers: UInt32(cmdKey))))
        #expect(fixture.model.isRecording)
        #expect(fixture.model.recordingError == .reserved(
            HotkeyCombo(keyCode: 12, modifiers: UInt32(cmdKey))
        ))
        #expect(fixture.hotkeyFixture.backend.operations == originalOperations)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyEnabled") == nil)
    }

    @Test
    func settingsCommandCannotReplaceTheGlobalShortcut() {
        let fixture = HotkeyModelFixture()
        defer {
            fixture.model.cancelRecording()
            fixture.hotkeyFixture.cleanupDefaults()
        }
        fixture.model.beginRecording(using: fixture.monitor.client)

        #expect(fixture.monitor.send(.init(keyCode: 43, modifiers: UInt32(cmdKey))))
        #expect(fixture.model.isRecording)
        #expect(fixture.model.recordingError == .reserved(
            HotkeyCombo(keyCode: 43, modifiers: UInt32(cmdKey))
        ))
        #expect(fixture.model.displayedCombo == .default)
        #expect(fixture.hotkeyFixture.backend.operations.isEmpty)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyModifiers") == nil)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyEnabled") == nil)
    }

    @Test
    func cancelHideAndDisappearAreIdempotentWithoutPreferenceChanges() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.beginRecording(using: fixture.monitor.client)
        fixture.model.beginRecording(using: fixture.monitor.client)
        fixture.model.cancelRecording()
        // Both panel hide and view disappearance use this same cancellation path.
        fixture.model.cancelRecording()
        fixture.model.cancelRecording()
        #expect(!fixture.model.isRecording)
        #expect(fixture.monitor.installationCount == 1)
        #expect(fixture.monitor.removalCount == 1)
        #expect(fixture.monitor.notifications == [true, false])
        #expect(fixture.hotkeyFixture.backend.operations.isEmpty)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyEnabled") == nil)
    }

    @Test
    func escapeCancelsAndConsumesOnlyTheOwnedEvent() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.beginRecording(using: fixture.monitor.client)
        #expect(!fixture.monitor.send(.init(keyCode: 53, modifiers: 0, eventIsForOwner: false)))
        #expect(fixture.model.isRecording)
        #expect(fixture.monitor.send(.init(keyCode: 53, modifiers: 0)))
        #expect(!fixture.model.isRecording)
        #expect(fixture.monitor.notifications == [true, false])
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
    }

    @Test
    func foreignHiddenNonkeyAndUnmodifiedEventsPassThrough() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.beginRecording(using: fixture.monitor.client)
        let inputs: [HotkeyRecordingInput] = [
            .init(keyCode: 14, modifiers: UInt32(cmdKey), eventIsForOwner: false),
            .init(keyCode: 14, modifiers: UInt32(cmdKey), ownerIsVisible: false),
            .init(keyCode: 14, modifiers: UInt32(cmdKey), ownerIsKey: false),
            .init(keyCode: 14, modifiers: 0),
        ]
        for input in inputs { #expect(!fixture.monitor.send(input)) }
        #expect(fixture.model.isRecording)
        #expect(fixture.hotkeyFixture.backend.operations.isEmpty)
        #expect(fixture.hotkeyFixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
        fixture.model.cancelRecording()
    }

    @Test
    func disableCancelsRecorderAndSavesOffBeforeNativeTeardown() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.setEnabled(true)
        fixture.model.beginRecording(using: fixture.monitor.client)
        var intentAtUnregister: Bool?
        fixture.hotkeyFixture.backend.onUnregister = { _ in
            intentAtUnregister = fixture.hotkeyFixture.defaults.bool(forKey: "hotkeyEnabled")
        }
        fixture.model.setEnabled(false)
        #expect(intentAtUnregister == false)
        #expect(!fixture.model.isRecording)
        #expect(!fixture.model.isEnabled)
        #expect(!fixture.model.isRequested)
        #expect(fixture.monitor.notifications == [true, false])
        #expect(fixture.monitor.removalCount == 1)
    }

    @Test
    func failedDisableKeepsActualOnButSavesExplicitOffIntent() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.setEnabled(true)
        fixture.hotkeyFixture.backend.unregisterResults = [-50]
        fixture.model.setEnabled(false)
        #expect(fixture.model.isEnabled)
        #expect(!fixture.model.isRequested)
        #expect(fixture.model.errorMessage != nil)
        fixture.model.setEnabled(false)
        #expect(!fixture.model.isEnabled)
        #expect(!fixture.model.isRequested)
    }

    @Test
    func unavailableMonitorDoesNotStartOrNotifyRecording() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.monitor.canInstall = false
        fixture.model.beginRecording(using: fixture.monitor.client)
        #expect(!fixture.model.isRecording)
        #expect(fixture.model.recordingError == .monitorUnavailable)
        #expect(fixture.monitor.notifications.isEmpty)
        #expect(fixture.hotkeyFixture.backend.operations.isEmpty)
    }

    @Test(arguments: [
        (OSStatus(eventHotKeyExistsErr), true,
         "That shortcut is already in use. Choose another combination. Your previous shortcut still works."),
        (OSStatus(eventHotKeyExistsErr), false,
         "That shortcut is already in use. Choose another combination."),
        (OSStatus(-50), true,
         "Glimpse couldn’t use that shortcut. Try another combination. Your previous shortcut still works."),
        (OSStatus(-50), false,
         "Glimpse couldn’t enable this shortcut. Try again or choose another combination."),
    ])
    func recordingFailureCopyReflectsWhetherPreviousShortcutRemainsUsable(
        status: OSStatus, previousIsUsable: Bool, message: String
    ) {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.hotkeyFixture.defaults.set(false, forKey: "hotkeyEnabled")
        if previousIsUsable { fixture.model.setEnabled(true) }
        fixture.model.beginRecording(using: fixture.monitor.client)
        fixture.hotkeyFixture.backend.registrationResults = [.init(status: status, hasReference: false)]
        #expect(fixture.monitor.send(.init(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))))
        #expect(fixture.model.isRecording)
        #expect(fixture.model.isEnabled == previousIsUsable)
        #expect(fixture.model.errorMessage == message)
        #expect(fixture.monitor.send(.init(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))))
        #expect(fixture.model.isEnabled)
        #expect(!fixture.model.isRecording)
        #expect(fixture.model.errorMessage == nil)
    }

    @Test(arguments: [false, true])
    func disableCopySeparatesUsableShortcutFromUnconfirmedHandlerCleanup(handlerCleanupFails: Bool) {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.setEnabled(true)
        if handlerCleanupFails {
            fixture.hotkeyFixture.backend.removeHandlerResults = [-50]
        } else {
            fixture.hotkeyFixture.backend.unregisterResults = [-50]
        }
        fixture.model.setEnabled(false)
        #expect(fixture.model.isEnabled == !handlerCleanupFails)
        #expect(fixture.model.errorMessage == (handlerCleanupFails
            ? "Glimpse couldn’t confirm the shortcut’s status. Try again."
            : "Glimpse couldn’t turn off this shortcut. Try again."))
    }

    @Test
    func candidateRollbackCleanupDoesNotPromiseThatStatusIsConfirmed() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.setEnabled(true)
        fixture.model.beginRecording(using: fixture.monitor.client)
        fixture.hotkeyFixture.backend.unregisterResults = [-50, -50]
        #expect(fixture.monitor.send(.init(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))))
        #expect(fixture.model.isEnabled)
        #expect(fixture.model.isRecording)
        #expect(fixture.model.errorMessage == "Glimpse couldn’t confirm the shortcut’s status. Try again.")
    }

    @Test
    func replacementRetirementFailurePreservesWorkingStateAndCopyAfterCancellation() throws {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.setEnabled(true)
        let oldKey = try #require(fixture.hotkeyFixture.backend.keys.keys.first)
        let oldHandler = try #require(fixture.hotkeyFixture.backend.handlers.keys.first)
        let savedCombo = HotkeyCombo.load(defaults: fixture.hotkeyFixture.defaults)
        fixture.model.beginRecording(using: fixture.monitor.client)
        fixture.hotkeyFixture.backend.unregisterResults = [-50, noErr]

        #expect(fixture.monitor.send(.init(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))))
        #expect(fixture.model.isRecording)
        #expect(fixture.model.isEnabled)
        #expect(fixture.model.isRequested)
        #expect(fixture.hotkeyFixture.defaults.bool(forKey: "hotkeyEnabled"))
        #expect(fixture.model.displayedCombo == savedCombo)
        #expect(HotkeyCombo.load(defaults: fixture.hotkeyFixture.defaults) == savedCombo)
        #expect(Array(fixture.hotkeyFixture.backend.keys.keys) == [oldKey])
        #expect(Array(fixture.hotkeyFixture.backend.handlers.keys) == [oldHandler])
        let message = "Glimpse couldn’t use that shortcut. Try another combination. Your previous shortcut still works."
        #expect(fixture.model.errorMessage == message)

        fixture.model.cancelRecording()
        #expect(!fixture.model.isRecording)
        #expect(fixture.model.isEnabled)
        #expect(fixture.model.isRequested)
        #expect(fixture.model.errorMessage == message)
        let reopened = HotkeyPreferencesModel(
            hotkey: fixture.hotkeyFixture.hotkey, defaults: fixture.hotkeyFixture.defaults
        ) {}
        #expect(reopened.errorMessage == message)
        #expect(fixture.monitor.notifications == [true, false])
        #expect(fixture.monitor.removalCount == 1)
    }

    @Test
    func reservedAndUnavailableCaptureCopyOfferTheApplicableRecovery() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.model.beginRecording(using: fixture.monitor.client)
        #expect(fixture.monitor.send(.init(keyCode: 12, modifiers: UInt32(cmdKey))))
        #expect(fixture.model.errorMessage == "⌘Q is a reserved shortcut. Choose another combination.")
        fixture.model.cancelRecording()
        fixture.monitor.canInstall = false
        fixture.model.beginRecording(using: fixture.monitor.client)
        #expect(!fixture.model.isRecording)
        #expect(fixture.model.errorMessage == "Glimpse couldn’t record a shortcut. Try again.")
    }

    @Test
    func intentOnlyOptOutNotifiesViewWhenRepeatedCleanupErrorIsUnchanged() {
        let fixture = HotkeyModelFixture()
        defer { fixture.hotkeyFixture.cleanupDefaults() }
        fixture.hotkeyFixture.defaults.set(true, forKey: "hotkeyEnabled")
        fixture.hotkeyFixture.backend.registrationResults = [.init(status: -50, hasReference: false)]
        fixture.hotkeyFixture.backend.removeHandlerResults = [-50, -50, -50]
        _ = fixture.hotkeyFixture.hotkey.register(combo: .default) {}
        // First teardown changes handlerRemovalFailed to cleanupFailed. Observe
        // the next identical failure, where only the persisted intent changes.
        _ = fixture.hotkeyFixture.hotkey.unregister()
        let model = fixture.model
        let observer = HotkeyObservationCounter()
        withObservationTracking {
            _ = model.isRequested
            _ = model.isEnabled
            _ = model.isRecording
            _ = model.displayedCombo
            _ = model.errorMessage
        } onChange: {
            MainActor.assumeIsolated { observer.notifications += 1 }
        }
        model.setEnabled(false)
        #expect(observer.notifications == 1)
        #expect(!model.isRequested)
        #expect(!model.isEnabled)
        #expect(model.errorMessage != nil)
        #expect(fixture.hotkeyFixture.defaults.bool(forKey: "hotkeyEnabled") == false)
        #expect(fixture.hotkeyFixture.backend.handlers.count == 1)
    }
}

@MainActor
final class HotkeyObservationCounter {
    var notifications = 0
}

@MainActor
final class HotkeyModelFixture {
    let hotkeyFixture = HotkeyFixture()
    let monitor = FakeRecordingMonitor()
    lazy var model = HotkeyPreferencesModel(
        hotkey: hotkeyFixture.hotkey, defaults: hotkeyFixture.defaults
    ) {}
}

@MainActor
final class FakeRecordingMonitor {
    var canInstall = true
    var installationCount = 0
    var removalCount = 0
    var notifications: [Bool] = []
    private var receive: ((HotkeyRecordingInput) -> Bool)?

    var client: HotkeyRecordingClient {
        .init(
            install: { receive in
                self.installationCount += 1
                guard self.canInstall else { return nil }
                self.receive = receive
                return "fixture-monitor"
            },
            remove: { _ in self.removalCount += 1; self.receive = nil },
            didChange: { self.notifications.append($0) }
        )
    }

    func send(_ input: HotkeyRecordingInput) -> Bool { receive?(input) ?? false }
}
