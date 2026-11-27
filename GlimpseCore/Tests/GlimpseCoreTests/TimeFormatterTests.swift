import Foundation
import Testing

@testable import GlimpseCore

/// Shared time formatters respect the user's locale (12- or 24-hour) through thread-safe
/// `Date.FormatStyle` values instead of `DateFormatter`s in hot paths.
struct TimeFormatterTests {
    private let utc = TimeZone(identifier: "UTC")!

    /// 2026-11-20 09:05:00 UTC.
    private let testDate = Date(timeIntervalSince1970: 1_795_165_500)

    private func shortTimeStyle(_ identifier: String) -> Date.FormatStyle {
        var style = TimeFormatter.shortTime.locale(Locale(identifier: identifier))
        style.timeZone = utc
        return style
    }

    private func clockOnlyStyle(_ identifier: String) -> Date.FormatStyle {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return TimeFormatter.clockOnly(calendar: cal, locale: Locale(identifier: identifier))
    }

    @Test
    func shortTimeUsesAMPMForTwelveHourLocale() {
        let text = testDate.formatted(shortTimeStyle("en_US"))
        // Formatters may use a narrow no-break space before AM/PM.
        #expect(text.replacingOccurrences(of: "\u{202F}", with: " ") == "9:05 AM")
    }

    @Test
    func shortTimeUsesTwentyFourHourFormatForBritishLocale() {
        // Date.FormatStyle .shortened does not pad single-digit hours.
        #expect(testDate.formatted(shortTimeStyle("en_GB")) == "9:05")
    }

    @Test
    func clockOnlyOmitsAMPMForTwelveHourLocale() {
        let text = testDate.formatted(clockOnlyStyle("en_US"))
        // Should show "9:05" without AM/PM.
        #expect(text == "9:05")
    }

    @Test
    func clockOnlyOmitsAMPMForTwentyFourHourLocale() {
        let text = testDate.formatted(clockOnlyStyle("en_GB"))
        // .defaultDigits does not pad single-digit hours.
        #expect(text == "9:05")
    }
}
