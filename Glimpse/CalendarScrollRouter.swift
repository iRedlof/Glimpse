import Foundation

struct CalendarScrollRouter {
    enum Direction: Equatable, Sendable {
        case previous, next
    }

    enum Phase: Equatable, Sendable {
        case none, began, changed, ended, cancelled
    }

    struct Result {
        let direction: Direction?
        let consumesEvent: Bool
    }

    private enum GestureOwner {
        case calendar, suppressedCalendar, viewport
    }

    private static let maximumContribution: CGFloat = 1.5
    private static let threshold: CGFloat = 5
    private var accumulator: CGFloat = 0
    private var gestureOwner: GestureOwner?

    mutating func reset() {
        accumulator = 0
        gestureOwner = nil
    }

    mutating func suspendNavigation() {
        accumulator = 0
        if gestureOwner == .calendar {
            gestureOwner = .suppressedCalendar
        }
    }

    mutating func route(
        delta: CGFloat, panelVisible: Bool, eventIsForPanel: Bool, overCalendar: Bool,
        recordingShortcut: Bool, contentOverflows: Bool,
        phase: Phase = .none, momentumPhase: Phase = .none
    ) -> Result {
        guard panelVisible, eventIsForPanel else {
            reset()
            return Result(direction: nil, consumesEvent: false)
        }
        let eligible = overCalendar && !recordingShortcut && !contentOverflows
        if phase == .none, momentumPhase == .none {
            // A discrete wheel event terminates ownership left by a trackpad gesture.
            if gestureOwner != nil { reset() }
            return routeDiscrete(delta: delta, eligible: eligible)
        }

        if phase == .began {
            accumulator = 0
            gestureOwner = eligible ? .calendar : .viewport
        } else if gestureOwner == nil {
            accumulator = 0
            gestureOwner = .viewport
        }
        if gestureOwner == .calendar, !eligible || !delta.isFinite {
            suspendNavigation()
        }

        let terminal = phase == .ended || phase == .cancelled
            || momentumPhase == .ended || momentumPhase == .cancelled
        let direction = gestureOwner == .calendar && !terminal
            ? accumulate(delta: delta) : nil
        let result = Result(
            direction: direction,
            consumesEvent: gestureOwner == .calendar || gestureOwner == .suppressedCalendar
        )
        // Finger end retains the chosen owner for momentum. No timer is needed:
        // momentum end/cancel, a new finger begin, or discrete input finishes it.
        if phase == .cancelled || momentumPhase == .ended || momentumPhase == .cancelled {
            reset()
        }
        return result
    }

    private mutating func routeDiscrete(delta: CGFloat, eligible: Bool) -> Result {
        guard eligible, delta.isFinite else {
            reset()
            return Result(direction: nil, consumesEvent: false)
        }
        guard delta != 0 else { return Result(direction: nil, consumesEvent: false) }
        return Result(direction: accumulate(delta: delta), consumesEvent: true)
    }

    private mutating func accumulate(delta: CGFloat) -> Direction? {
        accumulator += max(-Self.maximumContribution, min(Self.maximumContribution, delta))
        if accumulator > Self.threshold {
            accumulator = 0
            return .previous
        }
        if accumulator < -Self.threshold {
            accumulator = 0
            return .next
        }
        return nil
    }
}
