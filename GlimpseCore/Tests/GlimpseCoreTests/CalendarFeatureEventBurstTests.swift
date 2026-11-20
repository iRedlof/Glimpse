import ComposableArchitecture
import EventKit
import Foundation
import Testing

@testable import GlimpseCore

/// Regression for back-to-back event refreshes. TCA registers a `.run` effect's
/// cancellation only after it hops to the global executor, so effects sent in the
/// same main-actor turn can register out of order. With `cancelInFlight` an older
/// query could cancel the newest, leaving the agenda loading forever.
@MainActor
struct CalendarFeatureEventBurstTests {
    private static let burstSize = 3
    private static let iterations = 150
    /// Bounds a positive wait; never a latency budget.
    private static let hangGuard: Duration = .seconds(10)

    @Test
    func backToBackRefreshesKeepNewestQueryAndCancelEverySupersededOne() async throws {
        for iteration in 0..<Self.iterations {
            try await runBurst(iteration: iteration)
        }
    }

    private func runBurst(iteration: Int) async throws {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let event = CalendarEvent(id: "current", title: "Current", startDate: day, endDate: day, isAllDay: false)
        let queries = BurstQueries()
        var state = CalendarFeature.State(displayedMonth: day)
        state.calendarAuthorizationStatus = .fullAccess
        state.selectedDate = day
        let store = Store(initialState: state) {
            CalendarFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { _ in try await queries.enter() }
        }

        // Same main-actor turn: no suspension between the refreshes.
        for _ in 0..<Self.burstSize { store.send(.retryEvents) }

        try await waitUntil("all burst queries enter (iteration \(iteration))") {
            queries.entered.value == Self.burstSize
        }
        // Exactly the newest query survives; each superseded one is cancelled.
        try await waitUntil("superseded queries are cancelled (iteration \(iteration))") {
            queries.cancelled.value == Self.burstSize - 1
        }
        queries.resumeUncancelled(with: [event])
        try await waitUntil("newest result renders (iteration \(iteration))") {
            !store.isLoadingEvents
        }
        #expect(store.events == [event])
        #expect(store.eventsError == nil)
        #expect(queries.resumedLive.value == 1)
    }

    private func waitUntil(_ reason: String, _ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: Self.hangGuard)
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out: \(reason)")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

/// Fake client query that suspends until released and honors cancellation.
private final class BurstQueries: Sendable {
    private struct Query {
        var continuation: CheckedContinuation<[CalendarEvent], any Error>?
        var isCancelled = false
    }

    let entered = LockIsolated(0)
    let cancelled = LockIsolated(0)
    let resumedLive = LockIsolated(0)
    private let queries = LockIsolated<[UUID: Query]>([:])

    func enter() async throws -> [CalendarEvent] {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let alreadyCancelled = queries.withValue { queries in
                    if queries[id]?.isCancelled == true { return true }
                    queries[id] = Query(continuation: continuation)
                    return false
                }
                entered.withValue { $0 += 1 }
                if alreadyCancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            cancelled.withValue { $0 += 1 }
            let continuation = queries.withValue { queries in
                let continuation = queries[id]?.continuation
                queries[id] = Query(continuation: nil, isCancelled: true)
                return continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func resumeUncancelled(with events: [CalendarEvent]) {
        let live = queries.withValue { queries in
            let live = queries.values.filter { !$0.isCancelled }.compactMap(\.continuation)
            for id in queries.keys { queries[id]?.continuation = nil }
            return live
        }
        resumedLive.setValue(live.count)
        for continuation in live { continuation.resume(returning: events) }
    }
}
