import Foundation
import Testing

@testable import Glimpse

struct DiagnosticsExportTests {
    private static let inactiveHotkey = HotkeyDiagnosticSnapshot(
        requested: false, registered: false, savedCombo: .default, activeCombo: nil, error: nil
    )

    @Test
    func exportWritesMetadataAndLogsToChosenDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Export-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Cleanup is best effort after the assertions; it cannot affect the report.
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("chosen-report.txt")
        let result = try await DiagnosticsExport.export(to: destination, hotkey: Self.inactiveHotkey) {
            .init(output: "fixture log excerpt", timedOut: false, truncated: false)
        }
        #expect(result == destination)
        let report = try String(contentsOf: destination, encoding: .utf8)
        #expect(report.contains("=== Glimpse Diagnostics ==="))
        #expect(report.contains("App Version:"))
        #expect(report.contains("Launch at login:"))
        #expect(report.contains("fixture log excerpt"))
    }

    @Test
    func collectorFailureStillSavesUsefulReportAtChosenDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Export-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Cleanup is best effort after the assertions; it cannot affect the report.
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("partial-report.txt")
        _ = try await DiagnosticsExport.export(to: destination, hotkey: Self.inactiveHotkey) {
            throw NSError(domain: "GlimpseFixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "fixture collector failure"])
        }
        let report = try String(contentsOf: destination, encoding: .utf8)
        #expect(report.contains("App Version:"))
        #expect(report.contains("=== Preferences ==="))
        #expect(report.contains("Log collection failed: fixture collector failure"))
    }

    @Test
    func destinationWriteFailureIsReportedToCaller() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Export-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Cleanup is best effort after the assertions; it cannot affect the report.
            try? FileManager.default.removeItem(at: directory)
        }
        await #expect(throws: (any Error).self) {
            _ = try await DiagnosticsExport.export(to: directory, hotkey: Self.inactiveHotkey) {
                .init(output: "", timedOut: false, truncated: false)
            }
        }
    }

    @Test
    func reportDistinguishesStartupIntentFromFailedRegistration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Hotkey-Report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Best-effort cleanup follows report assertions, with no host preferences.
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("startup-failure.txt")
        _ = try await DiagnosticsExport.export(
            to: destination, hotkey: .init(
                requested: true, registered: false, savedCombo: .default,
                activeCombo: nil, error: .registrationFailed(-50)
            )
        ) {
            .init(output: "", timedOut: false, truncated: false)
        }
        let report = try String(contentsOf: destination, encoding: .utf8)
        #expect(report.contains("Hotkey requested: true"))
        #expect(report.contains("Hotkey registered: false"))
        #expect(report.contains("Hotkey active combo: (none)"))
        #expect(report.contains("registrationFailed(-50)"))
    }

    @Test
    func reportDistinguishesExplicitOffFromFailedNativeTeardown() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Hotkey-Report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Best-effort cleanup follows report assertions, with no host preferences.
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("disable-failure.txt")
        _ = try await DiagnosticsExport.export(
            to: destination, hotkey: .init(
                requested: false, registered: true, savedCombo: .default,
                activeCombo: .default, error: .unregisterFailed(-50)
            )
        ) {
            .init(output: "", timedOut: false, truncated: false)
        }
        let report = try String(contentsOf: destination, encoding: .utf8)
        #expect(report.contains("Hotkey requested: false"))
        #expect(report.contains("Hotkey registered: true"))
        #expect(report.contains("Hotkey saved combo: ⇧⌘C"))
        #expect(report.contains("Hotkey active combo: ⇧⌘C"))
        #expect(report.contains("unregisterFailed(-50)"))
    }

    private static func entry(
        _ message: String, date: Date = Date(),
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        subsystem: String = "com.rohit.Glimpse"
    ) -> DiagnosticsExport.LogEntry {
        .init(date: date, processIdentifier: pid, subsystem: subsystem,
              category: "fixture", level: "info", message: message)
    }

    private static func report(_ collect: @escaping @Sendable () async throws -> DiagnosticsExport.LogResult) async throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Collector-Report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("report.txt")
        _ = try await DiagnosticsExport.export(to: destination, hotkey: inactiveHotkey, collect: collect)
        return try String(contentsOf: destination, encoding: .utf8)
    }

    // Synchronization belongs to the fixture boundary: the real collector is
    // responsible for deciding whether and how often it invokes this provider.
    private final class ReaderProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var starts = 0
        private var candidates = 0
        private var exits = 0
        private var watchdogFired = false
        private let release = DispatchSemaphore(value: 0)

        var startCount: Int { lock.withLock { starts } }
        var candidateCount: Int { lock.withLock { candidates } }
        var exitCount: Int { lock.withLock { exits } }
        var didReachWatchdog: Bool { lock.withLock { watchdogFired } }
        func recordStart() { lock.withLock { starts += 1 } }
        func recordCandidate() { lock.withLock { candidates += 1 } }
        func unblock() { release.signal() }
        func block(onStart: () -> Void = {}) {
            recordStart()
            onStart()
            // A test watchdog also prevents a broken collector from stranding the runner.
            let released = release.wait(timeout: .now() + 5) == .success
            lock.withLock {
                watchdogFired = !released
                exits += 1
            }
        }
        func waitForStart() async throws -> Bool {
            let deadline = ContinuousClock.now + .seconds(1)
            while startCount == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            return startCount > 0
        }
    }

    private final class FixtureEvents: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []

        func record(_ event: String) { lock.withLock { events.append(event) } }
        var description: String {
            lock.withLock { events.enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n") }
        }
    }

    private struct FixtureWatchdog: Error {
        let event: String
    }

    /// One outcome, including cancellation before continuation installation.
    /// The watchdog is fixture teardown protection and is always a test failure.
    private final class FixtureSignal<Value: Sendable>: @unchecked Sendable {
        // The signal lock protects every observer field as well as durable
        // producer completion. Observer cancellation never completes the signal.
        private final class Observer: @unchecked Sendable {
            var outcome: Result<Value, any Error>?
            var continuation: CheckedContinuation<Value, any Error>?
            var watchdog: Task<Void, Never>?
        }

        private let lock = NSLock()
        private var outcome: Result<Value, any Error>?
        private var observers: [UUID: Observer] = [:]
        private let event: String
        private let events: FixtureEvents

        init(_ event: String, events: FixtureEvents) {
            self.event = event
            self.events = events
        }

        func resolve(_ result: Result<Value, any Error>) {
            let deliveries = lock.withLock { () -> [(CheckedContinuation<Value, any Error>?, Task<Void, Never>?)] in
                guard outcome == nil else { return [] }
                outcome = result
                let deliveries = observers.values.map { observer in
                    observer.outcome = result
                    let delivery = (observer.continuation, observer.watchdog)
                    observer.continuation = nil
                    observer.watchdog = nil
                    return delivery
                }
                observers.removeAll()
                return deliveries
            }
            for delivery in deliveries {
                delivery.1?.cancel()
                delivery.0?.resume(with: result)
            }
        }

        func wait(onInstall: @Sendable () -> Void = {}) async throws -> Value {
            try Task.checkCancellation()
            let id = UUID()
            let observer = Observer()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let completed = lock.withLock { () -> Result<Value, any Error>? in
                        if let canceled = observer.outcome { return canceled }
                        if let outcome {
                            observer.outcome = outcome
                            return outcome
                        }
                        observer.continuation = continuation
                        observers[id] = observer
                        return nil
                    }
                    if let completed {
                        continuation.resume(with: completed)
                        return
                    }
                    let watchdog = Task.detached {
                        do { try await Task.sleep(for: .seconds(5)) }
                        catch { return }
                        self.finishObserver(
                            id, observer: observer,
                            result: .failure(FixtureWatchdog(event: self.event)),
                            message: "watchdog fired: \(self.event)"
                        )
                    }
                    let completedBeforeWatchdog = lock.withLock {
                        guard observer.outcome == nil else { return true }
                        observer.watchdog = watchdog
                        return false
                    }
                    if completedBeforeWatchdog { watchdog.cancel() }
                    onInstall()
                }
            } onCancel: {
                self.finishObserver(
                    id, observer: observer, result: .failure(CancellationError()),
                    message: "wait canceled: \(self.event)"
                )
            }
        }

        private func finishObserver(
            _ id: UUID, observer: Observer,
            result: Result<Value, any Error>, message: String
        ) {
            let delivery = lock.withLock { () -> (CheckedContinuation<Value, any Error>?, Task<Void, Never>?)? in
                guard observer.outcome == nil else { return nil }
                observer.outcome = result
                observers.removeValue(forKey: id)
                let delivery = (observer.continuation, observer.watchdog)
                observer.continuation = nil
                observer.watchdog = nil
                return delivery
            }
            guard let delivery else { return }
            events.record(message)
            delivery.1?.cancel()
            delivery.0?.resume(with: result)
        }
    }

    private final class CapturedWorker: @unchecked Sendable {
        private let lock = NSLock()
        private var started = false
        private var work: (@Sendable () -> Void)?
        private let events: FixtureEvents
        let finished: FixtureSignal<Void>

        init(_ work: @escaping @Sendable () -> Void, events: FixtureEvents) {
            self.work = work
            self.events = events
            finished = FixtureSignal("full worker return", events: events)
        }

        func run(onReturn: @escaping @Sendable () -> Void = {}) {
            let shouldRun = lock.withLock {
                guard !started else { return false }
                started = true
                return true
            }
            guard shouldRun else { return }
            // Never invoke blocked work inside continuation installation.
            DispatchQueue(label: "Glimpse.DiagnosticsFixture.\(UUID().uuidString)", qos: .utility).async {
                self.events.record("worker executed")
                var work = self.lock.withLock {
                    let work = self.work
                    self.work = nil
                    return work
                }
                work?()
                // Drop the consumed collector closure before completion wakes
                // observers, breaking the fixture/worker/collector retain cycle.
                work = nil
                self.events.record("full worker returned after collector cleanup")
                self.finished.resolve(.success(()))
                onReturn()
            }
        }
    }

    private final class FixtureRound: @unchecked Sendable {
        private let lock = NSLock()
        private var worker: CapturedWorker?
        private var cleaningUp = false
        let captured: FixtureSignal<CapturedWorker>
        let armed: FixtureSignal<TimeInterval>
        let deadline: FixtureSignal<Void>
        private let events: FixtureEvents

        init(events: FixtureEvents) {
            self.events = events
            captured = FixtureSignal("worker captured", events: events)
            armed = FixtureSignal("deadline armed", events: events)
            deadline = FixtureSignal("manual deadline release", events: events)
        }

        func submit(_ work: @escaping @Sendable () -> Void) {
            let worker = CapturedWorker(work, events: events)
            let drain = lock.withLock {
                self.worker = worker
                return cleaningUp
            }
            events.record("worker captured")
            captured.resolve(.success(worker))
            if drain { worker.run() }
        }

        func awaitDeadline(_ delay: TimeInterval) async throws {
            events.record("deadline armed: \(delay)")
            armed.resolve(.success(delay))
            try await deadline.wait()
        }

        func releaseDeadline(reason: String) {
            events.record("deadline released: \(reason)")
            deadline.resolve(.success(()))
        }

        func cleanup(onWaitInstalled: @Sendable () -> Void = {}) async throws {
            releaseDeadline(reason: "cleanup")
            let worker = lock.withLock {
                cleaningUp = true
                return self.worker
            }
            if let worker {
                worker.run()
                try await worker.finished.wait(onInstall: onWaitInstalled)
            }
        }
    }

    enum BlockedBoundary: String, CaseIterable, Sendable {
        case provider, iterator
    }

    private final class DeadlineFixture: @unchecked Sendable {
        let events: FixtureEvents
        let probe = ReaderProbe()
        let entered: FixtureSignal<Void>
        private let lock = NSLock()
        private var rounds: [FixtureRound] = []
        private var current: FixtureRound
        private var waiters: [Task<DiagnosticsExport.LogResult, any Error>] = []
        private let onCleanupWaitInstalled: @Sendable () -> Void

        init(
            events: FixtureEvents = FixtureEvents(),
            onCleanupWaitInstalled: @escaping @Sendable () -> Void = {}
        ) {
            self.events = events
            self.onCleanupWaitInstalled = onCleanupWaitInstalled
            entered = FixtureSignal("blocked read entry", events: events)
            current = FixtureRound(events: events)
            rounds.append(current)
        }

        var round: FixtureRound { lock.withLock { current } }

        func nextRound() {
            lock.withLock {
                current = FixtureRound(events: events)
                rounds.append(current)
            }
        }

        func collector(manualDeadline: Bool = true) -> DiagnosticsExport.LogCollector {
            if manualDeadline {
                return DiagnosticsExport.LogCollector(
                    submitWorker: { self.round.submit($0) },
                    awaitDeadline: { try await self.round.awaitDeadline($0) }
                )
            }
            return DiagnosticsExport.LogCollector(submitWorker: { self.round.submit($0) })
        }

        func start(
            _ collector: DiagnosticsExport.LogCollector,
            read: @escaping @Sendable () throws -> AnySequence<DiagnosticsExport.LogEntry>
        ) -> Task<DiagnosticsExport.LogResult, any Error> {
            events.record("request started: timeout 0.2")
            let waiter = Task {
                do {
                    let result = try await collector.collect(timeout: 0.2, outputLimit: 1024, read: read)
                    self.events.record("waiter outcome: timedOut=\(result.timedOut), bytes=\(result.output.utf8.count)")
                    return result
                } catch {
                    self.events.record("waiter outcome: error \(String(describing: error))")
                    throw error
                }
            }
            lock.withLock { waiters.append(waiter) }
            return waiter
        }

        func blockedRead(_ boundary: BlockedBoundary) -> AnySequence<DiagnosticsExport.LogEntry> {
            if boundary == .provider {
                block(boundary)
                return AnySequence([DiagnosticsExportTests.entry("late provider result")])
            }
            return AnySequence {
                AnyIterator {
                    self.block(boundary)
                    return DiagnosticsExportTests.entry("late iterator result")
                }
            }
        }

        private func block(_ boundary: BlockedBoundary) {
            probe.block {
                events.record("\(boundary.rawValue) entered")
                entered.resolve(.success(()))
            }
            events.record("\(boundary.rawValue) exited")
        }

        func releaseReader(reason: String) {
            events.record("reader released: \(reason)")
            probe.unblock()
        }

        func cleanup() async {
            // Mandatory bounded draining must continue even when its fixture
            // caller is canceled. Awaiting this task's value still joins it.
            await Task.detached { await self.drain() }.value
        }

        private func drain() async {
            releaseReader(reason: "cleanup")
            let state = lock.withLock { (rounds, waiters) }
            for round in state.0 {
                do { try await round.cleanup(onWaitInstalled: onCleanupWaitInstalled) }
                catch { Issue.record("Fixture cleanup failed: \(error)\n\(events.description)") }
            }
            for waiter in state.1 {
                // Cancellation is teardown only; scenario assertions never use it as a deadline.
                waiter.cancel()
                _ = await waiter.result
            }
            // A request can submit work while the first cleanup snapshot is
            // empty. Its continuation-install closure has returned once the
            // waiter settles, so drain that captured work before teardown ends.
            for round in state.0 {
                do { try await round.cleanup(onWaitInstalled: onCleanupWaitInstalled) }
                catch { Issue.record("Late fixture cleanup failed: \(error)\n\(events.description)") }
            }
            #expect(!probe.didReachWatchdog, "Reader watchdog fired\n\(events.description)")
            print("Diagnostics fixture events:\n\(events.description)")
        }
    }

    private static func withDeadlineFixture(
        fixture: DeadlineFixture = DeadlineFixture(),
        _ body: (DeadlineFixture) async throws -> Void
    ) async throws {
        do {
            try await body(fixture)
        } catch {
            if let watchdog = error as? FixtureWatchdog {
                Issue.record("Five-second fixture watchdog fired awaiting \(watchdog.event)\n\(fixture.events.description)")
            }
            await fixture.cleanup()
            throw error
        }
        await fixture.cleanup()
    }

    private static func collectAfterWorkerExit(_ collector: DiagnosticsExport.LogCollector) async throws -> DiagnosticsExport.LogResult {
        let deadline = ContinuousClock.now + .seconds(2)
        while true {
            do {
                return try await collector.collect(timeout: 1, outputLimit: 1024) {
                    AnySequence([entry("collection after exit")])
                }
            } catch DiagnosticsExport.CollectionError.alreadyCollecting {
                if ContinuousClock.now >= deadline { throw DiagnosticsExport.CollectionError.alreadyCollecting }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    @Test
    func currentProcessEntriesAppearInReport() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let report = try await Self.report {
            try await collector.collect(timeout: 1, outputLimit: 1024) {
                AnySequence([Self.entry("current fixture <private>")])
            }
        }
        #expect(report.contains("current fixture <private>"))
    }

    @Test
    func unrelatedAndOldEntriesAreExcluded() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let result = try await collector.collect(timeout: 1, outputLimit: 1024) {
            AnySequence([
                Self.entry("foreign process", pid: -1),
                Self.entry("foreign subsystem", subsystem: "com.example.Other"),
                Self.entry("old entry", date: Date().addingTimeInterval(-301)),
                Self.entry("valid entry")
            ])
        }
        #expect(result.output.contains("valid entry"))
        #expect(!result.output.contains("foreign process"))
        #expect(!result.output.contains("foreign subsystem"))
        #expect(!result.output.contains("old entry"))
    }

    @Test
    func emptyEntriesProduceValidEmptyResult() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let result = try await collector.collect(timeout: 1, outputLimit: 1024) { AnySequence([]) }
        #expect(result.output.isEmpty)
        #expect(!result.timedOut)
        #expect(!result.truncated)
        let report = try await Self.report { result }
        #expect(report.contains("current launch"))
        #expect(report.contains("No matching retained entries"))
        #expect(!report.contains("(no logs)"))
    }

    @Test
    func unicodeByteBoundaryRemainsValid() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let result = try await collector.collect(timeout: 1, outputLimit: 180) {
            AnySequence([Self.entry("UNICODE " + String(repeating: "🙂é", count: 80))])
        }
        #expect(result.output.utf8.count <= 180)
        #expect(result.output.contains("UNICODE 🙂é")) // Cap reaches beyond the formatted prefix.
        #expect(!result.output.contains("�"))
        #expect(result.truncated)
    }

    @Test
    func candidateScanIsBounded() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        let result = try await collector.collect(timeout: 1, outputLimit: 1024) {
            AnySequence {
                var remaining = 20_000
                return AnyIterator<DiagnosticsExport.LogEntry> {
                    guard remaining > 0 else { return nil }
                    remaining -= 1
                    probe.recordCandidate()
                    return Self.entry("rejected candidate", pid: -1)
                }
            }
        }
        #expect(probe.candidateCount == 10_000)
        #expect(result.output.isEmpty)
        #expect(result.truncated)
        let report = try await Self.report { result }
        #expect(report.contains("may be incomplete"))
        #expect(!report.contains("Log excerpt limited to 1 MiB."))
    }

    @Test(arguments: BlockedBoundary.allCases)
    func blockedReadDeliversDeadlineAndRetainsOwnership(boundary: BlockedBoundary) async throws {
        try await Self.withDeadlineFixture { fixture in
            let collector = fixture.collector()
            let waiter = fixture.start(collector) { fixture.blockedRead(boundary) }
            #expect(try await fixture.round.armed.wait() == 0.2)
            let worker = try await fixture.round.captured.wait()
            worker.run()
            try await fixture.entered.wait()
            #expect(fixture.probe.startCount == 1)
            #expect(fixture.probe.exitCount == 0)
            fixture.round.releaseDeadline(reason: "observed blocked \(boundary.rawValue)")
            let result = try await waiter.value
            #expect(result.timedOut)
            #expect(result.output.isEmpty)
            #expect(!result.truncated)
            #expect(result.outputLimit == 1024)
            #expect(result.candidateLimit == 10_000)
            #expect(fixture.probe.exitCount == 0)
            await #expect(throws: DiagnosticsExport.CollectionError.alreadyCollecting) {
                try await collector.collect(timeout: 0.2, outputLimit: 1024) {
                    fixture.probe.recordStart()
                    return AnySequence([])
                }
            }
            #expect(fixture.probe.startCount == 1)
            let report = try await Self.report { result }
            #expect(report.contains("deadline reached"))
            #expect(!report.contains("No matching retained entries"))
            let busyReport = try await Self.report {
                try await collector.collect(timeout: 0.2, outputLimit: 1024) { AnySequence([]) }
            }
            #expect(busyReport.contains("collection is still in progress"))
            fixture.releaseReader(reason: "assertions complete")
            try await worker.finished.wait()
            #expect(fixture.probe.exitCount == 1)
            fixture.nextRound()
            let fresh = fixture.start(collector) { AnySequence([Self.entry("fresh collection")]) }
            #expect(try await fixture.round.armed.wait() == 0.2)
            let freshWorker = try await fixture.round.captured.wait()
            freshWorker.run()
            let next = try await fresh.value
            try await freshWorker.finished.wait()
            #expect(!next.timedOut)
            #expect(next.output.contains("fresh collection"))
            #expect(!next.output.contains("late \(boundary.rawValue) result"))
        }
    }

    @Test
    func deadlineBeforeQueuedWorkerSkipsReadAndRetainsOwnership() async throws {
        try await Self.withDeadlineFixture { fixture in
            let collector = fixture.collector()
            let waiter = fixture.start(collector) {
                fixture.probe.recordStart()
                return AnySequence([Self.entry("unstarted provider")])
            }
            #expect(try await fixture.round.armed.wait() == 0.2)
            let worker = try await fixture.round.captured.wait()
            fixture.round.releaseDeadline(reason: "worker remains queued")
            #expect(try await waiter.value.timedOut)
            #expect(fixture.probe.startCount == 0)
            await #expect(throws: DiagnosticsExport.CollectionError.alreadyCollecting) {
                try await collector.collect(timeout: 0.2, outputLimit: 1024) {
                    fixture.probe.recordStart()
                    return AnySequence([])
                }
            }
            #expect(fixture.probe.startCount == 0)
            worker.run()
            try await worker.finished.wait()
            #expect(fixture.probe.startCount == 0)
            fixture.nextRound()
            let fresh = fixture.start(collector) { AnySequence([Self.entry("fresh after queued exit")]) }
            #expect(try await fixture.round.armed.wait() == 0.2)
            let freshWorker = try await fixture.round.captured.wait()
            freshWorker.run()
            let result = try await fresh.value
            try await freshWorker.finished.wait()
            #expect(!result.timedOut)
            #expect(result.output.contains("fresh after queued exit"))
            #expect(!result.output.contains("unstarted provider"))
        }
    }

    @Test
    func productionDefaultTimerTimesOutQueuedWorkerWithinOneSecond() async throws {
        try await Self.withDeadlineFixture { fixture in
            let collector = fixture.collector(manualDeadline: false)
            let start = ContinuousClock.now
            let waiter = fixture.start(collector) {
                fixture.probe.recordStart()
                return AnySequence([])
            }
            let worker = try await fixture.round.captured.wait()
            let result = try await waiter.value
            let elapsed = start.duration(to: .now)
            fixture.events.record("production default timer elapsed: \(elapsed)")
            #expect(result.timedOut)
            #expect(elapsed < .seconds(1),
                    "Production default timer/task progress:\n\(fixture.events.description)")
            #expect(fixture.probe.startCount == 0)
            worker.run()
            try await worker.finished.wait()
            #expect(fixture.probe.startCount == 0)
        }
    }

    private enum CompletionObservation: Sendable, Equatable {
        case waiting, returned, failed
    }

    @Test
    func canceledFixtureCallerDrainsActualWorkerAndPreservesCompletion() async throws {
        let events = FixtureEvents()
        let callerWaiting = FixtureSignal<Void>("caller completion observer installed", events: events)
        let callerCanceled = FixtureSignal<Void>("caller completion observer canceled", events: events)
        let cleanupProgress = FixtureSignal<CompletionObservation>("cleanup progress", events: events)
        let durableProgress = FixtureSignal<CompletionObservation>("durable observer progress", events: events)
        let exitHeld = FixtureSignal<Void>("independent worker exit hold entered", events: events)
        let actualReturn = FixtureSignal<Void>("independent actual worker return", events: events)
        let exitHold = ReaderProbe()
        let fixture = DeadlineFixture(events: events) {
            events.record("cleanup completion observer installed")
            cleanupProgress.resolve(.success(.waiting))
        }
        try await Self.withDeadlineFixture(fixture: fixture) { fixture in
            defer {
                exitHold.unblock()
                #expect(!exitHold.didReachWatchdog, "Independent worker-exit watchdog fired")
            }
            let collector = fixture.collector()
            let waiter = fixture.start(collector) {
                let entries = fixture.blockedRead(.provider)
                // Cleanup opens the normal reader/deadline gates, but cannot
                // release this independent hold inside the real provider call.
                exitHold.block {
                    events.record("independent worker exit hold entered")
                    exitHeld.resolve(.success(()))
                }
                return entries
            }
            let worker = try await fixture.round.captured.wait()
            #expect(try await fixture.round.armed.wait() == 0.2)
            worker.run {
                events.record("independent actual worker return acknowledged")
                actualReturn.resolve(.success(()))
            }
            try await fixture.entered.wait()

            let caller = Task {
                do {
                    try await Self.withDeadlineFixture(fixture: fixture) { _ in
                        do {
                            try await worker.finished.wait {
                                events.record("caller completion observer installed")
                                callerWaiting.resolve(.success(()))
                            }
                            Issue.record("Canceled completion observer returned success")
                        } catch is CancellationError {
                            events.record("caller completion observer resumed once: cancellation")
                            callerCanceled.resolve(.success(()))
                            throw CancellationError()
                        }
                    }
                } catch is CancellationError {
                    events.record("fixture caller resumed once: cancellation after cleanup")
                } catch {
                    Issue.record("Unexpected fixture caller error: \(error)")
                }
                cleanupProgress.resolve(.success(.returned))
            }
            var durableObserver: Task<Void, Never>?
            do {
                try await callerWaiting.wait()
                events.record("fixture caller canceled while actual work pending")
                caller.cancel()
                try await callerCanceled.wait()
                try await exitHeld.wait()
                #expect(exitHold.exitCount == 0)
                #expect(try await cleanupProgress.wait() == .waiting,
                        "Cleanup returned while actual worker exit was held\n\(events.description)")

                let observer = Task {
                    do {
                        try await worker.finished.wait {
                            events.record("durable completion observer installed")
                            durableProgress.resolve(.success(.waiting))
                        }
                        events.record("durable completion observer resumed once: actual return")
                        durableProgress.resolve(.success(.returned))
                    } catch {
                        events.record("durable completion observer failed: \(error)")
                        durableProgress.resolve(.success(.failed))
                    }
                }
                durableObserver = observer
                #expect(try await durableProgress.wait() == .waiting,
                        "Canceled observer poisoned durable completion\n\(events.description)")
                #expect(exitHold.exitCount == 0)
                events.record("independent worker exit hold released")
                exitHold.unblock()
                try await actualReturn.wait()
                await observer.value
                await caller.value
                _ = await waiter.result
                // A new uncanceled observer must see durable actual completion.
                try await worker.finished.wait()
                #expect(exitHold.exitCount == 1)
                #expect(!exitHold.didReachWatchdog)
                let trace = events.description
                #expect(trace.components(separatedBy: "caller completion observer resumed once: cancellation").count == 2)
                #expect(trace.components(separatedBy: "durable completion observer resumed once: actual return").count == 2)
                #expect(trace.components(separatedBy: "fixture caller resumed once: cancellation after cleanup").count == 2)
            } catch {
                fixture.releaseReader(reason: "regression teardown")
                fixture.round.releaseDeadline(reason: "regression teardown")
                exitHold.unblock()
                caller.cancel()
                try await actualReturn.wait()
                await durableObserver?.value
                await caller.value
                #expect(!exitHold.didReachWatchdog)
                throw error
            }
        }
    }

    @Test
    func completedCapturedWorkerReleasesCollector() async throws {
        try await Self.withDeadlineFixture { fixture in
            var collector: DiagnosticsExport.LogCollector? = fixture.collector()
            weak var releasedCollector = collector
            let waiter = fixture.start(try #require(collector)) { AnySequence([]) }
            #expect(try await fixture.round.armed.wait() == 0.2)
            let worker = try await fixture.round.captured.wait()
            worker.run()
            #expect(!(try await waiter.value).timedOut)
            try await worker.finished.wait()
            collector = nil
            #expect(releasedCollector == nil,
                    "Completed captured work still retains its collector and fixture")
        }
    }

    @Test
    func cancellationBeforeStartDoesNotRead() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await collector.collect(timeout: 1, outputLimit: 1024) {
                probe.recordStart()
                return AnySequence([])
            }
        }
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(probe.startCount == 0)
        #expect(try await Self.collectAfterWorkerExit(collector).output.contains("collection after exit"))
    }

    @Test
    func cancellationDuringReadRetainsOwnership() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        defer {
            probe.unblock()
            #expect(!probe.didReachWatchdog, "Reader teardown watchdog fired")
        }
        let waiter = Task {
            try await collector.collect(timeout: 5, outputLimit: 1024) {
                probe.block()
                return AnySequence([Self.entry("late canceled result")])
            }
        }
        try #require(try await probe.waitForStart())
        let start = ContinuousClock.now
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(start.duration(to: .now) < .seconds(1))
        await #expect(throws: DiagnosticsExport.CollectionError.alreadyCollecting) {
            try await collector.collect(timeout: 1, outputLimit: 1024) {
                probe.recordStart()
                return AnySequence([])
            }
        }
        #expect(probe.startCount == 1)
        #expect(probe.exitCount == 0)
        probe.unblock()
        let next = try await Self.collectAfterWorkerExit(collector)
        #expect(next.output.contains("collection after exit"))
        #expect(!next.output.contains("late canceled result"))
    }

    private enum FixtureFailure: Error { case unavailable }

    @Test
    func providerFailureReleasesOwnership() async throws {
        let collector = DiagnosticsExport.LogCollector()
        await #expect(throws: FixtureFailure.unavailable) {
            try await collector.collect(timeout: 1, outputLimit: 1024) { throw FixtureFailure.unavailable }
        }
        let report = try await Self.report {
            try await collector.collect(timeout: 1, outputLimit: 1024) { throw FixtureFailure.unavailable }
        }
        #expect(report.contains("Log collection failed:"))
        #expect(report.contains("App Version:"))
        #expect(try await Self.collectAfterWorkerExit(collector).output.contains("collection after exit"))
    }

    @Test
    func invalidLimitsDoNotStartReader() async {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        let limits: [(TimeInterval, Int)] = [
            (0, 1024), (-1, 1024), (.nan, 1024), (.infinity, 1024),
            (-.infinity, 1024), (60.1, 1024), (1, 0), (1, -1), (1, 1_048_577)
        ]
        for (timeout, outputLimit) in limits {
            await #expect(throws: DiagnosticsExport.CollectionError.invalidLimits) {
                try await collector.collect(timeout: timeout, outputLimit: outputLimit) {
                    probe.recordStart()
                    return AnySequence([])
                }
            }
        }
        #expect(probe.startCount == 0)
    }
}
