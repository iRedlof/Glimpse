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
        meetingLink: MeetingLink? = nil
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
    }

    /// Locale-aware short time ("9:05 AM" or "09:05"). `Date.FormatStyle` is a thread-safe
    /// value; its default locale and time zone auto-update, so one shared style is enough.
    static let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)

    public var timeString: String { timeString(style: Self.timeStyle) }

    func timeString(style: Date.FormatStyle) -> String {
        if isAllDay { return "All day" }
        return "\(startDate.formatted(style)) – \(endDate.formatted(style))"
    }
}
