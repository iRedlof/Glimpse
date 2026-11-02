import Foundation

enum CalendarKeyboardOwner: String, CaseIterable, Hashable, Sendable {
    case grid, previousMonth, today, nextMonth, searchPrompt, searchDismiss, editor
}

enum CalendarKeyboardKey: Sendable {
    case left, right, up, down, returnKey, keypadEnter, space, tab, other

    init(nativeCode: UInt16) {
        switch nativeCode {
        case 123: self = .left
        case 124: self = .right
        case 126: self = .up
        case 125: self = .down
        case 36: self = .returnKey
        case 76: self = .keypadEnter
        case 49: self = .space
        case 48: self = .tab
        default: self = .other
        }
    }
}

enum CalendarKeyboardPhase: Sendable {
    case down, repeatPress, up
}

struct CalendarKeyboardContext: Sendable {
    var visible = true
    var key = true
    var eventForPanel = true
    var recording = false
    var preferences = false
    var modified = false
    var editingText = false

    static let eligible = Self()

    var allowsRouting: Bool {
        visible && key && eventForPanel && !recording && !preferences
            && !modified && !editingText
    }
}

enum CalendarKeyboardBrowseOwnership: Equatable, Sendable {
    case windowDefault
    case designated(CalendarKeyboardOwner)
    case ambiguous
}

enum CalendarBrowseIntent: Equatable, Sendable {
    case previousMonth, nextMonth, previousYear, nextYear, today
}

enum CalendarKeyboardRoute: Equatable, Sendable {
    case yield, consume, activate, move(Int), browse(CalendarBrowseIntent)
}

enum CalendarKeyboardRouter {
    static func local(
        _ key: CalendarKeyboardKey, phase: CalendarKeyboardPhase,
        owner: CalendarKeyboardOwner, context: CalendarKeyboardContext,
        isEnabled: Bool = true
    ) -> CalendarKeyboardRoute {
        guard context.allowsRouting, phase != .up, owner != .editor else { return .yield }
        if owner == .grid {
            guard isEnabled else { return .yield }
            switch key {
            case .left: return .move(-1)
            case .right: return .move(1)
            case .up: return .move(-7)
            case .down: return .move(7)
            case .returnKey, .keypadEnter, .space:
                return phase == .down ? .activate : .consume
            default: return .yield
            }
        }
        guard key == .returnKey || key == .keypadEnter || key == .space else { return .yield }
        guard isEnabled else { return .consume }
        return phase == .down ? .activate : .consume
    }

    static func browse(
        _ key: CalendarKeyboardKey, phase: CalendarKeyboardPhase,
        ownership: CalendarKeyboardBrowseOwnership, context: CalendarKeyboardContext
    ) -> CalendarKeyboardRoute {
        guard context.allowsRouting, phase != .up, ownership == .windowDefault else { return .yield }
        switch key {
        case .left: return .browse(.previousMonth)
        case .right: return .browse(.nextMonth)
        case .up: return .browse(.previousYear)
        case .down: return .browse(.nextYear)
        case .returnKey, .keypadEnter:
            return phase == .down ? .browse(.today) : .consume
        default: return .yield
        }
    }

    static func ownership(
        published: CalendarKeyboardOwner?, observed: Bool,
        responderIsWindowDefault: Bool, snapshotMatchesResponder: Bool
    ) -> CalendarKeyboardBrowseOwnership {
        if let published { return .designated(published) }
        guard observed, responderIsWindowDefault, snapshotMatchesResponder else { return .ambiguous }
        return .windowDefault
    }

    static func move(
        _ anchor: Date?, by delta: Int, days: [Date], calendar: Calendar
    ) -> Date? {
        guard days.count == 42, let anchor,
              let index = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: anchor) })
        else { return nil }
        return days[min(41, max(0, index + delta))]
    }

    static func reconcile(
        _ current: Date?, days: [Date], selected: Date?, today: Date,
        displayedMonth: Date, calendar: Calendar
    ) -> Date? {
        guard days.count == 42 else { return nil }
        for candidate in [current, selected, today] {
            if let candidate, let visible = days.first(where: {
                calendar.isDate($0, inSameDayAs: candidate)
            }) {
                return visible
            }
        }
        return days.first {
            calendar.isDate($0, equalTo: displayedMonth, toGranularity: .month)
        }
    }
}
