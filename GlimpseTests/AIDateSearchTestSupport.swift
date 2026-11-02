import AppKit
import ComposableArchitecture
import GlimpseCore
import SwiftUI
import Testing
@testable import Glimpse

struct AIDateIntegrationSettings: Sendable, Equatable {
    var enabled: Bool
    var preference: AIProvider
}

enum AIDateIntegrationClient {
    // Default for existing keyboard fixtures. No live resolver/configuration access.
    static var immediateNoDate: AIDateQueryClient {
        AIDateQueryClient(resolveProvider: { _ in .proxy }, parseDate: { _, _ in nil })
    }
}

@MainActor
final class AIDateIntegrationTaskReceipts {
    var tasks: [AIDateIntegrationTrackedTask] = []
}

@MainActor
final class AIDateIntegrationFixture {
    let requests: AIDateIntegrationRequests
    let root: CalendarKeyboardRootFixture

    init(maximumHeight: CGFloat = 550, allowAISettings: Bool = false) throws {
        let requests = AIDateIntegrationRequests()
        self.requests = requests
        root = try CalendarKeyboardRootFixture(
            showAI: true, maximumHeight: maximumHeight,
            aiClient: AIDateQueryClient(
                resolveProvider: { _ in .proxy },
                parseDate: { try await requests.parse(query: $0, provider: $1) }
            ),
            allowAISettings: allowAISettings
        )
    }

    func request(at index: Int) async throws -> AIDateIntegrationRequest {
        let request = try await requests.request(at: index)
        try await request.entered.wait()
        return request
    }

    func completed(_ request: AIDateIntegrationRequest, at index: Int) async throws {
        try await request.returned.wait()
        #expect(request.returnCount.value == 1)
        try await root.aiTasks[index].finish()
        await root.settleRendering()
    }

    func drain() async throws {
        // This unstructured cleanup does not inherit scenario cancellation.
        let cleanup = Task { @MainActor in
            defer { self.root.close() }
            self.root.aiModel.setPanelVisible(false)
            await self.requests.beginDrain()
            var failure: (any Error)?
            for receipt in self.root.aiTasks {
                do { try await receipt.finish() }
                catch { if failure == nil { failure = error } }
            }
            // Snapshot only after actual Tasks had the opportunity to enter/return.
            // Drain mode releases a worker even if it enters after cleanup begins.
            for request in await self.requests.snapshot() {
                do { try await request.returned.wait() }
                catch { if failure == nil { failure = error } }
                #expect(request.returnCount.value == 1)
                await request.entered.drainWatchdogs()
                await request.returned.drainWatchdogs()
            }
            await self.requests.drainDiscoverySignals()
            if let failure { throw failure }
        }
        try await cleanup.value
    }
}

/// The legacy keyboard acceptance method now executes its harmless synthetic
/// request and drains every actual returned handle even when its scenario throws.
@MainActor
func withAIDateKeyboardRootFixture(
    _ body: @MainActor (CalendarKeyboardRootFixture) async throws -> Void
) async throws {
    let root = try CalendarKeyboardRootFixture(showAI: true)
    defer { root.close() }
    do { try await body(root) }
    catch {
        do { try await root.awaitAcceptedSubmissions() }
        catch { Issue.record("Keyboard fixture actual-task cleanup failed") }
        throw error
    }
    try await root.awaitAcceptedSubmissions()
}

@MainActor
func withAIDateIntegrationFixture(
    maximumHeight: CGFloat = 550, allowAISettings: Bool = false,
    _ body: @MainActor (AIDateIntegrationFixture) async throws -> Void
) async throws {
    let fixture = try AIDateIntegrationFixture(
        maximumHeight: maximumHeight, allowAISettings: allowAISettings
    )
    do { try await body(fixture) }
    catch {
        do { try await fixture.drain() }
        catch { Issue.record("AI integration fixture cleanup failed: \(error)") }
        throw error
    }
    try await fixture.drain()
}

final class AIDateIntegrationTrackedTask: Sendable {
    let task: Task<Void, Never>
    let finished: AIDateIntegrationSignal<Void>
    let monitor: Task<Void, Never>

    init(_ task: Task<Void, Never>) {
        self.task = task
        let finished = AIDateIntegrationSignal<Void>("actual model Task.value completed")
        self.finished = finished
        monitor = Task.detached {
            await task.value
            finished.resolve(.success(()))
        }
    }

    func finish() async throws {
        var failure: (any Error)?
        do {
            try await finished.wait()
            // The producer publishes success only after this exact Task.value.
            // Never join an unacknowledged actual Task on the failure path.
            await task.value
            await monitor.value
        } catch {
            failure = error
        }
        // A failed bounded acknowledgement still owns retained signal jobs.
        await finished.drainWatchdogs()
        if let failure { throw failure }
    }
}

/// The client operation deliberately ignores cancellation until its release gate
/// opens. This is the actual injected worker, not a replacement completion waiter.
final class AIDateIntegrationRequest: Sendable {
    let query: String
    let provider: AIDateHelper.Provider
    let entered = AIDateIntegrationSignal<Void>("actual provider entered with handler installed")
    let returned = AIDateIntegrationSignal<Void>("actual provider returned")
    let returnCount = LockIsolated(0)
    let cancelCount = LockIsolated(0)
    private let releaseGate = AIDateIntegrationReleaseGate()

    init(query: String, provider: AIDateHelper.Provider) {
        self.query = query
        self.provider = provider
    }

    func run() async throws -> Date? {
        defer {
            returnCount.withValue { $0 += 1 }
            returned.resolve(.success(()))
        }
        return try await withTaskCancellationHandler {
            entered.resolve(.success(()))
            return try await releaseGate.wait().get()
        } onCancel: {
            self.cancelCount.withValue { $0 += 1 }
        }
    }

    func release(_ result: Result<Date?, any Error>) async {
        await releaseGate.open(result)
    }
}

private actor AIDateIntegrationReleaseGate {
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

actor AIDateIntegrationRequests {
    private var requests: [AIDateIntegrationRequest] = []
    private var discovery: [Int: AIDateIntegrationSignal<AIDateIntegrationRequest>] = [:]
    private var draining = false
    var count: Int { requests.count }

    func parse(query: String, provider: AIDateHelper.Provider) async throws -> Date? {
        let request = AIDateIntegrationRequest(query: query, provider: provider)
        let index = requests.count
        requests.append(request)
        discovery[index]?.resolve(.success(request))
        if draining { await request.release(.failure(CancellationError())) }
        return try await request.run()
    }

    func request(at index: Int) async throws -> AIDateIntegrationRequest {
        if index < requests.count { return requests[index] }
        let signal = discovery[index] ?? AIDateIntegrationSignal<AIDateIntegrationRequest>(
            "provider request \(index) discovered"
        )
        discovery[index] = signal
        return try await signal.wait()
    }

    func beginDrain() async {
        draining = true
        for request in requests { await request.release(.failure(CancellationError())) }
    }

    func snapshot() -> [AIDateIntegrationRequest] { requests }

    func drainDiscoverySignals() async {
        for signal in discovery.values { await signal.drainWatchdogs() }
    }
}

enum AIDateIntegrationFixtureFailure: Error {
    case watchdog(String)
    case receiptFailures([Int])
}

/// Durable producer result and separately cancellable observers. A watchdog can
/// fail an observer, never resolve the producer or substitute for Task.value.
final class AIDateIntegrationSignal<Value: Sendable>: @unchecked Sendable {
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
                        result: .failure(AIDateIntegrationFixtureFailure.watchdog(self.label))
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

    /// Joins signal watchdogs after bounded acknowledgement attempts,
    /// including failed attempts that leave the actual request Task unresolved.
    func drainWatchdogs() async {
        let jobs = lock.withLock { watchdogs }
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
