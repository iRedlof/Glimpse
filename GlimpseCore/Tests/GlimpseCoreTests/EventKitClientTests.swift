import EventKit
import Foundation
import Testing

@testable import GlimpseCore

struct EventKitClientTests {
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
