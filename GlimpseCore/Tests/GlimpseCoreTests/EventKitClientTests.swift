import ComposableArchitecture
import EventKit
import Foundation
import Testing

@testable import GlimpseCore

struct EventKitClientTests {
    @Test
    func canceledFetchSkipsAuthorization() async {
        let authorization = DeniedAuthorization()
        let store = EventStore(authorizationStatus: { authorization.status() })
        let fetch = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.fetchEvents(for: Date(timeIntervalSince1970: 1_000_000))
        }

        await #expect(throws: CancellationError.self) { try await fetch.value }
        #expect(authorization.calls == 0)
    }

    @Test
    func queuedCanceledFetchesSkipAuthorization() async throws {
        try await QueuedCancellationFixture().run(blockOnMainThread: false)
    }

    @Test
    func queuedCanceledFetchesSkipAuthorizationWhenMainThreadIsBlocked() async throws {
        try await QueuedCancellationFixture().run(blockOnMainThread: true)
    }

    @Test
    func withheldMainAdmissionUnwindsFetchAndLateWorkCannotBlock() async throws {
        try await QueuedCancellationFixture().verifyWithheldMainAdmission()
    }

    @Test
    func withheldObserverCompletionUnwindsFetchAndLateWorkCannotResumeTwice() async throws {
        try await QueuedCancellationFixture().verifyWithheldObserverCompletion()
    }

    @Test
    @MainActor
    func queuedCancellationSurvivesRealTestStoreScheduling() async throws {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let store = TestStore(initialState: CalendarFeature.State(displayedMonth: date)) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(date)
            $0.eventKitClient.authorizationStatus = { .notDetermined }
        }
        #expect(store.useMainSerialExecutor)
        await store.send(.togglePin) { $0.isPinned = true }
        try await QueuedCancellationFixture().run(blockOnMainThread: false)
        try await QueuedCancellationFixture().run(blockOnMainThread: true)
        // A real action after coordination keeps TestStore and its normal
        // process-wide scheduling behavior alive across both blocked callbacks.
        await store.send(.togglePin) { $0.isPinned = false }
    }

    @Test
    func coordinationFinishReleasesMissingObserversAndRejectsLateMessages() async throws {
        try await QueuedCancellationFixture().verifyMessageCleanup()
    }

    @Test
    func uncanceledDeniedFetchPreservesAccessError() async {
        let authorization = DeniedAuthorization()
        let store = EventStore(authorizationStatus: { authorization.status() })

        await #expect(throws: EventKitClient.QueryError.accessUnavailable) {
            try await store.fetchEvents(for: Date(timeIntervalSince1970: 1_000_000))
        }
        #expect(authorization.calls == 1)
    }

    @Test(arguments: [(2026, 3, 8, 23), (2026, 11, 1, 25), (2026, 3, 9, 24)])
    func localDayIntervalUsesCalendarBoundaries(year: Int, month: Int, day: Int, hours: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let selected = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        let expectedStart = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        let expectedEnd = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day + 1)))
        let interval = try EventKitClient.eventsInterval(for: selected, calendar: calendar)

        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
        #expect(interval.duration == TimeInterval(hours * 3_600))
    }

    @Test
    func eventConversionSkipsMissingDatesAndUsesStableFallbackIdentity() throws {
        let event = EKEvent(eventStore: EKEventStore())
        #expect(EventKitClient.calendarEvent(from: event) == nil)
        event.title = "Overnight"
        event.startDate = Date(timeIntervalSince1970: 1_000_000)
        event.endDate = Date(timeIntervalSince1970: 1_100_000)
        let first = try #require(EventKitClient.calendarEvent(from: event))
        let repeated = try #require(EventKitClient.calendarEvent(from: event))

        #expect(!first.id.isEmpty)
        #expect(first.id == repeated.id)
        #expect(first.title == "Overnight")
        #expect(first.startDate == Date(timeIntervalSince1970: 1_000_000))
        #expect(first.endDate == Date(timeIntervalSince1970: 1_100_000))
        #expect(!first.isAllDay)
        // EventKit normalizes dates when all-day is set; check this conversion
        // separately from the timed event's exact date preservation.
        event.isAllDay = true
        #expect(try #require(EventKitClient.calendarEvent(from: event)).isAllDay)
    }
}

// TestStore redirects global async resumptions to main, including suspended
// continuation waits. Bootstrap/obsolete entry run on this independent actor;
// a separate Dispatch coordinator observes their messages synchronously. Only
// its final completion resumes asynchronously, after releasing the main hold.
private actor QueuedCancellationFixture {
    private nonisolated let executor = FixtureExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    func run(blockOnMainThread: Bool) async throws {
        let entered = FixtureMessages<Void>()
        let ready = FixtureMessages<Void>()
        let activeFinished = FixtureMessages<Result<[CalendarEvent], any Error>>()
        let obsoleteFinished = FixtureMessages<Result<[CalendarEvent], any Error>>()
        // Deadlines only fail/clean up a broken fixture; success requires handshakes.
        let deadline = DispatchTime.now() + 10
        let gate = AuthorizationGate(deadline: deadline, entered: entered)
        let finish: @Sendable () -> Void = {
            gate.close()
            entered.finish()
            ready.finish()
            activeFinished.finish()
            obsoleteFinished.finish()
        }
        let cleanup = DispatchWorkItem(block: finish)
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: cleanup)
        let authorization = DeniedAuthorization()
        let store = EventStore(authorizationStatus: {
            let status = authorization.status()
            if authorization.calls == 1 {
                let released: Bool
                if blockOnMainThread && !Thread.isMainThread {
                    released = gate.hold(schedule: { DispatchQueue.main.async(execute: $0) })
                } else {
                    released = gate.hold()
                }
                #expect(released, "Authorization admission and release must finish before cleanup")
            }
            return status
        })
        // Always release the synchronous actor blocker, including on assertion failure.
        defer {
            cleanup.cancel()
            finish()
        }
        let date = Date(timeIntervalSince1970: 1_000_000)
        // Keep the blocker on the caller's potentially main/serial lane. Only
        // orchestration and obsolete request entry use our independent executor.
        let active = Task { @MainActor in
            do {
                activeFinished.publish(.success(try await store.fetchEvents(for: date)))
            } catch {
                activeFinished.publish(.failure(error))
            }
        }
        defer { active.cancel() }
        try #require(entered.next(until: deadline) != nil, "Authorization did not enter before cleanup")

        // Create these while isolated here, before any coordinator suspension.
        // Their first actor jobs can publish readiness while main is blocked.
        let obsolete = (0..<20).map { _ in
            Task {
                await self.obsoleteFetch(
                    store: store, date: date, ready: ready,
                    finished: obsoleteFinished
                )
            }
        }
        defer { obsolete.forEach { $0.cancel() } }
        let observed = await observeCancellation(until: deadline, cleanup: finish) {
            var readyCount = 0
            for _ in obsolete {
                guard ready.next(until: deadline) != nil else { break }
                readyCount += 1
            }
            obsolete.forEach { $0.cancel() }
            gate.close()
            let activeResult = activeFinished.next(until: deadline)
            let results = obsolete.map { _ in obsoleteFinished.next(until: deadline) }
            return CancellationObservations(readyCount: readyCount, active: activeResult, obsolete: results)
        }
        let observations = try #require(observed, "Observer did not finish before cleanup")
        try #require(observations.readyCount == 20, "All requests must start before cancellation/release")
        let activeResult = try #require(observations.active, "Active fetch did not finish before cleanup")
        #expect(throws: EventKitClient.QueryError.accessUnavailable) { try activeResult.get() }
        for observation in observations.obsolete {
            let result = try #require(observation, "Obsolete fetch did not finish before cleanup")
            #expect(throws: CancellationError.self) { try result.get() }
        }
        // The one uncanceled blocker is the only request allowed to check access.
        #expect(authorization.calls == 1)
    }

    func verifyWithheldMainAdmission() async throws {
        let entered = FixtureMessages<Void>()
        let pending = FixtureMessages<AuthorizationGate.Work>()
        let callbackFinished = FixtureMessages<Bool>()
        let activeFinished = FixtureMessages<Result<[CalendarEvent], any Error>>()
        let lateFinished = FixtureMessages<Void>()
        let deadline = DispatchTime.now() + 10
        let gate = AuthorizationGate(deadline: .now() + 1, entered: entered)
        let finish: @Sendable () -> Void = {
            gate.close()
            entered.finish()
            pending.finish()
            callbackFinished.finish()
            activeFinished.finish()
            lateFinished.finish()
        }
        let cleanup = DispatchWorkItem(block: finish)
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: cleanup)
        defer {
            cleanup.cancel()
            finish()
        }
        let authorization = DeniedAuthorization()
        let store = EventStore(authorizationStatus: {
            // Withhold the same gate's scheduling boundary, without blocking main
            // itself or duplicating its timeout/late-admission policy.
            let released = gate.hold(schedule: { pending.publish($0) })
            callbackFinished.publish(released)
            return authorization.status()
        })
        let active = Task { @MainActor in
            do {
                activeFinished.publish(
                    .success(try await store.fetchEvents(for: Date(timeIntervalSince1970: 1_000_000)))
                )
            } catch {
                activeFinished.publish(.failure(error))
            }
        }
        defer { active.cancel() }
        let lateWork = try #require(pending.next(until: deadline), "Gate work was not scheduled")
        let callbackReleased = callbackFinished.next(until: deadline)
        try #require(callbackReleased != nil, "Callback did not unwind")
        #expect(callbackReleased == false)
        let result = try #require(activeFinished.next(until: deadline), "Active fetch did not unwind")
        #expect(throws: EventKitClient.QueryError.accessUnavailable) { try result.get() }
        #expect(authorization.calls == 1)

        // Only admit saved work after observing both callback and fetch completion.
        DispatchQueue.main.async {
            lateWork()
            lateFinished.publish(())
        }
        try #require(lateFinished.next(until: deadline) != nil, "Late main work did not finish")
        entered.finish()
        var entryCount = 0
        while entered.next(until: deadline) != nil { entryCount += 1 }
        #expect(entryCount == 0, "Expired main work must not introduce a new authorization hold")
    }

    func verifyWithheldObserverCompletion() async throws {
        let entered = FixtureMessages<Void>()
        let pending = FixtureMessages<AuthorizationGate.Work>()
        let activeFinished = FixtureMessages<Result<[CalendarEvent], any Error>>()
        let lateFinished = FixtureMessages<Void>()
        let deadline = DispatchTime.now() + 1
        let observationDeadline = DispatchTime.now() + 10
        let gate = AuthorizationGate(deadline: observationDeadline, entered: entered)
        defer {
            gate.close()
            entered.finish()
            pending.finish()
            activeFinished.finish()
            lateFinished.finish()
        }
        let authorization = DeniedAuthorization()
        let store = EventStore(authorizationStatus: {
            let status = authorization.status()
            #expect(gate.hold(), "Observer cleanup must release the real authorization hold")
            return status
        })
        let active = Task { @MainActor in
            do {
                activeFinished.publish(.success(try await store.fetchEvents(for: Date(timeIntervalSince1970: 1_000_000))))
            } catch {
                activeFinished.publish(.failure(error))
            }
        }
        defer { active.cancel() }
        try #require(entered.next(until: observationDeadline) != nil, "Authorization did not enter")
        let observed = await observeCancellation(
            until: deadline, cleanup: { gate.close() },
            schedule: { pending.publish($0) }
        ) {
            gate.close()
            return CancellationObservations(
                readyCount: 0, active: activeFinished.next(until: deadline), obsolete: []
            )
        }
        #expect(observed == nil, "Withheld observer admission must reach bounded failure")
        let result = try #require(activeFinished.next(until: observationDeadline), "Deadline cleanup did not unwind fetch")
        #expect(throws: EventKitClient.QueryError.accessUnavailable) { try result.get() }
        #expect(authorization.calls == 1)
        let lateWork = try #require(pending.next(until: observationDeadline), "Observer work was not saved")
        DispatchQueue(label: "GlimpseCoreTests.late-observer").async {
            lateWork()
            lateFinished.publish(())
        }
        try #require(lateFinished.next(until: observationDeadline) != nil, "Late observer work did not finish")
    }

    // Only this final observer callback suspends asynchronously. Its deadline
    // closes the real hold first, then resolves missing admission/completion.
    private func observeCancellation(
        until deadline: DispatchTime, cleanup: @escaping @Sendable () -> Void,
        schedule: AuthorizationGate.Scheduler = {
            DispatchQueue(label: "GlimpseCoreTests.cancellation-observer").async(execute: $0)
        },
        work: @escaping @Sendable () -> CancellationObservations
    ) async -> CancellationObservations? {
        await withCheckedContinuation { continuation in
            let completion = CancellationCompletion(continuation)
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                completion.finish(nil, beforeResume: cleanup)
            }
            schedule { completion.finish(work()) }
        }
    }

    func verifyMessageCleanup() async throws {
        let buffered = FixtureMessages<Int>()
        let missing = FixtureMessages<Int>()
        let ready = FixtureMessages<Void>()
        let completed = FixtureMessages<Bool>()
        let deadline = DispatchTime.now() + 10
        defer {
            buffered.finish()
            missing.finish()
            ready.finish()
            completed.finish()
        }
        buffered.publish(11)
        buffered.publish(22)
        buffered.finish()
        buffered.publish(99)
        #expect(buffered.next(until: deadline) == 11)
        #expect(buffered.next(until: deadline) == 22)
        #expect(buffered.next(until: deadline) == nil)

        for _ in 0..<3 {
            DispatchQueue(label: "GlimpseCoreTests.missing-observation").async {
                let result = missing.next(until: deadline, onWait: { ready.publish(()) })
                completed.publish(result == nil)
            }
        }
        for _ in 0..<3 {
            try #require(ready.next(until: deadline) != nil, "Observer did not register a wait")
        }
        missing.finish()
        missing.finish()
        missing.publish(99)
        for _ in 0..<3 {
            let unblocked = completed.next(until: deadline)
            try #require(unblocked != nil, "Missing observation was not released by finish")
            #expect(unblocked == true)
        }
        #expect(missing.next(until: deadline) == nil)
    }

    private func obsoleteFetch(
        store: EventStore, date: Date, ready: FixtureMessages<Void>,
        finished: FixtureMessages<Result<[CalendarEvent], any Error>>
    ) async {
        ready.publish(())
        do {
            finished.publish(.success(try await store.fetchEvents(for: date)))
        } catch {
            finished.publish(.failure(error))
        }
    }
}

private struct CancellationObservations: Sendable {
    let readyCount: Int
    let active: Result<[CalendarEvent], any Error>?
    let obsolete: [Result<[CalendarEvent], any Error>?]
}

// The final continuation is consumed once under the lock and resumed outside
// it. Deadline and late observer completion may race; the losing callback is inert.
private final class CancellationCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CancellationObservations?, Never>?

    init(_ continuation: CheckedContinuation<CancellationObservations?, Never>) {
        self.continuation = continuation
    }

    func finish(
        _ observations: CancellationObservations?, beforeResume: @Sendable () -> Void = {}
    ) {
        let pending = lock.withLock {
            let pending = continuation
            continuation = nil
            return pending
        }
        guard let pending else { return }
        beforeResume()
        pending.resume(returning: observations)
    }
}

// Buffer, waiter count and closed state are lock-protected. The semaphore wakes
// readers after publication/finish; every read is bounded by the same absolute
// deadline. Finish wakes all registered readers and rejects later publications.
// These synchronous waits avoid TestStore's process-wide global async-job hook.
private final class FixtureMessages<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let available = DispatchSemaphore(value: 0)
    private var buffered: [Element] = []
    private var waiters = 0
    private var closed = false

    func publish(_ value: Element) {
        let accepted = lock.withLock {
            guard !closed else { return false }
            buffered.append(value)
            return true
        }
        if accepted { available.signal() }
    }

    func finish() {
        let pending = lock.withLock {
            closed = true
            return waiters
        }
        for _ in 0..<pending { available.signal() }
    }

    func next(until deadline: DispatchTime, onWait: (@Sendable () -> Void)? = nil) -> Element? {
        while DispatchTime.now() < deadline {
            lock.lock()
            if !buffered.isEmpty {
                let value = buffered.removeFirst()
                lock.unlock()
                return value
            }
            if closed {
                lock.unlock()
                return nil
            }
            waiters += 1
            lock.unlock()
            onWait?()
            let awakened = available.wait(timeout: deadline) == .success
            lock.withLock { waiters -= 1 }
            guard awakened else { return nil }
        }
        return nil
    }
}

// Mutable closed/result state is protected by the lock. Semaphores synchronize
// the synchronous callback and scheduled work; the deadline and message channel
// are immutable. Closing releases any admitted hold and makes late work inert.
private final class AuthorizationGate: @unchecked Sendable {
    typealias Work = @Sendable () -> Void
    typealias Scheduler = @Sendable (@escaping Work) -> Void

    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private let deadline: DispatchTime
    private let entered: FixtureMessages<Void>
    private var closed = false
    private var releaseSucceeded = false

    init(deadline: DispatchTime, entered: FixtureMessages<Void>) {
        self.deadline = deadline
        self.entered = entered
    }

    func hold(schedule: Scheduler? = nil) -> Bool {
        let finished = DispatchSemaphore(value: 0)
        let work: Work = { [self] in
            defer { finished.signal() }
            guard lock.withLock({ !closed && DispatchTime.now() < deadline }) else { return }
            entered.publish(())
            let released = release.wait(timeout: deadline) == .success
            lock.withLock { releaseSucceeded = released }
        }
        if let schedule {
            schedule(work)
            guard finished.wait(timeout: deadline) == .success else {
                close()
                return false
            }
        } else {
            work()
        }
        let released = lock.withLock { releaseSucceeded }
        close()
        return released
    }

    func close() {
        lock.withLock { closed = true }
        release.signal()
    }
}

// The immutable serial queue runs one job at a time; no mutable state is shared.
private final class FixtureExecutor: SerialExecutor {
    private let queue = DispatchQueue(label: "GlimpseCoreTests.queued-cancellation")

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}

// All mutable state is guarded by the lock; no native authorization or reads occur.
private final class DeniedAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    var calls: Int {
        lock.withLock { callCount }
    }

    func status() -> EKAuthorizationStatus {
        lock.withLock {
            callCount += 1
            return .denied
        }
    }
}
