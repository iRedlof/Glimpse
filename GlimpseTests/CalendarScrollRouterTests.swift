import Foundation
import Testing
@testable import Glimpse

private extension CalendarScrollRouter {
    mutating func wheel(
        _ delta: CGFloat = 1.5,
        visible: Bool = true,
        matchingWindow: Bool = true,
        calendar: Bool = true,
        recording: Bool = false,
        overflow: Bool = false,
        phase: Phase = .none,
        momentum: Phase = .none
    ) -> Result {
        route(
            delta: delta, panelVisible: visible, eventIsForPanel: matchingWindow,
            overCalendar: calendar, recordingShortcut: recording, contentOverflows: overflow,
            phase: phase, momentumPhase: momentum
        )
    }
}

struct CalendarScrollRouterTests {
    // Catches the released monitor's simultaneous month navigation and viewport pass-through.
    @Test(arguments: [
        CGFloat(1.5), -1.5, 100, -100, .greatestFiniteMagnitude, -.greatestFiniteMagnitude
    ])
    func fourClampedContributionsNavigateExclusively(delta: CGFloat) {
        var router = CalendarScrollRouter()
        for _ in 0..<3 {
            let result = router.wheel(delta)
            #expect(result.direction == nil)
            #expect(result.consumesEvent)
        }
        let result = router.wheel(delta)
        #expect(result.direction == (delta > 0 ? .previous : .next))
        #expect(result.consumesEvent)
        #expect(router.wheel(delta).direction == nil)
    }

    @Test(arguments: [CGFloat(1), -1])
    func thresholdIsStrict(delta: CGFloat) {
        var router = CalendarScrollRouter()
        for _ in 0..<5 {
            #expect(router.wheel(delta).direction == nil)
        }
        #expect(router.wheel(delta).direction == (delta > 0 ? .previous : .next))
    }

    @Test
    func oppositeContributionsCancel() {
        var router = CalendarScrollRouter()
        for _ in 0..<3 { _ = router.wheel() }
        for _ in 0..<3 {
            #expect(router.wheel(-1.5).direction == nil)
        }
        #expect(router.wheel().direction == nil)
    }

    @Test
    func discreteZeroPassesWithoutDiscardingEligibleAccumulation() {
        var router = CalendarScrollRouter()
        for _ in 0..<3 { _ = router.wheel() }
        let zero = router.wheel(0)
        #expect(zero.direction == nil)
        #expect(!zero.consumesEvent)
        #expect(router.wheel().direction == .previous)
    }

    @Test
    func overflowNeverNavigatesOrConsumesDiscreteInput() {
        var router = CalendarScrollRouter()
        for _ in 0..<8 {
            let result = router.wheel(100, overflow: true)
            #expect(result.direction == nil)
            #expect(!result.consumesEvent)
        }
    }

    // Removing the reset on any context branch leaks a nearly-complete month gesture.
    @Test(arguments: ["overflow", "settings", "hidden", "otherWindow", "recording", "nan"])
    func ineligibleDiscreteEventClearsPartialAccumulation(context: String) {
        var router = CalendarScrollRouter()
        for _ in 0..<3 { _ = router.wheel() }
        let interrupted = router.wheel(
            context == "nan" ? .nan : 1.5,
            visible: context != "hidden", matchingWindow: context != "otherWindow",
            calendar: context != "settings", recording: context == "recording",
            overflow: context == "overflow"
        )
        #expect(interrupted.direction == nil)
        #expect(!interrupted.consumesEvent)
        #expect(router.wheel().direction == nil)
    }

    @Test(arguments: [CGFloat.nan, .infinity, -.infinity])
    func nonfiniteDiscreteDeltaPassesAndResets(delta: CGFloat) {
        var router = CalendarScrollRouter()
        for _ in 0..<3 { _ = router.wheel() }
        let result = router.wheel(delta)
        #expect(result.direction == nil)
        #expect(!result.consumesEvent)
        #expect(router.wheel().direction == nil)
    }

    @Test
    func calendarGestureLosingEligibilityStaysConsumedAndSuppressed() {
        var router = CalendarScrollRouter()
        #expect(router.wheel(phase: .began).consumesEvent)
        _ = router.wheel(phase: .changed)
        _ = router.wheel(phase: .changed)
        let overflow = router.wheel(overflow: true, phase: .changed)
        #expect(overflow.consumesEvent)
        #expect(overflow.direction == nil)
        for _ in 0..<8 {
            let compactAgain = router.wheel(phase: .changed)
            #expect(compactAgain.consumesEvent)
            #expect(compactAgain.direction == nil)
        }
    }

    @Test(arguments: ["settings", "recording", "nan"])
    func calendarGestureContextLossSuppressesRemainder(context: String) {
        var router = CalendarScrollRouter()
        _ = router.wheel(phase: .began)
        let interrupted = router.wheel(
            context == "nan" ? .nan : 1.5,
            calendar: context != "settings", recording: context == "recording", phase: .changed
        )
        #expect(interrupted.consumesEvent)
        #expect(interrupted.direction == nil)
        for _ in 0..<8 {
            let result = router.wheel(phase: .changed)
            #expect(result.consumesEvent)
            #expect(result.direction == nil)
        }
    }

    @Test(arguments: ["overflow", "settings", "recording"])
    func viewportGestureNeverBecomesMonthNavigation(context: String) {
        var router = CalendarScrollRouter()
        let begin = router.wheel(
            calendar: context != "settings", recording: context == "recording",
            overflow: context == "overflow", phase: .began
        )
        #expect(!begin.consumesEvent)
        for _ in 0..<8 {
            let result = router.wheel(phase: .changed)
            #expect(!result.consumesEvent)
            #expect(result.direction == nil)
        }
    }

    @Test(arguments: [true, false])
    func fingerEndRetainsOwnerForMomentum(calendarOwner: Bool) {
        var router = CalendarScrollRouter()
        _ = router.wheel(overflow: !calendarOwner, phase: .began)
        let fingerEnd = router.wheel(100, phase: .ended)
        #expect(fingerEnd.consumesEvent == calendarOwner)
        #expect(fingerEnd.direction == nil)
        for _ in 0..<2 {
            let result = router.wheel(momentum: .began)
            #expect(result.consumesEvent == calendarOwner)
            #expect(result.direction == nil)
        }
        let fourth = router.wheel(momentum: .changed)
        #expect(fourth.consumesEvent == calendarOwner)
        #expect(fourth.direction == (calendarOwner ? .previous : nil))
    }

    @Test(arguments: ["fingerCancel", "momentumEnd", "momentumCancel"], [true, false])
    func terminalEventReturnsOwnershipThenClearsIt(terminal: String, calendarOwner: Bool) {
        var router = CalendarScrollRouter()
        _ = router.wheel(overflow: !calendarOwner, phase: .began)
        _ = router.wheel(phase: .changed)
        _ = router.wheel(phase: .changed)
        let end = router.wheel(
            100, phase: terminal == "fingerCancel" ? .cancelled : .none,
            momentum: terminal == "momentumEnd" ? .ended :
                (terminal == "momentumCancel" ? .cancelled : .none)
        )
        #expect(end.consumesEvent == calendarOwner)
        #expect(end.direction == nil)
        let unseen = router.wheel(phase: .changed)
        #expect(!unseen.consumesEvent)
        #expect(unseen.direction == nil)
    }

    @Test(arguments: ["changed", "ended", "momentumBegin", "momentumChange"])
    func unseenPhasedStartConservativelyPasses(context: String) {
        var router = CalendarScrollRouter()
        for _ in 0..<8 {
            let result = router.wheel(
                phase: context == "changed" ? .changed : (context == "ended" ? .ended : .none),
                momentum: context == "momentumBegin" ? .began :
                    (context == "momentumChange" ? .changed : .none)
            )
            #expect(!result.consumesEvent)
            #expect(result.direction == nil)
        }
    }

    @Test
    func suspensionConsumesOnlyVisibleMatchingCalendarGesture() {
        var router = CalendarScrollRouter()
        _ = router.wheel(phase: .began)
        router.suspendNavigation()
        for _ in 0..<8 {
            let result = router.wheel(phase: .changed)
            #expect(result.consumesEvent)
            #expect(result.direction == nil)
        }
        let other = router.wheel(matchingWindow: false, phase: .changed)
        #expect(!other.consumesEvent)
        #expect(other.direction == nil)
        #expect(!router.wheel(phase: .changed).consumesEvent)
        _ = router.wheel(phase: .began)
        router.suspendNavigation()
        #expect(!router.wheel(visible: false, phase: .changed).consumesEvent)
        #expect(!router.wheel(phase: .changed).consumesEvent)
    }

    @Test
    func suspensionPreservesViewportOwnership() {
        var router = CalendarScrollRouter()
        _ = router.wheel(overflow: true, phase: .began)
        router.suspendNavigation()
        for _ in 0..<8 {
            let result = router.wheel(phase: .changed)
            #expect(!result.consumesEvent)
            #expect(result.direction == nil)
        }
    }

    @Test
    func freshBeginRestoresNavigationAfterSuspension() {
        var router = CalendarScrollRouter()
        _ = router.wheel(phase: .began)
        router.suspendNavigation()
        #expect(router.wheel(phase: .began).direction == nil)
        for _ in 0..<2 {
            #expect(router.wheel(phase: .changed).direction == nil)
        }
        #expect(router.wheel(phase: .changed).direction == .previous)
    }

    @Test
    func freshBeginEndsViewportOwnershipAndClearsOldCalendarAccumulation() {
        var router = CalendarScrollRouter()
        _ = router.wheel(overflow: true, phase: .began)
        #expect(router.wheel(phase: .began).consumesEvent)
        _ = router.wheel(phase: .changed)
        _ = router.wheel(phase: .changed)
        #expect(router.wheel(phase: .began).direction == nil)
        for _ in 0..<2 {
            #expect(router.wheel(phase: .changed).direction == nil)
        }
        #expect(router.wheel(phase: .changed).direction == .previous)
    }

    @Test
    func suspensionAfterFingerEndSuppressesMomentum() {
        var router = CalendarScrollRouter()
        _ = router.wheel(phase: .began)
        _ = router.wheel(phase: .ended)
        router.suspendNavigation()
        for _ in 0..<8 {
            let result = router.wheel(momentum: .changed)
            #expect(result.consumesEvent)
            #expect(result.direction == nil)
        }
    }

    @Test
    func resetClearsOwnershipAndDiscreteAccumulation() {
        var router = CalendarScrollRouter()
        _ = router.wheel(phase: .began)
        router.reset()
        #expect(!router.wheel(phase: .changed).consumesEvent)
        for _ in 0..<3 { _ = router.wheel() }
        router.reset()
        #expect(router.wheel().direction == nil)
    }

    @Test
    func suspensionClearsDiscreteAccumulation() {
        var router = CalendarScrollRouter()
        for _ in 0..<3 { _ = router.wheel() }
        router.suspendNavigation()
        #expect(router.wheel().direction == nil)
    }

    @Test
    func discreteEventEndsOldGestureAndStartsFreshAccumulation() {
        var router = CalendarScrollRouter()
        _ = router.wheel(phase: .began)
        _ = router.wheel(phase: .changed)
        _ = router.wheel(phase: .changed)
        #expect(router.wheel().direction == nil)
        for _ in 0..<2 { #expect(router.wheel().direction == nil) }
        #expect(router.wheel().direction == .previous)
    }

    @Test
    func zeroDeltaCalendarPhaseRetainsExclusiveOwnership() {
        var router = CalendarScrollRouter()
        let result = router.wheel(0, phase: .began)
        #expect(result.direction == nil)
        #expect(result.consumesEvent)
    }
}
