import EventKit
import Foundation
import GlimpseCore

/// User-facing text for the create flow. Pure, so copy and VoiceOver labels are testable.
enum ScheduleCopy {
    private static let timeStyle = Date.FormatStyle.dateTime.hour().minute()
    private static let dayStyle = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
    private static let spokenDayStyle = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()

    static let choosingHint = "Choose a time with ↑ ↓, then press Return"
    static let selectedHint = "Return to add"
    static let searching = "Finding free times…"
    static let saving = "Saving…"
    static let requestingAccess = "Requesting calendar access…"
    static let needsAccess = "Glimpse needs calendar access to find free times."
    static let allowAccess = "Allow calendar access"
    static let allowAccessHint = "Click, or press Return when focused, to show the system prompt."
    static let openPrivacySettings = "Open Calendar Privacy Settings"
    static let otherIntentsStillWork = "Dates, ranges and questions still work."
    static let removing = "Removing…"
    static let removed = "Removed. Nothing was added."

    static func timeRange(_ slot: FreeSlot) -> String {
        "\(slot.start.formatted(timeStyle)) – \(slot.end.formatted(timeStyle))"
    }

    static func windowName(_ window: TimeWindow) -> String {
        switch window {
        case let .partOfDay(part): part.rawValue
        case .unspecified: "working hours"
        case let .between(from, to): "\(clock(from))–\(clock(to))"
        case let .exact(time): "around \(clock(time))"
        }
    }

    static func header(for draft: EventDraft, calendar: Calendar) -> String {
        let day = draft.day.date(in: calendar).map { $0.formatted(dayStyle) } ?? draft.day.iso
        return "\(day) · \(windowName(draft.window))"
    }

    static func freeTimes(_ count: Int) -> String {
        count == 1 ? "1 free time" : "\(count) free times"
    }

    static func draftLine(_ draft: EventDraft, calendar: WritableCalendar?) -> String {
        let target = calendar.map { " · saves to \($0.title)" } ?? ""
        return "\(draft.title) · \(duration(draft.durationMinutes))\(target)"
    }

    static func noSlots(_ draft: EventDraft, calendar: Calendar) -> String {
        let day = draft.day.date(in: calendar).map { $0.formatted(.dateTime.weekday(.wide)) } ?? draft.day.iso
        return "No free \(duration(draft.durationMinutes)) time \(day) \(windowName(draft.window)). Try another time."
    }

    static func slotAccessibilityLabel(_ slot: FreeSlot, title: String, calendar: WritableCalendar?) -> String {
        let target = calendar.map { ", to \($0.title)" } ?? ""
        let spokenRange = "\(slot.start.formatted(timeStyle)) to \(slot.end.formatted(timeStyle))"
        return "Add \(title), \(spokenRange), \(slot.start.formatted(spokenDayStyle))\(target)"
    }

    static func busyAccessibilityLabel(_ event: CalendarEvent) -> String {
        "Busy: \(event.title), \(event.startDate.formatted(timeStyle)) to \(event.endDate.formatted(timeStyle))"
    }

    static func accessUnavailable(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .restricted: "Calendar access is restricted on this Mac, so Glimpse can't add events."
        case .writeOnly: "Allow full calendar access so Glimpse can find free times."
        default: "Calendar access is off, so Glimpse can't add events."
        }
    }

    static func added(_ event: SavedEvent) -> String { "Added to \(event.calendarTitle)" }

    static func undoButton(remaining: Int) -> String { "Undo \(remaining)" }

    static func undoAccessibilityLabel(_ event: SavedEvent) -> String { "Undo adding \(event.title)" }

    static func undoAccessibilityValue(remaining: Int) -> String {
        remaining == 1 ? "1 second left" : "\(remaining) seconds left"
    }

    static func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    private static func clock(_ time: ClockTime) -> String {
        String(format: "%d:%02d", time.hour, time.minute)
    }
}
