import Foundation
import Testing

@testable import GlimpseCore

/// Agenda row times follow the user's locale (12- or 24-hour) through one static,
/// thread-safe `Date.FormatStyle` instead of two `DateFormatter`s per row per body pass.
struct CalendarEventTimeStringTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func event(allDay: Bool = false) -> CalendarEvent {
        // 2026-11-20 14:05–15:30 UTC.
        let start = Date(timeIntervalSince1970: 1_795_183_500)
        return CalendarEvent(id: "e", title: "Standup", startDate: start, endDate: start.addingTimeInterval(5_100), isAllDay: allDay)
    }

    private func style(_ identifier: String) -> Date.FormatStyle {
        var style = CalendarEvent.timeStyle.locale(Locale(identifier: identifier))
        style.timeZone = utc
        return style
    }

    @Test
    func twelveHourLocaleUsesAMPM() {
        let text = event().timeString(style: style("en_US"))
        // Formatters may use a narrow no-break space before AM/PM.
        #expect(text.replacingOccurrences(of: "\u{202F}", with: " ") == "2:05 PM – 3:30 PM")
    }

    @Test
    func twentyFourHourLocaleOmitsAMPM() {
        #expect(event().timeString(style: style("en_GB")) == "14:05 – 15:30")
    }

    @Test
    func allDayIgnoresStyle() {
        #expect(event(allDay: true).timeString(style: style("en_GB")) == "All day")
        #expect(event(allDay: true).timeString == "All day")
    }

    @Test
    func defaultTimeStringUsesTheSharedStyle() {
        let event = event()
        #expect(event.timeString == event.timeString(style: CalendarEvent.timeStyle))
    }
}
