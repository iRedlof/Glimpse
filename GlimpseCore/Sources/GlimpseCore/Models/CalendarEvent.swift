import Foundation

public struct CalendarEvent: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    /// False for all-day and "free" events, which never make a time busy.
    public let blocksTime: Bool
    /// EventKit's `calendarItemIdentifier`: the handle Calendar's `ical://ekevent/` link accepts.
    /// Nil when EventKit gave none; then Calendar can only be brought forward.
    public let itemIdentifier: String?
    /// A repeating series shares one item identifier, so its link also names the occurrence.
    public let isRecurring: Bool
    /// The current user declined this invitation; it never counts as the next meeting.
    public let isDeclined: Bool
    /// A strict video-call link found on the event (URL, location or notes), if any.
    public let meetingLink: MeetingLink?
    /// A physical place (whitespace collapsed), or nil for none or a virtual/URL location.
    /// Drives leave-by and trips; never sent anywhere.
    public let location: String?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        blocksTime: Bool = true,
        itemIdentifier: String? = nil,
        isRecurring: Bool = false,
        isDeclined: Bool = false,
        meetingLink: MeetingLink? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.blocksTime = blocksTime
        self.itemIdentifier = itemIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        self.isRecurring = isRecurring
        self.isDeclined = isDeclined
        self.meetingLink = meetingLink
        self.location = Self.physicalLocation(location)
    }

    /// Location strings calendar apps fill in for calls, not places.
    static let virtualPlaceholders: Set<String> = [
        "zoom", "zoom meeting", "microsoft teams meeting", "microsoft teams", "teams",
        "google meet", "facetime", "webex", "online", "virtual", "phone", "phone call",
    ]

    /// A placeholder, also when prefixed "Join" / "Join the" ("Join Zoom Meeting").
    static func isVirtualPlaceholder(_ lowered: String) -> Bool {
        let unprefixed = ["join the ", "join "].first { lowered.hasPrefix($0) }
            .map { String(lowered.dropFirst($0.count)) } ?? lowered
        return virtualPlaceholders.contains(unprefixed)
    }

    /// Trimmed, whitespace-collapsed place; nil when empty, a URL, or a call placeholder.
    public static func physicalLocation(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        let lowered = collapsed.lowercased()
        guard !collapsed.isEmpty, !lowered.contains("://"), !lowered.contains("www."),
              !isVirtualPlaceholder(lowered)
        else { return nil }
        return collapsed
    }

    public var timeString: String { timeString(style: TimeFormatter.shortTime) }

    func timeString(style: Date.FormatStyle) -> String {
        if isAllDay { return "All day" }
        return "\(startDate.formatted(style)) – \(endDate.formatted(style))"
    }
}
