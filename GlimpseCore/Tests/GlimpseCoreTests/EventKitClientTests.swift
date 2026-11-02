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
    func queuedCanceledFetchesSkipAuthorization() async {
        let entered = AsyncStream.makeStream(of: Void.self)
        let ready = AsyncStream.makeStream(of: Void.self)
        let release = DispatchSemaphore(value: 0)
        let authorization = DeniedAuthorization()
        let store = EventStore(authorizationStatus: {
            let status = authorization.status()
            if authorization.calls == 1 {
                entered.continuation.yield(())
                release.wait()
            }
            return status
        })
        // Always release the synchronous actor blocker, including on assertion failure.
        defer {
            release.signal()
            entered.continuation.finish()
            ready.continuation.finish()
        }
        let date = Date(timeIntervalSince1970: 1_000_000)
        let active = Task { try await store.fetchEvents(for: date) }
        var enteredIterator = entered.stream.makeAsyncIterator()
        await enteredIterator.next()

        let obsolete = (0..<20).map { _ in
            Task {
                ready.continuation.yield(())
                return try await store.fetchEvents(for: date)
            }
        }
        var readyIterator = ready.stream.makeAsyncIterator()
        for _ in obsolete {
            await readyIterator.next()
        }
        for fetch in obsolete {
            fetch.cancel()
        }
        release.signal()

        await #expect(throws: EventKitClient.QueryError.accessUnavailable) { try await active.value }
        for fetch in obsolete {
            await #expect(throws: CancellationError.self) { try await fetch.value }
        }
        // The one uncanceled blocker is the only request allowed to check access.
        #expect(authorization.calls == 1)
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
