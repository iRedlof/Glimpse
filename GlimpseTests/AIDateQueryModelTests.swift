import ComposableArchitecture
import Foundation
import GlimpseCore
import Testing

@testable import Glimpse

/// Production request owner with synthetic asynchronous provider work only.
/// No app/window, storage, live client or provider configuration is constructed.
@Suite(.serialized)
@MainActor
struct AIDateQueryModelTests {
    enum CurrentOutcome: String, CaseIterable, Sendable {
        case date, noDate, operationalFailure, unavailable, providerCancellation

        var result: Result<Date?, any Error> {
            switch self {
            case .date: .success(AIDateModelFixture.dateA)
            case .noDate: .success(nil)
            case .operationalFailure: .failure(AIDateFailure.transport)
            case .unavailable: .failure(AIDateFailure.unavailable)
            case .providerCancellation: .failure(CancellationError())
            }
        }

        var expectedMessage: String? {
            switch self {
            case .date, .providerCancellation: nil
            case .noDate:
                "AI didn't return a usable date. Try ‘next Friday’ or ‘Jan 2028’."
            case .operationalFailure:
                "AI couldn't complete the date search. Try again."
            case .unavailable:
                "On-device AI is unavailable. Choose Cloud AI in Preferences."
            }
        }
    }

    enum RevisionInput: String, CaseIterable, Sendable {
        case draftChange, draftRoundTrip, providerChange, providerRoundTrip, autoCloudRoundTrip
    }

    enum DiscardInput: String, CaseIterable, Sendable {
        case dismiss, escape, editorBindingClose, hide, actualRemoval, disable
    }

    enum LateOutcome: String, CaseIterable, Sendable {
        case date, failure, noDate, cancellation

        var result: Result<Date?, any Error> {
            switch self {
            case .date: .success(AIDateModelFixture.dateA)
            case .failure: .failure(AIDateFailure.onDeviceRequest)
            case .noDate: .success(nil)
            case .cancellation: .failure(CancellationError())
            }
        }
    }

    // Removing classification/retention or publishing a failure as a date breaks this.
    @Test(arguments: CurrentOutcome.allCases)
    func currentOutcomesRetainDraftOrPublishOnce(outcome: CurrentOutcome) async throws {
        try await withFixture { fixture in
            let tracked = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            #expect(fixture.model.isProcessing)
            #expect(fixture.model.errorMessage == nil)
            await request.release(outcome.result)
            try await tracked.finished.wait()
            #expect(request.returnCount.value == 1)
            #expect(!fixture.model.isProcessing)
            #expect(fixture.model.currentRequestID == nil)
            #expect(fixture.model.errorMessage == outcome.expectedMessage)

            if outcome == .date {
                #expect(fixture.receipts.dates == [AIDateModelFixture.dateA])
                #expect(fixture.model.draft == "")
                #expect(!fixture.model.isEditorOpen)
            } else {
                #expect(fixture.receipts.dates.isEmpty)
                #expect(fixture.model.draft == "fixture draft A")
                #expect(fixture.model.isEditorOpen)
                let initialCount = await fixture.requests.count
                #expect(initialCount == 1)
                let resubmission = try fixture.submitRequired()
                let secondRequest = try await fixture.enteredRequest(at: 1)
                await secondRequest.release(.success(AIDateModelFixture.dateB))
                try await resubmission.finished.wait()
                #expect(fixture.receipts.dates == [AIDateModelFixture.dateB])
                let finalCount = await fixture.requests.count
                #expect(finalCount == 2)
            }
        }
    }

    // Missing owned-context validation or allowing a second active submission breaks this.
    @Test
    func submitEligibilityAndDoubleSubmit() async throws {
        for context in ["hidden", "disabled", "closed"] {
            try await withFixture { fixture in
                switch context {
                case "hidden": fixture.model.setPanelVisible(false)
                case "disabled":
                    fixture.model.synchronizeSettings(enabled: false, preference: .auto)
                default: fixture.model.setEditorOpen(false)
                }
                // A synthetic direct setter retains a nonempty input even if closed.
                // The owner must still reject it based on context.
                fixture.model.setDraft("fixture draft A")
                let rejected = fixture.submit()
                #expect(rejected == nil)
                #expect(!fixture.model.isProcessing)
                #expect(fixture.model.currentRequestID == nil)
            }
        }

        try await withFixture { fixture in
            let first = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            let firstID = fixture.model.currentRequestID
            #expect(fixture.submit() == nil)
            #expect(fixture.model.currentRequestID == firstID)
            let requestCount = await fixture.requests.count
            #expect(requestCount == 1)
            await request.release(.success(nil))
            try await first.finished.wait()
        }
    }

    // Delayed invalidation or comparing only final draft/effective provider breaks this.
    @Test(arguments: RevisionInput.allCases)
    func editAndPreferenceRoundTripsInvalidate(input: RevisionInput) async throws {
        try await withFixture { fixture in
            let first = try fixture.submitRequired()
            let requestA = try await fixture.enteredRequest(at: 0)
            let expectedDraft: String
            switch input {
            case .draftChange:
                fixture.model.setDraft("fixture draft B")
                expectedDraft = "fixture draft B"
            case .draftRoundTrip:
                fixture.model.setDraft("fixture draft B")
                fixture.model.setDraft("fixture draft A")
                expectedDraft = "fixture draft A"
            case .providerChange:
                fixture.model.synchronizeSettings(enabled: true, preference: .onDevice)
                expectedDraft = "fixture draft A"
            case .providerRoundTrip:
                fixture.model.synchronizeSettings(enabled: true, preference: .onDevice)
                fixture.model.synchronizeSettings(enabled: true, preference: .auto)
                expectedDraft = "fixture draft A"
            case .autoCloudRoundTrip:
                fixture.model.synchronizeSettings(enabled: true, preference: .proxy)
                fixture.model.synchronizeSettings(enabled: true, preference: .auto)
                expectedDraft = "fixture draft A"
            }
            // These assertions run synchronously, before another MainActor await.
            #expect(!fixture.model.isProcessing)
            #expect(fixture.model.currentRequestID == nil)
            #expect(fixture.model.errorMessage == nil)
            #expect(fixture.model.draft == expectedDraft)
            #expect(fixture.model.isEditorOpen)

            let second = fixture.submit()
            #expect(second != nil)
            if let second {
                let requestB = try await fixture.enteredRequest(at: 1)
                let secondID = fixture.model.currentRequestID
                await requestA.release(.success(AIDateModelFixture.dateA))
                try await first.finished.wait()
                #expect(fixture.model.currentRequestID == secondID)
                #expect(fixture.model.isProcessing)
                #expect(fixture.model.draft == expectedDraft)
                #expect(fixture.receipts.dates.isEmpty)
                await requestB.release(.success(AIDateModelFixture.dateB))
                try await second.finished.wait()
                #expect(fixture.receipts.dates == [AIDateModelFixture.dateB])
            } else {
                // A failed eligibility assertion must not lead to a nonexistent
                // request wait or leave the real old worker gated.
                await requestA.release(.success(AIDateModelFixture.dateA))
                try await first.finished.wait()
                #expect(fixture.receipts.dates.isEmpty)
            }
        }
    }

    // Omitting cancel/clear on a model discard boundary breaks this.
    // Escape/removal here are model boundaries; native wiring is Task 3.
    @Test(arguments: DiscardInput.allCases)
    func discardHideDisableAndReopenInvalidate(input: DiscardInput) async throws {
        try await withFixture { fixture in
            let first = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            switch input {
            case .dismiss, .escape: fixture.model.discardEditor()
            case .editorBindingClose: fixture.model.setEditorOpen(false)
            case .hide, .actualRemoval: fixture.model.setPanelVisible(false)
            case .disable:
                fixture.model.synchronizeSettings(enabled: false, preference: .auto)
            }
            #expect(fixture.model.currentRequestID == nil)
            #expect(!fixture.model.isProcessing)
            #expect(fixture.model.draft == "")
            #expect(!fixture.model.isEditorOpen)
            #expect(fixture.model.errorMessage == nil)
            await request.release(.success(AIDateModelFixture.dateA))
            try await first.finished.wait()
            #expect(fixture.receipts.dates.isEmpty)

            fixture.model.synchronizeSettings(enabled: true, preference: .auto)
            fixture.model.setPanelVisible(true)
            fixture.model.setEditorOpen(true)
            fixture.model.setDraft("fixture draft B")
            let second = try fixture.submitRequired()
            let requestB = try await fixture.enteredRequest(at: 1)
            await requestB.release(.success(AIDateModelFixture.dateB))
            try await second.finished.wait()
            #expect(fixture.receipts.dates == [AIDateModelFixture.dateB])
        }
    }

    // A stale result clearing another handle/spinner/draft/error or navigating breaks this.
    @Test(arguments: LateOutcome.allCases)
    func obsoleteCompletionCannotAffectNewRequest(outcome: LateOutcome) async throws {
        try await withFixture { fixture in
            let first = try fixture.submitRequired()
            let requestA = try await fixture.enteredRequest(at: 0)
            let firstID = fixture.model.currentRequestID
            fixture.model.setPanelVisible(false)
            fixture.model.setPanelVisible(true)
            fixture.model.setEditorOpen(true)
            fixture.model.setDraft("fixture draft B")
            let second = try fixture.submitRequired()
            let requestB = try await fixture.enteredRequest(at: 1)
            let secondID = fixture.model.currentRequestID
            #expect(secondID != firstID)
            await requestA.release(outcome.result)
            try await requestA.returned.wait()
            try await first.finished.wait()
            #expect(requestA.returnCount.value == 1)
            #expect(requestB.returnCount.value == 0)
            #expect(fixture.model.currentRequestID == secondID)
            #expect(fixture.model.isProcessing)
            #expect(fixture.model.draft == "fixture draft B")
            #expect(fixture.model.isEditorOpen)
            #expect(fixture.model.errorMessage == nil)
            #expect(fixture.receipts.dates.isEmpty)
            #expect(fixture.submit() == nil)
            await requestB.release(.success(AIDateModelFixture.dateB))
            try await second.finished.wait()
            #expect(fixture.receipts.dates == [AIDateModelFixture.dateB])
        }
    }

    // Canceling a waiter must not complete the actual request/drain obligation.
    @Test
    func canceledObserverDoesNotCompleteWorker() async throws {
        try await withFixture { fixture in
            let tracked = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            let installed: AIDateModelSignal<Void> = fixture.signal("completion observer installed")
            let observerExited: AIDateModelSignal<Void> = fixture.signal("canceled observer exited")
            let observer = Task {
                do {
                    try await tracked.finished.wait {
                        installed.resolve(.success(()))
                    }
                    Issue.record("Canceled observer unexpectedly received producer completion.")
                } catch is CancellationError {
                    observerExited.resolve(.success(()))
                } catch {
                    observerExited.resolve(.failure(error))
                }
            }
            fixture.trackObserver(observer)
            try await installed.wait()
            observer.cancel()
            try await observerExited.wait()
            await observer.value
            #expect(request.returnCount.value == 0)
            #expect(!tracked.finished.isResolved)
            #expect(!request.returned.isResolved)
            await request.release(.success(AIDateModelFixture.dateA))
            try await request.returned.wait()
            try await tracked.finished.wait()
            // A fresh observer sees the durable real Task.value acknowledgement.
            try await tracked.finished.wait()
            #expect(request.returnCount.value == 1)
            #expect(fixture.receipts.dates == [AIDateModelFixture.dateA])
        }
    }

    // Resetting on same visible state or unchanged preferences breaks a valid request.
    @Test
    func sameVisibleShowAndUnchangedSettingsPreserveRequest() async throws {
        try await withFixture { fixture in
            let tracked = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            let requestID = fixture.model.currentRequestID
            fixture.model.setPanelVisible(true)
            fixture.model.setPanelVisible(true)
            fixture.model.synchronizeSettings(enabled: true, preference: .auto)
            #expect(fixture.model.currentRequestID == requestID)
            #expect(fixture.model.isProcessing)
            #expect(fixture.model.draft == "fixture draft A")
            #expect(request.cancelCount.value == 0)
            await request.release(.success(AIDateModelFixture.dateA))
            try await tracked.finished.wait()
            #expect(fixture.receipts.dates == [AIDateModelFixture.dateA])
        }
    }

    // Publishing date before relinquishing current ownership makes a synchronous
    // consumer see mixed state or loses a newly submitted request during cleanup.
    @Test
    func atomicCompletionRelinquishesOwnershipBeforeDateCallback() async throws {
        try await withFixture { fixture in
            var next: AIDateModelTrackedTask?
            fixture.receipts.onDate = { date in
                guard date == AIDateModelFixture.dateA else { return }
                #expect(fixture.model.currentRequestID == nil)
                #expect(!fixture.model.isProcessing)
                #expect(fixture.model.draft == "")
                #expect(!fixture.model.isEditorOpen)
                fixture.model.setEditorOpen(true)
                fixture.model.setDraft("fixture draft B")
                next = fixture.submit()
                #expect(next != nil)
            }
            let first = try fixture.submitRequired()
            let requestA = try await fixture.enteredRequest(at: 0)
            await requestA.release(.success(AIDateModelFixture.dateA))
            try await first.finished.wait()
            let second = try #require(next)
            let requestB = try await fixture.enteredRequest(at: 1)
            let secondID = fixture.model.currentRequestID
            #expect(secondID != nil)
            #expect(fixture.model.isProcessing)
            #expect(fixture.model.draft == "fixture draft B")
            await requestB.release(.success(AIDateModelFixture.dateB))
            try await second.finished.wait()
            #expect(fixture.receipts.dates == [AIDateModelFixture.dateA, AIDateModelFixture.dateB])
        }
    }

    // Cancel-first abandonment exposes the old owner to synchronous cancellation code.
    @Test
    func clearOwnershipBeforeCancelHandlerRuns() async throws {
        try await withFixture { fixture in
            let snapshots = LockIsolated<[AIDateModelOwnershipSnapshot]>([])
            let armed = LockIsolated(false)
            fixture.requests.setCancellationObservation {
                guard armed.value else { return }
                guard Thread.isMainThread else {
                    Issue.record("Cancellation snapshot did not run in the initiating MainActor call.")
                    return
                }
                MainActor.assumeIsolated {
                    let snapshot = AIDateModelOwnershipSnapshot(fixture.model)
                    snapshots.withValue { $0.append(snapshot) }
                }
            }
            let tracked = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            armed.setValue(true)
            fixture.model.setPanelVisible(false)
            armed.setValue(false)
            // Registered cancellation handler is synchronous; no await precedes this.
            #expect(snapshots.value.count == 1)
            if let snapshot = snapshots.value.first {
                #expect(snapshot.requestID == nil)
                #expect(!snapshot.processing)
                #expect(snapshot.error == nil)
            }
            #expect(request.returnCount.value == 0)
            await request.release(.success(AIDateModelFixture.dateA))
            try await tracked.finished.wait()
            #expect(fixture.receipts.dates.isEmpty)
        }
    }

    // Reselecting the provider during an await or resolving again on same Show breaks this.
    @Test
    func resolvedProviderIsSnapshottedOncePerAcceptedRequest() async throws {
        try await withFixture(preference: .onDevice) { fixture in
            let tracked = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            #expect(request.query == "fixture draft A")
            #expect(request.provider == .foundationModels)
            fixture.model.setPanelVisible(true)
            fixture.model.synchronizeSettings(enabled: true, preference: .onDevice)
            #expect(fixture.resolutions.value == [.onDevice])
            await request.release(.success(nil))
            try await tracked.finished.wait()
            #expect(fixture.resolutions.value == [.onDevice])
        }
    }

    // Treating unavailable as rejection/no-date or invoking a provider breaks this.
    @Test
    func unsupportedProviderRetainsDraftWithoutInvokingWork() async throws {
        try await withFixture(preference: .onDevice, onDeviceSupported: false) { fixture in
            let tracked = try fixture.submitRequired()
            try await tracked.finished.wait()
            let requestCount = await fixture.requests.count
            #expect(requestCount == 0)
            #expect(fixture.resolutions.value == [.onDevice])
            #expect(fixture.model.currentRequestID == nil)
            #expect(!fixture.model.isProcessing)
            #expect(fixture.model.draft == "fixture draft A")
            #expect(fixture.model.isEditorOpen)
            #expect(fixture.model.errorMessage ==
                    "On-device AI is unavailable. Choose Cloud AI in Preferences.")
            #expect(fixture.receipts.dates.isEmpty)
        }
    }

    // Leaving an old idle failure visible after a direct edit misrepresents the new draft.
    @Test
    func idleFailureEditClearsErrorSynchronously() async throws {
        try await withFixture { fixture in
            let tracked = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            await request.release(.success(nil))
            try await tracked.finished.wait()
            #expect(fixture.model.errorMessage != nil)
            fixture.model.setDraft("fixture draft B")
            #expect(fixture.model.errorMessage == nil)
            #expect(fixture.model.draft == "fixture draft B")
            #expect(fixture.model.isEditorOpen)
            #expect(!fixture.model.isProcessing)
            #expect(fixture.receipts.dates.isEmpty)
        }
    }

    // Returning early on current Task cancellation leaves its spinner/handle stranded.
    @Test
    func currentTaskCancellationIsSilentAndEndsOwnProgress() async throws {
        try await withFixture { fixture in
            let tracked = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            tracked.task.cancel()
            await request.release(.success(AIDateModelFixture.dateA))
            try await tracked.finished.wait()
            #expect(!fixture.model.isProcessing)
            #expect(fixture.model.currentRequestID == nil)
            #expect(fixture.model.errorMessage == nil)
            #expect(fixture.model.draft == "fixture draft A")
            #expect(fixture.model.isEditorOpen)
            #expect(fixture.receipts.dates.isEmpty)
        }
    }

    // Missing trim/empty rejection invokes the provider for an empty current draft.
    @Test(arguments: ["", " ", "\t", " \t "])
    func emptyAndWhitespaceDraftDoesNotStartProvider(draft: String) async throws {
        try await withFixture { fixture in
            fixture.model.setDraft(draft)
            #expect(fixture.submit() == nil)
            #expect(!fixture.model.isProcessing)
            #expect(fixture.model.currentRequestID == nil)
        }
    }

    @Test
    func cleanupContinuesAfterOneActualTaskMissesItsBound() async throws {
        let fixture = AIDateModelFixture(preference: .auto, onDeviceSupported: true)
        let blocked = AIDateModelReleaseGate()
        let blockedTask = Task { _ = await blocked.wait() }
        _ = fixture.trackObserver(blockedTask)
        var scenarioError: (any Error)?
        do {
            let installed: AIDateModelSignal<Void> = fixture.signal("cleanup observer installed")
            let observed: AIDateModelSignal<Void> = fixture.signal("cleanup observer")
            let observer = Task {
                do {
                    try await observed.wait { installed.resolve(.success(())) }
                    Issue.record("Cleanup observer unexpectedly received a producer result.")
                } catch is CancellationError {
                    // The observer ends; its producer remains unresolved.
                } catch {
                    Issue.record("Unexpected cleanup observer failure: \(error)")
                }
            }
            let laterObserver = fixture.trackObserver(observer)
            try await installed.wait()
            #expect(observed.retainedWatchdogCount == 1)
            let actual = try fixture.submitRequired()
            let request = try await fixture.enteredRequest(at: 0)
            do {
                try await fixture.drain()
                Issue.record("An unresolved actual task must make cleanup fail explicitly.")
            } catch AIDateModelFixtureFailure.unresolvedCleanup(let obligations) {
                #expect(obligations == ["observer task 0"])
            }
            #expect(laterObserver.task.isCancelled)
            #expect(laterObserver.finished.isResolved)
            #expect(actual.finished.isResolved)
            #expect(request.returnCount.value == 1)
            #expect(observed.retainedWatchdogCount == 0)
            #expect(!observed.isResolved)
        } catch {
            scenarioError = error
        }
        // Release the genuine blocked task even when the scenario throws.
        await blocked.open(.success(nil))
        try await fixture.drain()
        if let scenarioError { throw scenarioError }
    }

    private func withFixture(
        preference: AIProvider = .auto,
        onDeviceSupported: Bool = true,
        body: @MainActor (AIDateModelFixture) async throws -> Void
    ) async throws {
        let fixture = AIDateModelFixture(
            preference: preference, onDeviceSupported: onDeviceSupported
        )
        do {
            try await body(fixture)
        } catch {
            let scenarioError = error
            do { try await fixture.drain() }
            catch { Issue.record("Synthetic fixture drain failed after scenario error: \(error)") }
            throw scenarioError
        }
        try await fixture.drain()
    }
}

@MainActor
private final class AIDateModelFixture {
    nonisolated static let dateA = Date(timeIntervalSince1970: 1_000_000)
    nonisolated static let dateB = Date(timeIntervalSince1970: 2_000_000)
    let requests: AIDateModelRequests
    let resolutions: LockIsolated<[AIProvider]>
    let receipts: AIDateModelDateReceipts
    let model: AIDateQueryModel
    private var tracked: [AIDateModelTrackedTask] = []
    private var observerTasks: [AIDateModelTrackedTask] = []
    private var extraSignalDrains: [@Sendable () async -> Void] = []

    init(preference: AIProvider, onDeviceSupported: Bool) {
        let requests = AIDateModelRequests()
        let resolutions = LockIsolated<[AIProvider]>([])
        let receipts = AIDateModelDateReceipts()
        self.requests = requests
        self.resolutions = resolutions
        self.receipts = receipts
        let client = AIDateQueryClient(
            resolveProvider: { preference in
                resolutions.withValue { $0.append(preference) }
                switch preference {
                case .auto, .proxy: return .proxy
                case .onDevice: return onDeviceSupported ? .foundationModels : .none
                }
            },
            parseDate: {
                if $1 == .none { throw AIDateFailure.unavailable }
                return try await requests.parse(query: $0, provider: $1)
            }
        )
        model = AIDateQueryModel(
            client: client, enabled: true, preference: preference,
            onDate: { receipts.accept($0) }
        )
        model.setPanelVisible(true)
        model.setEditorOpen(true)
        model.setDraft("fixture draft A")
    }

    func submit() -> AIDateModelTrackedTask? {
        guard let task = model.submit() else { return nil }
        let receipt = AIDateModelTrackedTask(task)
        tracked.append(receipt)
        return receipt
    }

    func submitRequired() throws -> AIDateModelTrackedTask {
        try #require(submit())
    }

    func enteredRequest(at index: Int) async throws -> AIDateModelRequest {
        let request = try await requests.request(at: index)
        try await request.entered.wait()
        return request
    }

    func signal<Value: Sendable>(_ label: String) -> AIDateModelSignal<Value> {
        let signal = AIDateModelSignal<Value>(label)
        extraSignalDrains.append { await signal.drainWatchdogs() }
        return signal
    }

    @discardableResult
    func trackObserver(_ task: Task<Void, Never>) -> AIDateModelTrackedTask {
        let receipt = AIDateModelTrackedTask(task)
        observerTasks.append(receipt)
        return receipt
    }

    func drain() async throws {
        // Unstructured cleanup does not inherit a canceled scenario's state.
        // Signal.wait must remain able to observe genuine worker completion.
        let cleanup = Task { @MainActor in
            try await self.drainUncancelled()
        }
        try await cleanup.value
    }

    private func drainUncancelled() async throws {
        receipts.onDate = nil
        requests.setCancellationObservation(nil)
        model.setPanelVisible(false)
        // Set drain mode before releasing existing workers. A captured model Task
        // that enters the client late is also released immediately in that mode.
        await requests.beginDrain()
        for receipt in observerTasks { receipt.task.cancel() }
        var unresolved: [String] = []
        for (index, receipt) in tracked.enumerated() {
            do {
                try await receipt.finished.wait()
                await receipt.monitor.value
            } catch {
                unresolved.append("model task \(index)")
            }
            await receipt.finished.drainWatchdogs()
        }
        for (index, receipt) in observerTasks.enumerated() {
            do {
                try await receipt.finished.wait()
                await receipt.monitor.value
            } catch {
                unresolved.append("observer task \(index)")
            }
            await receipt.finished.drainWatchdogs()
        }
        let actual = await requests.snapshot()
        for (index, request) in actual.enumerated() {
            do {
                try await request.returned.wait()
                #expect(request.returnCount.value == 1)
            } catch {
                unresolved.append("provider worker \(index)")
            }
            await request.entered.drainWatchdogs()
            await request.returned.drainWatchdogs()
        }
        await requests.drainDiscoverySignals()
        for drainSignal in extraSignalDrains { await drainSignal() }
        if !unresolved.isEmpty {
            throw AIDateModelFixtureFailure.unresolvedCleanup(unresolved)
        }
    }
}

@MainActor
private final class AIDateModelDateReceipts {
    var dates: [Date] = []
    var onDate: (@MainActor (Date) -> Void)?

    func accept(_ date: Date) {
        dates.append(date)
        onDate?(date)
    }
}

private struct AIDateModelOwnershipSnapshot: Sendable {
    let requestID: UUID?
    let processing: Bool
    let error: String?

    @MainActor init(_ model: AIDateQueryModel) {
        requestID = model.currentRequestID
        processing = model.isProcessing
        error = model.errorMessage
    }
}

private final class AIDateModelTrackedTask: Sendable {
    let task: Task<Void, Never>
    let finished: AIDateModelSignal<Void>
    let monitor: Task<Void, Never>

    init(_ task: Task<Void, Never>) {
        self.task = task
        let finished = AIDateModelSignal<Void>("actual model Task.value completed")
        self.finished = finished
        monitor = Task.detached {
            await task.value
            finished.resolve(.success(()))
        }
    }
}

/// The client operation deliberately ignores cancellation until its release gate
/// opens. This is the actual injected worker, not a replacement completion waiter.
private final class AIDateModelRequest: Sendable {
    let query: String
    let provider: AIDateHelper.Provider
    let entered = AIDateModelSignal<Void>("actual provider entered with handler installed")
    let returned = AIDateModelSignal<Void>("actual provider returned")
    let returnCount = LockIsolated(0)
    let cancelCount = LockIsolated(0)
    private let releaseGate = AIDateModelReleaseGate()

    init(query: String, provider: AIDateHelper.Provider) {
        self.query = query
        self.provider = provider
    }

    func run(onCancellation: @escaping @Sendable () -> Void) async throws -> Date? {
        defer {
            returnCount.withValue { $0 += 1 }
            returned.resolve(.success(()))
        }
        return try await withTaskCancellationHandler {
            entered.resolve(.success(()))
            return try await releaseGate.wait().get()
        } onCancel: {
            self.cancelCount.withValue { $0 += 1 }
            onCancellation()
        }
    }

    func release(_ result: Result<Date?, any Error>) async {
        await releaseGate.open(result)
    }
}

private actor AIDateModelReleaseGate {
    private var result: Result<Date?, any Error>?
    private var waiter: CheckedContinuation<Result<Date?, any Error>, Never>?

    func wait() async -> Result<Date?, any Error> {
        if let result { return result }
        return await withCheckedContinuation { waiter = $0 }
    }

    func open(_ result: Result<Date?, any Error>) {
        guard self.result == nil else { return }
        self.result = result
        waiter?.resume(returning: result)
        waiter = nil
    }
}

private actor AIDateModelRequests {
    private var requests: [AIDateModelRequest] = []
    private var discovery: [Int: AIDateModelSignal<AIDateModelRequest>] = [:]
    private var draining = false
    nonisolated private let cancellationObservation = LockIsolated<(@Sendable () -> Void)?>(nil)
    var count: Int { requests.count }

    nonisolated func setCancellationObservation(_ observation: (@Sendable () -> Void)?) {
        cancellationObservation.setValue(observation)
    }

    func parse(query: String, provider: AIDateHelper.Provider) async throws -> Date? {
        let request = AIDateModelRequest(query: query, provider: provider)
        let index = requests.count
        requests.append(request)
        discovery[index]?.resolve(.success(request))
        if draining { await request.release(.failure(CancellationError())) }
        return try await request.run { [cancellationObservation] in
            cancellationObservation.value?()
        }
    }

    func request(at index: Int) async throws -> AIDateModelRequest {
        if index < requests.count { return requests[index] }
        let signal = discovery[index] ?? AIDateModelSignal<AIDateModelRequest>(
            "provider request \(index) discovered"
        )
        discovery[index] = signal
        return try await signal.wait()
    }

    func beginDrain() async {
        draining = true
        for request in requests { await request.release(.failure(CancellationError())) }
    }

    func snapshot() -> [AIDateModelRequest] { requests }

    func drainDiscoverySignals() async {
        for signal in discovery.values { await signal.drainWatchdogs() }
    }
}

private enum AIDateModelFixtureFailure: Error {
    case watchdog(String)
    case unresolvedCleanup([String])
}

/// Durable producer result and separately cancellable observers. A watchdog can
/// fail an observer, never resolve the producer or substitute for Task.value.
private final class AIDateModelSignal<Value: Sendable>: @unchecked Sendable {
    private final class Observer: @unchecked Sendable {
        var result: Result<Value, any Error>?
        var continuation: CheckedContinuation<Value, any Error>?
        var watchdog: Task<Void, Never>?
    }

    private let lock = NSLock()
    private let label: String
    private var result: Result<Value, any Error>?
    private var observers: [UUID: Observer] = [:]
    private var watchdogs: [Task<Void, Never>] = []

    init(_ label: String) { self.label = label }

    var isResolved: Bool { lock.withLock { result != nil } }
    var retainedWatchdogCount: Int { lock.withLock { watchdogs.count } }

    func resolve(_ result: Result<Value, any Error>) {
        let deliveries = lock.withLock { () -> [(CheckedContinuation<Value, any Error>?, Task<Void, Never>?)] in
            guard self.result == nil else { return [] }
            self.result = result
            let deliveries = observers.values.map { observer in
                observer.result = result
                let delivery = (observer.continuation, observer.watchdog)
                observer.continuation = nil
                observer.watchdog = nil
                return delivery
            }
            observers.removeAll()
            return deliveries
        }
        for (continuation, watchdog) in deliveries {
            watchdog?.cancel()
            continuation?.resume(with: result)
        }
    }

    func wait(onInstall: @Sendable () -> Void = {}) async throws -> Value {
        try Task.checkCancellation()
        let id = UUID()
        let observer = Observer()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let completed = lock.withLock { () -> Result<Value, any Error>? in
                    if let canceled = observer.result { return canceled }
                    if let result {
                        observer.result = result
                        return result
                    }
                    observer.continuation = continuation
                    observers[id] = observer
                    return nil
                }
                if let completed {
                    continuation.resume(with: completed)
                    return
                }
                // Failure-only bound, never an ordering mechanism or completion.
                let watchdog = Task.detached {
                    do { try await Task.sleep(for: .seconds(5)) }
                    catch { return }
                    self.finishObserver(
                        id, observer: observer,
                        result: .failure(AIDateModelFixtureFailure.watchdog(self.label))
                    )
                }
                let alreadyCompleted = lock.withLock {
                    watchdogs.append(watchdog)
                    guard observer.result == nil else { return true }
                    observer.watchdog = watchdog
                    return false
                }
                if alreadyCompleted { watchdog.cancel() }
                onInstall()
            }
        } onCancel: {
            self.finishObserver(id, observer: observer, result: .failure(CancellationError()))
        }
    }

    /// Joins watchdogs after bounded acknowledgement attempts; this never
    /// supplies completion for an unresolved producer.
    func drainWatchdogs() async {
        let jobs = lock.withLock {
            let jobs = watchdogs
            watchdogs.removeAll()
            return jobs
        }
        for job in jobs { job.cancel() }
        for job in jobs { await job.value }
    }

    private func finishObserver(
        _ id: UUID, observer: Observer, result: Result<Value, any Error>
    ) {
        let delivery = lock.withLock { () -> (CheckedContinuation<Value, any Error>?, Task<Void, Never>?)? in
            guard observer.result == nil else { return nil }
            observer.result = result
            observers.removeValue(forKey: id)
            let delivery = (observer.continuation, observer.watchdog)
            observer.continuation = nil
            observer.watchdog = nil
            return delivery
        }
        delivery?.1?.cancel()
        delivery?.0?.resume(with: result)
    }
}
