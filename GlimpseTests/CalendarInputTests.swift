import Testing

@testable import Glimpse

struct CalendarInputTests {
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
