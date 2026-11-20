import ComposableArchitecture
import Foundation
import GlimpseCore
import Testing
@testable import Glimpse

/// Opening the AI editor prewarms one single-use on-device session; the first
/// submit consumes it and later requests always get a fresh one.
struct PrewarmedSessionSlotTests {
    private final class FakeSession: Sendable {}

    @Test
    func matchingTakeReturnsTheStoredSessionOnce() {
        let slot = PrewarmedSessionSlot<FakeSession>()
        let session = FakeSession()
        slot.store(session, instructions: "today")
        #expect(slot.take(instructions: "today") === session)
        #expect(slot.take(instructions: "today") == nil)
        #expect(slot.isEmpty)
    }

    @Test
    func mismatchedInstructionsAreDroppedNotReused() {
        let slot = PrewarmedSessionSlot<FakeSession>()
        slot.store(FakeSession(), instructions: "yesterday")
        #expect(slot.take(instructions: "today") == nil)
        #expect(slot.isEmpty)
    }

    @Test
    func discardEmptiesTheSlot() {
        let slot = PrewarmedSessionSlot<FakeSession>()
        slot.store(FakeSession(), instructions: "today")
        slot.discard()
        #expect(slot.take(instructions: "today") == nil)
    }

    @Test(arguments: [
        (AIDateHelper.Provider.foundationModels, true), (.onDeviceThenProxy, true), (.proxy, false), (.none, false),
    ])
    func onlyOnDeviceRoutesPrewarm(provider: AIDateHelper.Provider, expected: Bool) {
        #expect(AIDateHelper.usesOnDevice(provider) == expected)
    }
}

@MainActor
struct AIDateQueryModelPrewarmTests {
    private enum Call: Equatable { case prewarm(AIProvider), release }

    private func model(enabled: Bool = true, preference: AIProvider = .auto) -> (AIDateQueryModel, LockIsolated<[Call]>) {
        let calls = LockIsolated<[Call]>([])
        let client = AIDateQueryClient(
            resolveProvider: { _ in .proxy },
            interpret: { _, _ in nil },
            prewarm: { pref in calls.withValue { $0.append(.prewarm(pref)) } },
            releasePrewarm: { calls.withValue { $0.append(.release) } }
        )
        let model = AIDateQueryModel(client: client, enabled: enabled, preference: preference, onIntent: { _ in })
        model.setPanelVisible(true)
        return (model, calls)
    }

    @Test
    func openingTheEditorPrewarmsOnce() {
        let (model, calls) = model()
        model.setEditorOpen(true)
        model.setEditorOpen(true)
        #expect(calls.value == [.prewarm(.auto)])
    }

    @Test
    func disabledAIDoesNotPrewarm() {
        let (model, calls) = model(enabled: false)
        model.setEditorOpen(true)
        #expect(calls.value.isEmpty)
    }

    @Test
    func closingOrHidingReleasesTheSession() {
        let (model, calls) = model()
        model.setEditorOpen(true)
        model.setEditorOpen(false)
        model.setEditorOpen(false)
        #expect(calls.value == [.prewarm(.auto), .release])
        model.setEditorOpen(true)
        model.setPanelVisible(false)
        #expect(calls.value == [.prewarm(.auto), .release, .prewarm(.auto), .release])
    }

    @Test
    func providerChangeWhileOpenRewarmsForTheNewProvider() {
        let (model, calls) = model(preference: .proxy)
        model.setEditorOpen(true)
        model.synchronizeSettings(enabled: true, preference: .onDevice)
        model.synchronizeSettings(enabled: true, preference: .onDevice)
        #expect(calls.value == [.prewarm(.proxy), .release, .prewarm(.onDevice)])
    }
}
