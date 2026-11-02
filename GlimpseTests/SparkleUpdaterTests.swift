import Combine
import Foundation
import Sparkle
import Testing
@testable import Glimpse

@MainActor
struct SparkleUpdaterTests {
    @Test
    func initializationFailureHasNoRetryPath() {
        let fixture = UpdaterFixture(startError: updateTestError)
        defer { fixture.delay.drain() }
        let firstProjection = fixture.updater.userDriver
        let reopenedProjection = fixture.updater.userDriver
        fixture.updater.checkForUpdates()
        #expect(firstProjection === reopenedProjection)
        #expect(firstProjection.status == .initializationFailed)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
        #expect(!fixture.updater.canCheckForUpdates)
    }

    @Test
    func checkErrorWaitsForEligibilityAndPersistsThroughDismissal() {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        fixture.updater.checkForUpdates()
        fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        fixture.backend.publishEligibility(false)
        var acknowledgements = 0
        fixture.driver.showUpdaterError(updateTestError) {
            acknowledgements += 1
            #expect(fixture.driver.status == .error(.check))
        }
        fixture.driver.dismissUpdateInstallation()
        #expect(fixture.driver.status == .error(.check))
        #expect(acknowledgements == 1)
        #expect(!fixture.updater.canCheckForUpdates)
        fixture.backend.publishEligibility(true)
        #expect(fixture.updater.canCheckForUpdates)
        #expect(fixture.backend.checkCount == 1)
        #expect(fixture.backend.startCount == 1)
    }

    @Test
    func eligibilityDropRejectsRenderedRetry() {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        #expect(fixture.updater.canCheckForUpdates)
        let renderedRetry = { fixture.updater.checkForUpdates() }
        fixture.backend.canCheck = false // Native eligibility changed before its notification.
        renderedRetry()
        #expect(fixture.backend.checkCount == 0)
        #expect(fixture.driver.status == .error(.check))
        #expect(!fixture.updater.canCheckForUpdates)
    }

    @Test
    func doubleRetryAdmitsBeforeNativeCallback() {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        fixture.backend.onCheck = {
            #expect(fixture.driver.status == .checking)
        }
        fixture.updater.checkForUpdates()
        fixture.updater.checkForUpdates()
        fixture.backend.publishEligibility(true)
        #expect(fixture.backend.checkCount == 1)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.driver.status == .checking)
        #expect(!fixture.updater.canCheckForUpdates)
    }

    @Test(arguments: [false, true])
    func retryReceivesNewOutcome(latest: Bool) async {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        fixture.updater.checkForUpdates()
        #expect(fixture.driver.status == .checking)
        var acknowledgements = 0
        if latest {
            fixture.driver.showUpdateNotFoundWithError(updateTestError) {
                acknowledgements += 1
            }
            #expect(fixture.driver.status == .latest)
            #expect(!fixture.updater.canCheckForUpdates)
            _ = await fixture.delay.waitForRequest(0)
        } else {
            fixture.driver.showUpdaterError(updateTestError) { acknowledgements += 1 }
            #expect(fixture.driver.status == .error(.check))
            #expect(fixture.updater.canCheckForUpdates)
            #expect(fixture.backend.checkCount == 1)
            fixture.updater.checkForUpdates()
            #expect(fixture.backend.checkCount == 2)
            #expect(fixture.driver.status == .checking)
        }
        #expect(acknowledgements == 1)
        #expect(fixture.backend.startCount == 1)
    }

    @Test
    func errorWithoutAnActiveCheckUsesUpdateFailure() {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var acknowledgements = 0
        fixture.driver.showUpdaterError(updateTestError) { acknowledgements += 1 }
        #expect(fixture.driver.status == .error(.update))
        #expect(acknowledgements == 1)
        #expect(fixture.backend.checkCount == 0)
    }
}

@MainActor
var updateTestError: NSError {
    NSError(domain: "GlimpseUpdateFixture", code: 1)
}

@MainActor
struct UpdateChoiceTests {
    @Test
    func oldOfferControlsCannotConsumeReplacementOffer() throws {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var aChoices: [SPUUserUpdateChoice] = []
        var bChoices: [SPUUserUpdateChoice] = []
        var replacementID: UUID?
        fixture.driver.presentUpdate(version: "A") { choice in
            aChoices.append(choice)
            fixture.driver.presentUpdate(version: "B") { bChoices.append($0) }
            replacementID = fixture.driver.updateChoiceID
        }
        let aID = try #require(fixture.driver.updateChoiceID)
        let retainedInstall = { fixture.driver.chooseUpdate(.install, id: aID) }
        let retainedSkip = { fixture.driver.chooseUpdate(.skip, id: aID) }
        retainedInstall()
        let bID = try #require(replacementID)
        #expect(aChoices == [.install])
        retainedInstall()
        retainedSkip()
        #expect(bChoices.isEmpty)
        #expect(fixture.driver.updateChoiceID == bID)
        #expect(fixture.driver.status == .available(version: "B"))
        fixture.driver.chooseUpdate(.install, id: bID)
        fixture.driver.chooseUpdate(.install, id: bID)
        #expect(bChoices == [.install])
        #expect(fixture.driver.updateChoiceID == nil)
        #expect(!fixture.updater.canCheckForUpdates)
    }

    @Test
    func skipConsumesOnlyItsMatchingOfferOnce() throws {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var choices: [SPUUserUpdateChoice] = []
        fixture.driver.presentUpdate(version: "A") { choices.append($0) }
        let id = try #require(fixture.driver.updateChoiceID)
        fixture.driver.chooseUpdate(.skip, id: id)
        fixture.driver.chooseUpdate(.skip, id: id)
        #expect(choices == [.skip])
        #expect(fixture.driver.updateChoiceID == nil)
        #expect(fixture.backend.checkCount == 0)
        #expect(!fixture.updater.canCheckForUpdates)
    }

    @Test
    func oldRelaunchControlCannotConsumeReplacementReadyChoice() throws {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var aChoices: [SPUUserUpdateChoice] = []
        var bChoices: [SPUUserUpdateChoice] = []
        var replacementID: UUID?
        fixture.driver.showReady { choice in
            aChoices.append(choice)
            fixture.driver.showReady { bChoices.append($0) }
            replacementID = fixture.driver.installChoiceID
        }
        let aID = try #require(fixture.driver.installChoiceID)
        let retainedRelaunch = { fixture.driver.chooseInstallAndRelaunch(id: aID) }
        retainedRelaunch()
        let bID = try #require(replacementID)
        retainedRelaunch()
        #expect(aChoices == [.install])
        #expect(bChoices.isEmpty)
        #expect(fixture.driver.installChoiceID == bID)
        fixture.driver.chooseInstallAndRelaunch(id: bID)
        fixture.driver.chooseInstallAndRelaunch(id: bID)
        #expect(bChoices == [.install])
        #expect(fixture.driver.installChoiceID == nil)
        #expect(!fixture.updater.canCheckForUpdates)
    }

    @Test(arguments: [false, true])
    func errorRetainsOwnedChoiceUntilSparkleDismisses(ready: Bool) throws {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var choices: [SPUUserUpdateChoice] = []
        if ready {
            fixture.driver.showReady { choices.append($0) }
        } else {
            fixture.driver.presentUpdate(version: "A") { choices.append($0) }
        }
        let id = try #require(ready ? fixture.driver.installChoiceID : fixture.driver.updateChoiceID)
        var acknowledgements = 0
        fixture.driver.showUpdaterError(updateTestError) {
            acknowledgements += 1
            #expect(fixture.driver.status == .error(.update))
            #expect((ready ? fixture.driver.installChoiceID : fixture.driver.updateChoiceID) == id)
        }
        fixture.backend.publishEligibility(true)
        fixture.updater.checkForUpdates()
        #expect(!fixture.updater.canCheckForUpdates)
        #expect(fixture.backend.checkCount == 0)
        #expect(choices.isEmpty)
        #expect(acknowledgements == 1)
        fixture.driver.dismissUpdateInstallation()
        #expect(fixture.driver.updateChoiceID == nil)
        #expect(fixture.driver.installChoiceID == nil)
        #expect(fixture.driver.status == .error(.update))
        #expect(choices.isEmpty)
        fixture.updater.checkForUpdates()
        #expect(fixture.backend.checkCount == 1)
        #expect(fixture.driver.status == .checking)
    }

    @Test(arguments: [false, true])
    func failureDuringProgressAllowsOnlyNewCheck(installing: Bool) throws {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var choices: [SPUUserUpdateChoice] = []
        fixture.driver.presentUpdate(version: "A") { choices.append($0) }
        fixture.driver.chooseUpdate(.install, id: try #require(fixture.driver.updateChoiceID))
        if installing {
            fixture.driver.showInstallingUpdate(
                withApplicationTerminated: false, retryTerminatingApplication: {}
            )
        } else {
            fixture.driver.showDownloadInitiated(cancellation: {})
        }
        fixture.backend.publishEligibility(false)
        var acknowledgements = 0
        fixture.driver.showUpdaterError(updateTestError) { acknowledgements += 1 }
        #expect(fixture.driver.status == .error(.update))
        #expect(acknowledgements == 1)
        fixture.updater.checkForUpdates()
        #expect(fixture.backend.checkCount == 0)
        fixture.driver.dismissUpdateInstallation()
        fixture.backend.publishEligibility(true)
        #expect(fixture.backend.checkCount == 0)
        fixture.updater.checkForUpdates()
        #expect(fixture.backend.checkCount == 1)
        #expect(choices == [.install])
    }

    @Test
    func dismissInvalidatesAllOldControls() throws {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var choices: [SPUUserUpdateChoice] = []
        fixture.driver.presentUpdate(version: "A") { choices.append($0) }
        let offerID = try #require(fixture.driver.updateChoiceID)
        fixture.driver.showReady { choices.append($0) }
        let readyID = try #require(fixture.driver.installChoiceID)
        fixture.driver.dismissUpdateInstallation()
        fixture.driver.chooseUpdate(.install, id: offerID)
        fixture.driver.chooseUpdate(.skip, id: offerID)
        fixture.driver.chooseInstallAndRelaunch(id: readyID)
        #expect(choices.isEmpty)
        #expect(fixture.driver.updateChoiceID == nil)
        #expect(fixture.driver.installChoiceID == nil)
        #expect(fixture.driver.status == .idle)
    }

    @Test(arguments: ["checking", "available", "downloading", "extracting", "ready"])
    func activePhaseBlocksAnotherCheck(phase: String) {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var choices: [SPUUserUpdateChoice] = []
        switch phase {
        case "checking": fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        case "available": fixture.driver.presentUpdate(version: "A") { choices.append($0) }
        case "downloading": fixture.driver.showDownloadInitiated(cancellation: {})
        case "extracting": fixture.driver.showDownloadDidStartExtractingUpdate()
        case "ready": fixture.driver.showReady { choices.append($0) }
        default: Issue.record("Unknown fixture phase")
        }
        let prior = fixture.driver.status
        fixture.updater.checkForUpdates()
        #expect(fixture.driver.status == prior)
        #expect(fixture.backend.checkCount == 0)
        #expect(fixture.backend.startCount == 1)
        #expect(choices.isEmpty)
    }

    @Test(arguments: [false, true])
    func manualCheckCanResumeAnOfferOrReadyInstallation(ready: Bool) throws {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var choices: [SPUUserUpdateChoice] = []
        fixture.updater.checkForUpdates()
        #expect(fixture.backend.checkCount == 1)
        if ready {
            fixture.driver.showReady { choices.append($0) }
            fixture.driver.chooseInstallAndRelaunch(id: try #require(fixture.driver.installChoiceID))
        } else {
            fixture.driver.presentUpdate(version: "resumed") { choices.append($0) }
            fixture.driver.chooseUpdate(.install, id: try #require(fixture.driver.updateChoiceID))
        }
        fixture.updater.checkForUpdates()
        #expect(choices == [.install])
        #expect(fixture.backend.checkCount == 1)
        #expect(fixture.backend.startCount == 1)
    }

    @Test
    func retryCanReceiveAnOffer() {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        fixture.updater.checkForUpdates()
        fixture.driver.presentUpdate(version: "new") { _ in }
        #expect(fixture.driver.status == .available(version: "new"))
        #expect(fixture.driver.updateChoiceID != nil)
        #expect(!fixture.updater.canCheckForUpdates)
        #expect(fixture.backend.checkCount == 1)
    }
}

/// The double replaces native I/O only; driver transitions remain production code.
@MainActor
final class UpdateBackend {
    var startCount = 0
    var checkCount = 0
    var canCheck = true
    var startError: Error?
    var onCheck: (() -> Void)?
    private var observer: (@MainActor (Bool) -> Void)?

    var client: UpdaterClient {
        UpdaterClient(
            start: {
                self.startCount += 1
                if let error = self.startError { throw error }
            },
            canCheckForUpdates: { self.canCheck },
            observeCanCheckForUpdates: { receive in
                self.observer = receive
                receive(self.canCheck)
                return AnyCancellable {}
            },
            checkForUpdates: {
                self.checkCount += 1
                self.onCheck?()
            }
        )
    }

    func publishEligibility(_ value: Bool) {
        canCheck = value
        observer?(value)
    }
}

@MainActor
final class UpdaterFixture {
    let backend: UpdateBackend
    let delay: ControlledUpdateDelay
    let driver: InlineUpdateDriver
    let updater: SparkleUpdater

    init(startError: Error? = nil) {
        let backend = UpdateBackend()
        backend.startError = startError
        let delay = ControlledUpdateDelay()
        let driver = InlineUpdateDriver(delay: { try await delay.sleep($0) })
        self.backend = backend
        self.delay = delay
        self.driver = driver
        updater = SparkleUpdater(userDriver: driver, client: backend.client)
    }
}

/// Advances the driver's actual Task, including successful returns after cancellation.
@MainActor
final class ControlledUpdateDelay {
    struct Request: Equatable {
        let id: Int
        let duration: Duration
    }

    private(set) var requests: [Request] = []
    private(set) var returnedCancellation: [Int: Bool] = [:]
    private var sleepers: [Int: CheckedContinuation<Void, Error>] = [:]
    private var registrationWaiters: [Int: [CheckedContinuation<Request, Never>]] = [:]
    private var returnWaiters: [Int: [CheckedContinuation<Bool, Never>]] = [:]

    func sleep(_ duration: Duration) async throws {
        let id = requests.count
        do {
            try await withCheckedThrowingContinuation { continuation in
                let request = Request(id: id, duration: duration)
                requests.append(request)
                sleepers[id] = continuation
                for waiter in registrationWaiters.removeValue(forKey: id) ?? [] {
                    waiter.resume(returning: request)
                }
            }
            recordReturn(id)
        } catch {
            recordReturn(id)
            throw error
        }
    }

    func waitForRequest(_ id: Int) async -> Request {
        if requests.indices.contains(id) { return requests[id] }
        return await withCheckedContinuation {
            registrationWaiters[id, default: []].append($0)
        }
    }

    func waitForReturn(_ id: Int) async -> Bool {
        if let cancelled = returnedCancellation[id] { return cancelled }
        return await withCheckedContinuation {
            returnWaiters[id, default: []].append($0)
        }
    }

    func resumeSuccessfully(_ id: Int) {
        guard let sleeper = sleepers.removeValue(forKey: id) else {
            Issue.record("No registered update delay \(id)")
            return
        }
        sleeper.resume()
    }

    func resumeThrowing(_ id: Int, error: Error = CancellationError()) {
        guard let sleeper = sleepers.removeValue(forKey: id) else {
            Issue.record("No registered update delay \(id)")
            return
        }
        sleeper.resume(throwing: error)
    }

    func drain() {
        let pending = sleepers.values
        sleepers.removeAll()
        for sleeper in pending { sleeper.resume(throwing: CancellationError()) }
    }

    private func recordReturn(_ id: Int) {
        let cancelled = Task.isCancelled
        returnedCancellation[id] = cancelled
        for waiter in returnWaiters.removeValue(forKey: id) ?? [] {
            waiter.resume(returning: cancelled)
        }
    }
}

@MainActor
struct UpdateResultTests {
    @Test
    func latestWaitsFiveSecondsAndSurvivesOrdinaryDismissal() async {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        var acknowledgements = 0
        fixture.driver.showUpdateNotFoundWithError(updateTestError) { acknowledgements += 1 }
        #expect(fixture.driver.status == .latest)
        #expect(acknowledgements == 1)
        let request = await fixture.delay.waitForRequest(0)
        #expect(request.duration == .seconds(5))
        fixture.driver.dismissUpdateInstallation()
        #expect(fixture.driver.status == .latest)
        fixture.delay.resumeSuccessfully(request.id)
        #expect(await fixture.delay.waitForReturn(request.id) == false)
        await drainUpdateExecutor()
        #expect(fixture.driver.status == .idle)
    }

    @Test(arguments: ["error", "check", "offer", "download", "extraction", "ready", "installing", "latest"])
    func canceledLatestCannotEraseNewPresentation(replacement: String) async {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        fixture.driver.showUpdateNotFoundWithError(updateTestError, acknowledgement: {})
        let a = await fixture.delay.waitForRequest(0)
        switch replacement {
        case "error": fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        case "check": fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        case "offer": fixture.driver.presentUpdate(version: "B") { _ in }
        case "download": fixture.driver.showDownloadInitiated(cancellation: {})
        case "extraction": fixture.driver.showDownloadDidStartExtractingUpdate()
        case "ready": fixture.driver.showReady { _ in }
        case "installing":
            fixture.driver.showInstallingUpdate(
                withApplicationTerminated: false, retryTerminatingApplication: {}
            )
        case "latest": fixture.driver.showUpdateNotFoundWithError(updateTestError, acknowledgement: {})
        default: Issue.record("Unknown result fixture")
        }
        let expected: UpdateStatus
        switch replacement {
        case "error": expected = .error(.update)
        case "check": expected = .checking
        case "offer": expected = .available(version: "B")
        case "download": expected = .downloading
        case "extraction", "installing": expected = .extracting
        case "ready": expected = .readyToInstall
        default: expected = .latest
        }
        if replacement == "latest" {
            let b = await fixture.delay.waitForRequest(1)
            #expect(b.duration == .seconds(5))
        }
        fixture.delay.resumeSuccessfully(a.id)
        #expect(await fixture.delay.waitForReturn(a.id) == true)
        await drainUpdateExecutor()
        #expect(fixture.driver.status == expected)
        if replacement == "latest" {
            fixture.delay.resumeSuccessfully(1)
            #expect(await fixture.delay.waitForReturn(1) == false)
            await drainUpdateExecutor()
            #expect(fixture.driver.status == .idle)
        }
    }

    @Test(arguments: ["error", "latest", "finished"], ["dismiss", "offer", "ready", "progress", "error"])
    func acknowledgementCannotEraseItsReplacement(callback: String, replacement: String) async {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        if callback == "error" {
            fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        } else if callback == "finished" {
            fixture.driver.presentUpdate(version: "old") { _ in }
            fixture.driver.showReady { _ in }
            fixture.driver.showInstallingUpdate(
                withApplicationTerminated: false, retryTerminatingApplication: {}
            )
        }
        var acknowledgements = 0
        let acknowledge = {
            acknowledgements += 1
            switch callback {
            case "error": #expect(fixture.driver.status == .error(.check))
            case "latest": #expect(fixture.driver.status == .latest)
            default:
                #expect(fixture.driver.status == .idle)
                #expect(fixture.driver.updateChoiceID == nil)
                #expect(fixture.driver.installChoiceID == nil)
            }
            switch replacement {
            case "dismiss": fixture.driver.dismissUpdateInstallation()
            case "offer": fixture.driver.presentUpdate(version: "replacement") { _ in }
            case "ready": fixture.driver.showReady { _ in }
            case "progress": fixture.driver.showDownloadInitiated(cancellation: {})
            default: fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
            }
        }
        switch callback {
        case "error": fixture.driver.showUpdaterError(updateTestError, acknowledgement: acknowledge)
        case "latest": fixture.driver.showUpdateNotFoundWithError(updateTestError, acknowledgement: acknowledge)
        default: fixture.driver.showUpdateInstalledAndRelaunched(false, acknowledgement: acknowledge)
        }
        let expected: UpdateStatus
        switch replacement {
        case "offer": expected = .available(version: "replacement")
        case "ready": expected = .readyToInstall
        case "progress": expected = .downloading
        case "error": expected = .error(.update)
        default:
            switch callback {
            case "error": expected = .error(.check)
            case "latest": expected = .latest
            default: expected = .idle
            }
        }
        #expect(acknowledgements == 1)
        #expect(fixture.driver.status == expected)
        if replacement == "offer" { #expect(fixture.driver.updateChoiceID != nil) }
        if replacement == "ready" { #expect(fixture.driver.installChoiceID != nil) }
        if callback == "latest" {
            let request = await fixture.delay.waitForRequest(0)
            fixture.delay.resumeSuccessfully(request.id)
            #expect(await fixture.delay.waitForReturn(request.id) == (replacement != "dismiss"))
            await drainUpdateExecutor()
            #expect(fixture.driver.status == (replacement == "dismiss" ? .idle : expected))
        }
    }

    @Test(arguments: ["initialization", "error", "latest"])
    func installationFinishedPreservesAnExistingTerminalResult(result: String) async {
        let fixture = UpdaterFixture(startError: result == "initialization" ? updateTestError : nil)
        defer { fixture.delay.drain() }
        let expected: UpdateStatus
        switch result {
        case "initialization": expected = .initializationFailed
        case "error":
            fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
            expected = .error(.update)
        default:
            fixture.driver.showUpdateNotFoundWithError(updateTestError, acknowledgement: {})
            _ = await fixture.delay.waitForRequest(0)
            expected = .latest
        }
        var acknowledgements = 0
        fixture.driver.showUpdateInstalledAndRelaunched(false) {
            acknowledgements += 1
            #expect(fixture.driver.status == expected)
        }
        #expect(acknowledgements == 1)
        #expect(fixture.driver.status == expected)
    }

    @Test
    func delayFailureDoesNotFalselyDismissLatest() async {
        let fixture = UpdaterFixture()
        defer { fixture.delay.drain() }
        fixture.driver.showUpdateNotFoundWithError(updateTestError, acknowledgement: {})
        let request = await fixture.delay.waitForRequest(0)
        fixture.delay.resumeThrowing(request.id, error: updateTestError)
        _ = await fixture.delay.waitForReturn(request.id)
        await drainUpdateExecutor()
        #expect(fixture.driver.status == .latest)
    }
}

@MainActor
private func drainUpdateExecutor() async {
    for _ in 0..<8 { await Task.yield() }
}
