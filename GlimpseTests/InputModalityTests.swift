import AppKit
import ComposableArchitecture
import Observation
import Testing

@testable import Glimpse

@Suite("Input modality")
struct InputModalityTests {
    @Test(arguments: [NSEvent.EventType.keyDown])
    func keyPressesMeanKeyboard(type: NSEvent.EventType) {
        #expect(InputModality(eventType: type) == .keyboard)
    }

    @Test(arguments: [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel])
    func clicksAndScrollsMeanPointer(type: NSEvent.EventType) {
        #expect(InputModality(eventType: type) == .pointer)
    }

    /// Releases, drags, hover and modifier presses say nothing: a click's mouse-up or a held
    /// Shift must not flip the modality the press already set.
    @Test(arguments: [
        NSEvent.EventType.keyUp, .flagsChanged, .leftMouseUp, .rightMouseUp, .otherMouseUp,
        .mouseMoved, .leftMouseDragged, .mouseEntered, .mouseExited, .appKitDefined,
    ])
    func otherEventsLeaveTheModalityAlone(type: NSEvent.EventType) {
        #expect(InputModality(eventType: type) == nil)
    }

    @Test
    func theMonitorWatchesEveryModalitySignal() {
        for type in [NSEvent.EventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel] {
            #expect(InputModality.monitoredEvents.contains(NSEvent.EventTypeMask(type: type)))
        }
        #expect(!InputModality.monitoredEvents.contains(.keyUp))
        #expect(!InputModality.monitoredEvents.contains(.leftMouseUp))
    }
}

@Suite("Input modality tracker") @MainActor
struct InputModalityTrackerTests {
    @Test
    func startsWithoutRingsUntilTheKeyboardIsUsed() {
        let tracker = InputModalityTracker()
        #expect(tracker.modality == .pointer)
        #expect(!tracker.showsFocusRing)
        #expect(!tracker.isMonitoring)
    }

    @Test
    func keyboardShowsRingsAndAClickHidesThemAgain() {
        let tracker = InputModalityTracker()
        tracker.record(.keyDown)
        #expect(tracker.modality == .keyboard && tracker.showsFocusRing)
        tracker.record(.keyUp)
        #expect(tracker.showsFocusRing)
        tracker.record(.leftMouseDown)
        #expect(tracker.modality == .pointer && !tracker.showsFocusRing)
        tracker.record(.leftMouseUp)
        tracker.record(.flagsChanged)
        #expect(!tracker.showsFocusRing)
        tracker.note(.keyboard)
        #expect(tracker.showsFocusRing)
        tracker.record(.scrollWheel)
        #expect(!tracker.showsFocusRing)
    }

    @Test
    func observersHearFlipsButNotRepeats() {
        let tracker = InputModalityTracker()
        let changes = LockIsolated(0)
        func observe() {
            withObservationTracking { _ = tracker.modality } onChange: { changes.withValue { $0 += 1 } }
        }
        observe()
        tracker.note(.pointer)
        #expect(changes.value == 0)
        tracker.note(.keyboard)
        #expect(changes.value == 1)
        observe()
        tracker.record(.keyDown)
        #expect(changes.value == 1)
    }

    @Test
    func trackersAreIndependentOfTheSharedOne() {
        let tracker = InputModalityTracker()
        let shared = InputModalityTracker.shared.modality
        tracker.note(shared == .keyboard ? .pointer : .keyboard)
        #expect(InputModalityTracker.shared.modality == shared)
        #expect(InputModalityTracker.shared !== tracker)
    }

    /// End to end through AppKit dispatch: an owned offscreen window receives a real click.
    @Test
    func theMonitorRecordsDispatchedClicksOnceAndStops() throws {
        let tracker = InputModalityTracker()
        let window = InputModalityTestWindow()
        defer { tracker.stopMonitoring(); window.close() }
        tracker.note(.keyboard)
        tracker.startMonitoring()
        tracker.startMonitoring()
        #expect(tracker.isMonitoring)
        try window.click()
        #expect(tracker.modality == .pointer)
        tracker.stopMonitoring()
        #expect(!tracker.isMonitoring)
        tracker.note(.keyboard)
        try window.click()
        #expect(tracker.modality == .keyboard, "A stopped tracker no longer follows events")
    }
}

/// Never key or main, positioned off every screen: a click here reaches nothing else.
@MainActor
private final class InputModalityTestWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        let screens = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        setFrameOrigin(NSPoint(x: screens.minX - 200, y: screens.minY - 200))
        contentView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        orderBack(nil)
    }

    func click() throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 20, y: 20), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            try #require(event.window === self)
            NSApp.sendEvent(event)
        }
    }
}
