import Foundation

/// Shared time formatters for event times, meeting chips and menu bar segments.
///
/// `Date.FormatStyle` is thread-safe and auto-updates its default locale and time zone,
/// so one shared style is enough. Never use `DateFormatter` in hot paths or computed
/// properties — it's not thread-safe.
public enum TimeFormatter {
    /// Shared locale-aware short time ("9:05 AM" or "09:05" in 24-hour locales).
    /// Thread-safe, auto-updating locale/timezone.
    public static let shortTime = Date.FormatStyle(date: .omitted, time: .shortened)

    /// Clock-only time for menu bar chips ("8:40", no AM/PM).
    /// Pass the calendar and locale to match the calling context.
    public static func clockOnly(calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .omitted)
            .hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return style
    }
}
