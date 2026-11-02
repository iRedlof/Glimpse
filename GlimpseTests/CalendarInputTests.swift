import AppKit
import Testing

@testable import Glimpse

struct CalendarInputTests {
    @Test func nativePhasesPreserveGestureOwnershipBoundaries() {
        #expect(CalendarPopoverView.scrollPhase(.mayBegin) == .began)
        #expect(CalendarPopoverView.scrollPhase(.began) == .began)
        #expect(CalendarPopoverView.scrollPhase(.changed) == .changed)
        #expect(CalendarPopoverView.scrollPhase(.stationary) == .changed)
        #expect(CalendarPopoverView.scrollPhase(.ended) == .ended)
        #expect(CalendarPopoverView.scrollPhase(.cancelled) == .cancelled)
        #expect(CalendarPopoverView.scrollPhase([]) == .none)
        #expect(CalendarPopoverView.scrollPhase([.cancelled, .ended, .began, .changed]) == .cancelled)
        #expect(CalendarPopoverView.scrollPhase([.ended, .began, .changed]) == .ended)
        #expect(CalendarPopoverView.scrollPhase([.mayBegin, .changed]) == .began)
    }

    @Test
    func hiddenPanelDoesNotHandleNavigation() {
        #expect(!CalendarPopoverView.shouldHandleNavigation(
            panelVisible: false, eventIsForPanel: true, editingText: false, modified: false
        ))
    }

    @Test
    func otherWindowDoesNotHandleNavigation() {
        #expect(!CalendarPopoverView.shouldHandleNavigation(
            panelVisible: true, eventIsForPanel: false, editingText: false, modified: false
        ))
    }

    @Test
    func textEditorKeepsArrowKeys() {
        #expect(!CalendarPopoverView.shouldHandleNavigation(
            panelVisible: true, eventIsForPanel: true, editingText: true, modified: false
        ))
    }

    @Test
    func modifiedShortcutsAreNotCalendarNavigation() {
        #expect(!CalendarPopoverView.shouldHandleNavigation(
            panelVisible: true, eventIsForPanel: true, editingText: false, modified: true
        ))
    }

    @Test
    func visibleCalendarHandlesUnmodifiedNavigation() {
        #expect(CalendarPopoverView.shouldHandleNavigation(
            panelVisible: true, eventIsForPanel: true, editingText: false, modified: false
        ))
    }
}
