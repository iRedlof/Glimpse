import Carbon
import Foundation
import Testing
@testable import Glimpse

@MainActor
struct GlobalHotkeyTests {
    private let original = HotkeyCombo(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey))
    private let replacement = HotkeyCombo(keyCode: 14, modifiers: UInt32(cmdKey | optionKey))

    @Test(arguments: [OSStatus(eventHotKeyExistsErr), OSStatus(-50)])
    func initialFailureDoesNotReportRegisteredOrPersist(status: OSStatus) {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        fixture.backend.registrationResults = [.init(status: status, hasReference: false)]
        let result = fixture.hotkey.register(combo: replacement) {}
        #expect(result.isFailure)
        #expect(!fixture.hotkey.isRegistered)
        #expect(fixture.hotkey.currentCombo == original)
        #expect(fixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.defaults.object(forKey: "hotkeyModifiers") == nil)
        #expect(fixture.backend.keys.isEmpty)
        #expect(fixture.backend.handlers.isEmpty)
    }

    @Test
    func successfulStatusWithoutKeyReferenceIsFailure() {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        fixture.backend.registrationResults = [.init(status: noErr, hasReference: false)]
        #expect(fixture.hotkey.register(combo: replacement) {}.failure == .missingHotkeyReference)
        #expect(!fixture.hotkey.isRegistered)
        #expect(fixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
    }

    @Test(arguments: [OSStatus(-50), OSStatus(noErr)])
    func handlerFailureCannotLeaveAnActiveHotkey(status: OSStatus) {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        fixture.backend.handlerResults = [.init(status: status, hasReference: false)]
        #expect(fixture.hotkey.register(combo: replacement) {}.isFailure)
        #expect(!fixture.hotkey.isRegistered)
        #expect(fixture.backend.keys.isEmpty)
        #expect(fixture.backend.handlers.isEmpty)
        #expect(fixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
    }

    @Test
    func replacementFailurePreservesRegistrationCallbackAndSavedCombo() throws {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        var originalCalls = 0
        var replacementCalls = 0
        #expect(fixture.hotkey.register(combo: original) { originalCalls += 1 }.isFailure == false)
        let oldKey = try #require(fixture.backend.keys.keys.first)
        let oldHandler = try #require(fixture.backend.handlers.keys.first)
        let oldEvent = try #require(fixture.backend.keys[oldKey]?.id)
        fixture.backend.registrationResults = [.init(status: OSStatus(eventHotKeyExistsErr), hasReference: false)]

        #expect(fixture.hotkey.register(combo: replacement) { replacementCalls += 1 }.isFailure)
        fixture.backend.deliver(oldEvent)

        #expect(fixture.hotkey.isRegistered)
        #expect(fixture.hotkey.currentCombo == original)
        #expect(fixture.backend.keys.keys.contains(oldKey))
        #expect(fixture.backend.handlers.keys.contains(oldHandler))
        #expect(HotkeyCombo.load(defaults: fixture.defaults) == original)
        #expect(originalCalls == 1)
        #expect(replacementCalls == 0)
    }

    @Test
    func sameComboRetainsNativeRegistrationAndUsesAcceptedCallback() throws {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        var firstCalls = 0
        var secondCalls = 0
        _ = fixture.hotkey.register(combo: original) { firstCalls += 1 }
        let oldKey = try #require(fixture.backend.keys.keys.first)
        let event = try #require(fixture.backend.keys[oldKey]?.id)
        let operationsBefore = fixture.backend.operations
        #expect(fixture.hotkey.register(combo: original) { secondCalls += 1 }.isFailure == false)
        fixture.backend.deliver(event)
        #expect(fixture.backend.operations == operationsBefore)
        #expect(fixture.backend.keys.count == 1)
        #expect(fixture.backend.keys.keys.contains(oldKey))
        #expect(firstCalls == 0)
        #expect(secondCalls == 1)
    }

    @Test
    func successfulReplacementPersistsOnlyAfterReleasingOldKey() throws {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        _ = fixture.hotkey.register(combo: original) {}
        let oldKey = try #require(fixture.backend.keys.keys.first)
        var savedAtRelease: HotkeyCombo?
        fixture.backend.onUnregister = { _ in
            savedAtRelease = HotkeyCombo.load(defaults: fixture.defaults)
        }
        #expect(fixture.hotkey.register(combo: replacement) {}.isFailure == false)
        #expect(savedAtRelease == original)
        #expect(fixture.hotkey.isRegistered)
        #expect(fixture.hotkey.currentCombo == replacement)
        #expect(!fixture.backend.keys.keys.contains(oldKey))
        #expect(fixture.backend.keys.count == 1)
        #expect(HotkeyCombo.load(defaults: fixture.defaults) == replacement)
    }

    @Test
    func oldKeyReleaseFailureRollsBackCandidateAndPreservesOldCallback() throws {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        var calls = 0
        _ = fixture.hotkey.register(combo: original) { calls += 1 }
        let oldKey = try #require(fixture.backend.keys.keys.first)
        let event = try #require(fixture.backend.keys[oldKey]?.id)
        fixture.backend.unregisterResults = [-50, noErr]
        #expect(fixture.hotkey.register(combo: replacement) {}.failure == .replacementRetirementFailed(-50))
        fixture.backend.deliver(event)
        #expect(fixture.hotkey.isRegistered)
        #expect(fixture.hotkey.currentCombo == original)
        #expect(fixture.backend.keys.count == 1)
        #expect(fixture.backend.keys.keys.contains(oldKey))
        #expect(HotkeyCombo.load(defaults: fixture.defaults) == original)
        #expect(calls == 1)
    }

    @Test
    func failedCandidateCleanupRemainsOwnedAndCanBeRetried() throws {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        _ = fixture.hotkey.register(combo: original) {}
        let oldKey = try #require(fixture.backend.keys.keys.first)
        fixture.backend.unregisterResults = [-50, -50]
        #expect(fixture.hotkey.register(combo: replacement) {}.isFailure)
        #expect(fixture.backend.keys.count == 2)
        #expect(fixture.hotkey.currentCombo == original)
        #expect(HotkeyCombo.load(defaults: fixture.defaults) == original)
        #expect(fixture.hotkey.unregister().isFailure == false)
        #expect(fixture.backend.keys.isEmpty)
        #expect(fixture.backend.handlers.isEmpty)
        #expect(!fixture.hotkey.isRegistered)
        #expect(fixture.backend.operations.contains(.unregister(oldKey)))
    }

    @Test
    func failedHandlerCleanupRemainsOwnedForRetry() {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        fixture.backend.registrationResults = [.init(status: -50, hasReference: false)]
        fixture.backend.removeHandlerResults = [-50]
        #expect(fixture.hotkey.register(combo: replacement) {}.isFailure)
        #expect(!fixture.hotkey.isRegistered)
        #expect(fixture.backend.handlers.count == 1)
        #expect(fixture.hotkey.unregister().isFailure == false)
        #expect(fixture.backend.handlers.isEmpty)
    }

    @Test
    func pendingCandidateCleanupBlocksNewTransactionsUntilRetrySucceeds() {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        _ = fixture.hotkey.register(combo: original) {}
        fixture.backend.unregisterResults = [-50, -50]
        #expect(fixture.hotkey.register(combo: replacement) {}.isFailure)
        let registrationCount = fixture.backend.operations.filter {
            if case .register = $0 { return true }
            return false
        }.count
        fixture.backend.unregisterResults = [-50]
        #expect(fixture.hotkey.register(combo: original) {}.isFailure)
        #expect(fixture.backend.operations.filter {
            if case .register = $0 { return true }
            return false
        }.count == registrationCount)
        #expect(fixture.hotkey.currentCombo == original)
        #expect(fixture.backend.keys.count == 2)
        #expect(fixture.hotkey.register(combo: original) {}.isFailure == false)
        #expect(fixture.backend.keys.count == 1)
    }

    @Test
    func failedNativeRegistrationReferenceIsRetainedWhenCleanupFails() {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        fixture.backend.registrationResults = [.init(status: -50, hasReference: true)]
        fixture.backend.unregisterResults = [-50]
        #expect(fixture.hotkey.register(combo: replacement) {}.isFailure)
        #expect(!fixture.hotkey.isRegistered)
        #expect(fixture.backend.keys.count == 1)
        #expect(fixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.hotkey.unregister().isFailure == false)
        #expect(fixture.backend.keys.isEmpty)
    }

    @Test
    func failedHandlerInstallationReferenceIsRetainedWhenCleanupFails() {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        fixture.backend.handlerResults = [.init(status: -50, hasReference: true)]
        fixture.backend.removeHandlerResults = [-50]
        #expect(fixture.hotkey.register(combo: replacement) {}.isFailure)
        #expect(!fixture.hotkey.isRegistered)
        #expect(fixture.backend.keys.isEmpty)
        #expect(fixture.backend.handlers.count == 1)
        #expect(fixture.defaults.object(forKey: "hotkeyKeyCode") == nil)
        #expect(fixture.hotkey.unregister().isFailure == false)
        #expect(fixture.backend.handlers.isEmpty)
    }

    @Test
    func disableFailureRetainsUsableKeyAndCallbackUntilRetry() throws {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        var calls = 0
        _ = fixture.hotkey.register(combo: original) { calls += 1 }
        let event = try #require(fixture.backend.keys.values.first?.id)
        fixture.backend.unregisterResults = [-50]
        #expect(fixture.hotkey.unregister().isFailure)
        #expect(fixture.hotkey.isRegistered)
        fixture.backend.deliver(event)
        #expect(calls == 1)
        #expect(fixture.hotkey.unregister().isFailure == false)
        let operationsAfter = fixture.backend.operations
        #expect(fixture.hotkey.unregister().isFailure == false)
        #expect(fixture.backend.operations == operationsAfter)
        #expect(!fixture.hotkey.isRegistered)
    }

    @Test
    func handlerRemovalFailureReportsFailureAndRetainsOwnedReference() {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        _ = fixture.hotkey.register(combo: original) {}
        fixture.backend.removeHandlerResults = [-50]
        #expect(fixture.hotkey.unregister().isFailure)
        #expect(!fixture.hotkey.isRegistered)
        #expect(fixture.backend.keys.isEmpty)
        #expect(fixture.backend.handlers.count == 1)
        #expect(fixture.hotkey.unregister().isFailure == false)
        #expect(fixture.backend.handlers.isEmpty)
    }

    @Test
    func queuedStaleAndForeignEventsCannotInvokeAcceptedCallback() throws {
        let fixture = HotkeyFixture()
        defer { fixture.cleanupDefaults() }
        var oldCalls = 0
        var newCalls = 0
        _ = fixture.hotkey.register(combo: original) { oldCalls += 1 }
        let oldEvent = try #require(fixture.backend.keys.values.first?.id)
        let queuedOldEvent = fixture.backend.queuedDelivery(oldEvent)
        _ = fixture.hotkey.register(combo: replacement) { newCalls += 1 }
        let newEvent = try #require(fixture.backend.keys.values.first?.id)
        #expect(newEvent != oldEvent)
        queuedOldEvent()
        fixture.backend.deliver(.init(signature: 0, id: newEvent.id))
        fixture.backend.deliver(newEvent)
        #expect(oldCalls == 0)
        #expect(newCalls == 1)
        let queuedBeforeDisable = fixture.backend.queuedDelivery(newEvent)
        _ = fixture.hotkey.unregister()
        queuedBeforeDisable()
        #expect(newCalls == 1)
        _ = fixture.hotkey.register(combo: replacement) { newCalls += 1 }
        queuedBeforeDisable()
        #expect(newCalls == 1)
    }
}

@MainActor
final class HotkeyFixture {
    let domain = "GlimpseTests.Hotkey.\(UUID().uuidString)"
    let defaults: UserDefaults
    let backend = FakeHotkeyBackend()
    let hotkey: GlobalHotkey

    init() {
        // A private suite keeps the running app's standard preference domain intact.
        defaults = UserDefaults(suiteName: domain)!
        hotkey = GlobalHotkey(backend: backend, defaults: defaults)
    }

    func cleanupDefaults() { defaults.removePersistentDomain(forName: domain) }
}

@MainActor
final class FakeHotkeyBackend: HotkeyBackend {
    struct Response {
        var status: OSStatus
        var hasReference: Bool
    }
    enum Operation: Equatable {
        case register(HotkeyCombo, HotkeyEventID)
        case install
        case unregister(EventHotKeyRef)
        case remove(EventHandlerRef)
    }
    var registrationResults: [Response] = []
    var handlerResults: [Response] = []
    var unregisterResults: [OSStatus] = []
    var removeHandlerResults: [OSStatus] = []
    var keys: [EventHotKeyRef: (combo: HotkeyCombo, id: HotkeyEventID)] = [:]
    var handlers: [EventHandlerRef: (HotkeyEventID) -> Void] = [:]
    var operations: [Operation] = []
    var onUnregister: ((EventHotKeyRef) -> Void)?
    private var nextReference = 1

    func register(combo: HotkeyCombo, id: HotkeyEventID) -> HotkeyNativeResult<EventHotKeyRef> {
        operations.append(.register(combo, id))
        let response = registrationResults.isEmpty
            ? Response(status: noErr, hasReference: true) : registrationResults.removeFirst()
        let reference = response.hasReference ? makeReference() : nil
        if let reference { keys[reference] = (combo, id) }
        return .init(status: response.status, reference: reference)
    }

    func installHandler(_ receive: @escaping (HotkeyEventID) -> Void) -> HotkeyNativeResult<EventHandlerRef> {
        operations.append(.install)
        let response = handlerResults.isEmpty
            ? Response(status: noErr, hasReference: true) : handlerResults.removeFirst()
        let reference = response.hasReference ? makeReference() : nil
        if let reference { handlers[reference] = receive }
        return .init(status: response.status, reference: reference)
    }

    func unregister(_ reference: EventHotKeyRef) -> OSStatus {
        operations.append(.unregister(reference))
        onUnregister?(reference)
        let status = unregisterResults.isEmpty ? noErr : unregisterResults.removeFirst()
        if status == noErr { keys.removeValue(forKey: reference) }
        return status
    }

    func removeHandler(_ reference: EventHandlerRef) -> OSStatus {
        operations.append(.remove(reference))
        let status = removeHandlerResults.isEmpty ? noErr : removeHandlerResults.removeFirst()
        if status == noErr { handlers.removeValue(forKey: reference) }
        return status
    }

    func deliver(_ id: HotkeyEventID) {
        for callback in handlers.values { callback(id) }
    }

    func queuedDelivery(_ id: HotkeyEventID) -> () -> Void {
        let callbacks = Array(handlers.values)
        return { for callback in callbacks { callback(id) } }
    }

    private func makeReference() -> OpaquePointer {
        defer { nextReference += 1 }
        // Fake tokens are never passed to Carbon; only this backend owns them.
        return OpaquePointer(bitPattern: nextReference)!
    }
}

extension Result where Success == Void {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
