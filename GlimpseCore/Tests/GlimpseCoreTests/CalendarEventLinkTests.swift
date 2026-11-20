import Foundation
import Testing

@testable import GlimpseCore

struct CalendarEventLinkTests {
    private static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!  // Fixed IANA zone, always present.
    private static let identifier = "9675DF46-4040-4762-A70B-6CD65DC01C36"

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
                             in zone: TimeZone = losAngeles) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }

    private static func event(
        itemIdentifier: String? = identifier, start: Date, allDay: Bool = false, recurring: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(id: "event-id", title: "Haircut", startDate: start, endDate: start.addingTimeInterval(3_600),
                      isAllDay: allDay, itemIdentifier: itemIdentifier, isRecurring: recurring)
    }

    @Test
    func oneOffTimedEventOpensByItemIdentifier() throws {
        let event = Self.event(start: try Self.date(2026, 11, 22, 12))
        #expect(CalendarEventLink.url(for: event, timeZone: Self.losAngeles)?.absoluteString
            == "ical://ekevent/\(Self.identifier)?method=show&options=more")
    }

    @Test
    func oneOffAllDayEventNeedsNoOccurrenceDate() throws {
        let event = Self.event(start: try Self.date(2026, 11, 26), allDay: true)
        #expect(CalendarEventLink.url(for: event, timeZone: Self.losAngeles)?.absoluteString
            == "ical://ekevent/\(Self.identifier)?method=show&options=more")
    }

    @Test
    func recurringTimedOccurrenceIsNamedByItsUTCStart() throws {
        // 9:30 PST is 17:30 UTC.
        let event = Self.event(start: try Self.date(2026, 11, 20, 9, 30), recurring: true)
        #expect(CalendarEventLink.url(for: event, timeZone: Self.losAngeles)?.absoluteString
            == "ical://ekevent/20261120T173000Z/\(Self.identifier)?method=show&options=more")
    }

    @Test
    func recurringTimedOccurrenceAcrossUTCMidnightKeepsTheUTCDay() throws {
        // 20:00 PST on Nov 20 is 04:00 UTC on Nov 21.
        let event = Self.event(start: try Self.date(2026, 11, 20, 20), recurring: true)
        #expect(CalendarEventLink.url(for: event, timeZone: Self.losAngeles)?.absoluteString
            == "ical://ekevent/20261121T040000Z/\(Self.identifier)?method=show&options=more")
    }

    @Test
    func recurringAllDayOccurrenceUsesItsFloatingLocalDay() throws {
        let event = Self.event(start: try Self.date(2026, 11, 26), allDay: true, recurring: true)
        #expect(CalendarEventLink.url(for: event, timeZone: Self.losAngeles)?.absoluteString
            == "ical://ekevent/20261126T000000Z/\(Self.identifier)?method=show&options=more")
    }

    @Test(arguments: [nil, ""] as [String?])
    func missingItemIdentifierOnlyOpensCalendar(identifier: String?) throws {
        let event = Self.event(itemIdentifier: identifier, start: try Self.date(2026, 11, 22, 12), recurring: true)
        #expect(event.itemIdentifier == nil)
        #expect(CalendarEventLink.url(for: event)?.absoluteString == "ical://")
    }

    @Test
    func reservedCharactersInIdentifierArePercentEncoded() throws {
        let event = Self.event(itemIdentifier: "A/B?C#D E:F", start: try Self.date(2026, 11, 22, 12))
        let url = try #require(CalendarEventLink.url(for: event))
        #expect(url.absoluteString == "ical://ekevent/A%2FB%3FC%23D%20E%3AF?method=show&options=more")
        #expect(url.scheme == "ical")
        #expect(url.query == "method=show&options=more")
    }

    @Test
    func occurrenceStampIsZeroPadded() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try Self.date(2027, 1, 2, 3, 4, in: utc).addingTimeInterval(5)
        #expect(CalendarEventLink.occurrenceStamp(date, in: utc) == "20270102T030405Z")
    }
}
