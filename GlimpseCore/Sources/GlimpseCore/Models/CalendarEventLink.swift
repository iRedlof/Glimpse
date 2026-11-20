import Foundation

/// Builds the URL that opens an agenda event in Apple's Calendar app.
///
/// Calendar registers the `ical` URL scheme, and its own binary formats
/// `ical://ekevent/%@?method=show&options=more` to reveal an event. Opening that URL
/// through LaunchServices needs no entitlement in the App Sandbox; AppleScript would
/// (Apple Events need a temporary exception), `EKEventViewController` is iOS-only,
/// and no `ical://` form tried (epoch, `date/…`) selects a bare date.
///
/// - One-off event: `ical://ekevent/<itemIdentifier>?method=show&options=more`.
/// - Repeating event: the series shares one identifier, so the occurrence start is
///   inserted: `ical://ekevent/<yyyyMMddTHHmmssZ>/<itemIdentifier>?…`. Timed starts are
///   written in UTC; all-day starts are floating, so their local wall time is written.
/// - No identifier: `ical://`, which only brings Calendar forward.
public enum CalendarEventLink {
    public static let calendarAppURLString = "ical://"
    static let eventQuery = "method=show&options=more"
    /// RFC 3986 unreserved characters; anything else in an identifier is percent-encoded.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// The most precise Calendar URL for `event`. `timeZone` is the user's zone, used
    /// only for all-day (floating) occurrences.
    public static func url(for event: CalendarEvent, timeZone: TimeZone = .current) -> URL? {
        guard let identifier = event.itemIdentifier,
              let encoded = identifier.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return URL(string: calendarAppURLString) }
        var path = "ekevent"
        if event.isRecurring {
            let zone = event.isAllDay ? timeZone : TimeZone(identifier: "UTC") ?? timeZone
            path += "/" + occurrenceStamp(event.startDate, in: zone)
        }
        return URL(string: "\(calendarAppURLString)\(path)/\(encoded)?\(eventQuery)")
    }

    /// `yyyyMMdd'T'HHmmss'Z'` from calendar components (no shared formatter state).
    static func occurrenceStamp(_ date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let fields = [parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second]
            .map { $0 ?? 0 }
        return String(format: "%04d%02d%02dT%02d%02d%02dZ",
                      fields[0], fields[1], fields[2], fields[3], fields[4], fields[5])
    }
}
