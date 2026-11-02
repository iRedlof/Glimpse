import AppIntents
import AppKit
import ComposableArchitecture
import Foundation
import GlimpseCore
import SwiftUI
import Testing
@testable import Glimpse

struct CalendarStatusItemTests {

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - nextMidnight computation

    @Test
    func nextMidnight_fromAfternoon_returnsTomorrowJustAfterMidnight() {
        let now = date(2026, 4, 14, 15, 30) // Apr 14 at 3:30 PM
        let midnight = CalendarStatusItem.nextMidnight(after: now)!

        let cal = Calendar.current
        #expect(cal.component(.day, from: midnight) == 15)
        #expect(cal.component(.month, from: midnight) == 4)
        #expect(cal.component(.hour, from: midnight) == 0)
        #expect(cal.component(.minute, from: midnight) == 0)
        #expect(cal.component(.second, from: midnight) == 1)
    }

    @Test
    func nextMidnight_fromLateNight_returnsTomorrowNotToday() {
        let now = date(2026, 4, 14, 23, 59) // Apr 14 at 11:59 PM
        let midnight = CalendarStatusItem.nextMidnight(after: now)!

        let cal = Calendar.current
        #expect(cal.component(.day, from: midnight) == 15)
        #expect(cal.component(.month, from: midnight) == 4)
    }

    @Test
    func nextMidnight_fromJustAfterMidnight_returnsTomorrowNotToday() {
        let now = date(2026, 4, 15, 0, 1) // Apr 15 at 12:01 AM
        let midnight = CalendarStatusItem.nextMidnight(after: now)!

        let cal = Calendar.current
        // Should be Apr 16, not Apr 15 again
        #expect(cal.component(.day, from: midnight) == 16)
        #expect(cal.component(.month, from: midnight) == 4)
    }

    @Test
    func nextMidnight_crossesMonthBoundary() {
        let now = date(2026, 4, 30, 20, 0) // Apr 30 at 8 PM
        let midnight = CalendarStatusItem.nextMidnight(after: now)!

        let cal = Calendar.current
        #expect(cal.component(.day, from: midnight) == 1)
        #expect(cal.component(.month, from: midnight) == 5)
    }

    @Test
    func nextMidnight_crossesYearBoundary() {
        let now = date(2026, 12, 31, 22, 0) // Dec 31 at 10 PM
        let midnight = CalendarStatusItem.nextMidnight(after: now)!

        let cal = Calendar.current
        #expect(cal.component(.day, from: midnight) == 1)
        #expect(cal.component(.month, from: midnight) == 1)
        #expect(cal.component(.year, from: midnight) == 2027)
    }

    @Test
    func nextMidnight_isAlwaysInTheFuture() {
        let now = date(2026, 4, 15, 12, 0)
        let midnight = CalendarStatusItem.nextMidnight(after: now)!
        #expect(midnight > now)
    }

    @Test
    func nextMidnight_fromExactMidnight_returnsTomorrowMidnight() {
        // Edge case: what if the timer fires exactly at midnight?
        let now = date(2026, 4, 15, 0, 0)
        let midnight = CalendarStatusItem.nextMidnight(after: now)!

        let cal = Calendar.current
        // Should schedule for Apr 16, not re-schedule for Apr 15
        #expect(cal.component(.day, from: midnight) == 16)
    }
}

@Suite(.serialized) @MainActor
struct CalendarShowTests {
    @Test
    func showIntentWithoutReadyTargetReportsFailure() async {
        let delegate = NSApplication.shared.delegate
        let delegateType = delegate.map { String(reflecting: type(of: $0)) } ?? "nil"
        print("SHOW-ROUTE host-delegate=\(delegateType) concrete-cast=\(delegate is AppDelegate)")
        await #expect(throws: (any Error).self) {
            _ = try await ShowCalendarIntent().perform()
        }
    }

    @Test(arguments: [false, true], [false, true])
    func repeatedVisibleShowPreservesPanelAndState(pinned: Bool, editing: Bool) throws {
        let fixture = ShowFixture()
        defer { fixture.close() }
        try fixture.owner.showCalendar()
        let panel = try #require(fixture.panel)
        fixture.browseAway()
        if pinned { fixture.store.send(.togglePin) }
        panel.isPinned = pinned
        panel.isTextInputActive = editing
        let before = fixture.store.state
        let loads = fixture.preferenceLoads.value
        for _ in 0..<2 { try fixture.owner.showCalendar() }
        #expect(panel.isVisible)
        #expect(fixture.panel === panel)
        #expect(fixture.allocations == 1)
        #expect(fixture.store.state == before)
        #expect(fixture.preferenceLoads.value == loads)
        #expect(panel.isPinned == pinned)
        #expect(panel.isTextInputActive == editing)
        #expect(fixture.shows == 1)
        #expect(fixture.hides == 0)
    }

    @Test
    func visibleShowPreservesNativeEditor() throws {
        let fixture = ShowFixture()
        defer { fixture.close() }
        try fixture.owner.showCalendar()
        let panel = try #require(fixture.panel)
        panel.isTextInputActive = true
        let field = NSTextField(frame: NSRect(x: 20, y: 50, width: 240, height: 24))
        field.stringValue = "Retained Show editor draft"
        let hosting = try #require(panel.contentView)
        let container = NSView(frame: hosting.frame)
        panel.contentView = container
        hosting.frame = container.bounds
        container.addSubview(hosting)
        container.addSubview(field)
        panel.activateForTextInput()
        #expect(panel.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 3, length: 5))
        let responder = panel.firstResponder
        for _ in 0..<2 { try fixture.owner.showCalendar() }
        #expect(panel.isVisible)
        #expect(panel.firstResponder === responder)
        #expect(field.currentEditor() === editor)
        #expect(editor.string == "Retained Show editor draft")
        #expect(editor.selectedRange() == NSRange(location: 3, length: 5))
        #expect(panel.isTextInputActive)
        #expect(fixture.shows == 1)
        #expect(fixture.hides == 0)
        panel.deactivateTextInput()
    }

    @Test
    func hiddenShowResetsOnceAndReusesPanel() throws {
        let fixture = ShowFixture()
        defer { fixture.close() }
        try fixture.owner.showCalendar()
        let panel = try #require(fixture.panel)
        fixture.browseAway()
        panel.orderOut(nil)
        let hiddenHides = fixture.hides
        #expect(hiddenHides > 0)
        let loads = fixture.preferenceLoads.value
        try fixture.owner.showCalendar()
        #expect(panel.isVisible)
        #expect(fixture.panel === panel)
        #expect(fixture.allocations == 1)
        #expect(fixture.store.selectedDate == ShowFixture.today)
        #expect(fixture.store.displayedMonth == ShowFixture.today)
        #expect(!fixture.store.showingPreferences)
        #expect(fixture.preferenceLoads.value == loads + 3)
        #expect(fixture.shows == 2)
        #expect(fixture.hides == hiddenHides)
    }

    @Test(arguments: [0, 1, 2, 3])
    func unavailableOrInvalidAnchorFailsBeforeHiddenPresentation(caseIndex: Int) {
        let fixture = ShowFixture()
        defer { fixture.close() }
        if caseIndex == 0 {
            fixture.anchor = nil
        } else {
            fixture.anchor = CalendarStatusItem.PanelAnchor(
                statusItemFrame: caseIndex == 2
                    ? NSRect(x: CGFloat.nan, y: -4000, width: 100, height: 24)
                    : ShowFixture.statusFrame,
                visibleFrame: caseIndex == 3
                    ? NSRect(x: -6000, y: -5000, width: 300, height: 1000)
                    : .zero
            )
        }
        #expect(throws: (any Error).self) { try fixture.owner.showCalendar() }
        #expect(fixture.panel == nil)
        #expect(fixture.allocations == 0)
        #expect(fixture.shows == 0)
        #expect(fixture.hides == 0)
        #expect(fixture.preferenceLoads.value == 0)
    }

    @Test
    func visibleShowReanchorsOrRetainsValidFrame() throws {
        let fixture = ShowFixture()
        defer { fixture.close() }
        try fixture.owner.showCalendar()
        let panel = try #require(fixture.panel)
        fixture.browseAway()
        let before = fixture.store.state
        fixture.anchor = CalendarStatusItem.PanelAnchor(
            statusItemFrame: NSRect(x: -4800, y: -4000, width: 100, height: 24),
            visibleFrame: ShowFixture.visibleFrame
        )
        try fixture.owner.showCalendar()
        #expect(panel.frame.minX == -4908)
        let retained = panel.frame
        fixture.anchor = nil
        try fixture.owner.showCalendar()
        #expect(panel.frame == retained)
        fixture.anchor = CalendarStatusItem.PanelAnchor(
            statusItemFrame: ShowFixture.statusFrame, visibleFrame: .zero
        )
        try fixture.owner.showCalendar()
        #expect(panel.frame == retained)
        #expect(panel.isVisible)
        #expect(fixture.store.state == before)
        #expect(fixture.shows == 1)
        #expect(fixture.hides == 0)
    }

    @Test
    func actualIntentUsesOwnedShow() async throws {
        let fixture = ShowFixture()
        defer { fixture.close() }
        let previous = CalendarShowCommand.shared.register { try fixture.owner.showCalendar() }
        defer { CalendarShowCommand.shared.register(previous) }
        _ = try await ShowCalendarIntent().perform()
        fixture.browseAway()
        let before = fixture.store.state
        _ = try await ShowCalendarIntent().perform()
        #expect(fixture.panel?.isVisible == true)
        #expect(fixture.store.state == before)
        #expect(fixture.shows == 1)
        #expect(fixture.hides == 0)
        fixture.panel?.orderOut(nil)
        fixture.anchor = nil
        await #expect(throws: (any Error).self) {
            _ = try await ShowCalendarIntent().perform()
        }
        #expect(fixture.panel?.isVisible == false)
        #expect(fixture.shows == 1)
    }

    @Test(arguments: [false, true])
    func reopenShowsForBothVisibilityFlags(hasVisibleWindows: Bool) throws {
        let fixture = ShowFixture()
        defer { fixture.close() }
        let command = CalendarShowCommand()
        command.register { try fixture.owner.showCalendar() }
        let delegate: NSApplicationDelegate = AppDelegate(
            calendarStatusItem: fixture.owner, showCommand: command
        )
        #expect(delegate.applicationShouldHandleReopen?(
            NSApplication.shared, hasVisibleWindows: hasVisibleWindows
        ) == false)
        #expect(fixture.panel?.isVisible == true)
        fixture.browseAway()
        let before = fixture.store.state
        #expect(delegate.applicationShouldHandleReopen?(
            NSApplication.shared, hasVisibleWindows: hasVisibleWindows
        ) == false)
        #expect(fixture.panel?.isVisible == true)
        #expect(fixture.store.state == before)
        #expect(fixture.shows == 1)
        #expect(fixture.hides == 0)
    }

    @Test
    func guardedStartupDoesNotRegisterOrShow() throws {
        _ = try #require(ProcessInfo.processInfo.environment["XCTestBundlePath"])
        let fixture = ShowFixture()
        defer { fixture.close() }
        let command = CalendarShowCommand()
        let delegate = AppDelegate(calendarStatusItem: fixture.owner, showCommand: command)
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        #expect(throws: (any Error).self) { try command.requestShow() }
        #expect(fixture.allocations == 0)
        #expect(fixture.shows == 0)
        #expect(fixture.preferenceLoads.value == 0)
    }

    @Test
    func delayedCrossScreenShowPreservesNewerVisibleState() throws {
        let fixture = ShowFixture(capturesCrossScreenCompletions: true)
        defer { fixture.close() }
        try fixture.owner.showCalendar()
        let panel = try #require(fixture.panel)
        fixture.onSameScreen = false
        fixture.owner.statusItemClicked()
        #expect(!panel.isVisible)
        try fixture.owner.showCalendar()
        fixture.browseAway()
        let before = fixture.store.state
        let loads = fixture.preferenceLoads.value
        let shows = fixture.shows
        let hides = fixture.hides
        try fixture.completeCrossScreenShow()
        #expect(panel.isVisible)
        #expect(fixture.panel === panel)
        #expect(fixture.allocations == 1)
        #expect(fixture.store.state == before)
        #expect(fixture.preferenceLoads.value == loads)
        #expect(fixture.shows == shows)
        #expect(fixture.hides == hides)
    }

    @Test
    func supersededCrossScreenShowCannotOverrideNewerHide() throws {
        let fixture = ShowFixture(capturesCrossScreenCompletions: true)
        defer { fixture.close() }
        try fixture.owner.showCalendar()
        let panel = try #require(fixture.panel)
        fixture.onSameScreen = false
        fixture.owner.statusItemClicked()
        #expect(!panel.isVisible)
        try fixture.owner.showCalendar()
        fixture.browseAway()
        fixture.onSameScreen = true
        fixture.owner.statusItemClicked()
        #expect(!panel.isVisible)
        let before = fixture.store.state
        let loads = fixture.preferenceLoads.value
        let shows = fixture.shows
        let hides = fixture.hides
        try fixture.completeCrossScreenShow()
        #expect(!panel.isVisible)
        #expect(fixture.panel === panel)
        #expect(fixture.allocations == 1)
        #expect(fixture.store.state == before)
        #expect(fixture.preferenceLoads.value == loads)
        #expect(fixture.shows == shows)
        #expect(fixture.hides == hides)
    }

    @Test
    func existingToggleKeepsHideOpenPinAndCrossScreenBehavior() async throws {
        let fixture = ShowFixture()
        defer { fixture.close() }
        fixture.owner.statusItemClicked()
        let panel = try #require(fixture.panel)
        #expect(panel.isVisible)
        fixture.owner.statusItemClicked()
        #expect(!panel.isVisible)
        #expect(fixture.hides > 0)
        fixture.owner.statusItemClicked()
        #expect(panel.isVisible)
        panel.isPinned = true
        fixture.browseAway()
        fixture.owner.statusItemClicked()
        #expect(panel.isVisible)
        #expect(fixture.store.showingPreferences)
        let beforeCrossScreenHides = fixture.hides
        fixture.onSameScreen = false
        fixture.owner.statusItemClicked()
        #expect(!panel.isVisible)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !panel.isVisible && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(panel.isVisible)
        #expect(panel.isPinned)
        #expect(!fixture.store.showingPreferences)
        #expect(fixture.shows == 3)
        #expect(fixture.hides == beforeCrossScreenHides + 1)
        #expect(fixture.allocations == 1)
    }
}

@MainActor
private final class ShowFixture {
    static let today = Date(timeIntervalSince1970: 1_800_000_000)
    static let selected = Date(timeIntervalSince1970: 1_700_000_000)
    static let statusFrame = NSRect(x: -5000, y: -4000, width: 100, height: 24)
    static let visibleFrame = NSRect(x: -6000, y: -5000, width: 1440, height: 1000)

    let store: StoreOf<CalendarFeature>
    let preferenceLoads = LockIsolated(0)
    var anchor: CalendarStatusItem.PanelAnchor? = .init(
        statusItemFrame: statusFrame, visibleFrame: visibleFrame
    )
    var panel: CalendarPanel?
    var allocations = 0
    var shows = 0
    var hides = 0
    var onSameScreen = true
    private let capturesCrossScreenCompletions: Bool
    private var crossScreenCompletions: [@MainActor () -> Void] = []
    private var observers: [Any] = []

    lazy var owner = CalendarStatusItem(
        anchorProvider: { [unowned self] in anchor },
        panelFactory: { [unowned self] frame, caret in makePanel(frame: frame, caret: caret) },
        toggleVisibility: { $0.isVisible },
        sameScreen: { [unowned self] _ in onSameScreen },
        crossScreenScheduler: controlledCrossScreenScheduler
    )

    private var controlledCrossScreenScheduler: (@MainActor (@escaping @MainActor () -> Void) -> Void)? {
        guard capturesCrossScreenCompletions else { return nil }
        return { [unowned self] completion in
            crossScreenCompletions.append(completion)
        }
    }

    init(capturesCrossScreenCompletions: Bool = false) {
        self.capturesCrossScreenCompletions = capturesCrossScreenCompletions
        let loads = preferenceLoads
        store = Store(initialState: CalendarFeature.State(displayedMonth: Self.selected)) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(Self.today)
            $0.calendarClient = CalendarClient(
                calendarDays: { _, _ in [] },
                gridInfo: { _ in GridInfo(startCol: 0, endCol: 6, endRow: 5) },
                menuBarDateString: { _, _ in
                    Issue.record("Owned Show fixture must not render a production status item")
                    return ""
                }
            )
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { loads.withValue { $0 += 1 }; return 1 }
            $0.preferencesClient.loadWorkdays = {
                loads.withValue { $0 += 1 }; return [2, 3, 4, 5, 6]
            }
            $0.preferencesClient.loadShowAISearch = { loads.withValue { $0 += 1 }; return true }
            $0.eventKitClient = EventKitClient(
                requestAccess: {
                    Issue.record("Owned Show must not request calendar access")
                    return false
                },
                fetchEvents: { _ in
                    Issue.record("Unauthorized Show fixture must not fetch calendar events")
                    return []
                },
                authorizationStatus: { .notDetermined }
            )
        }
    }

    func browseAway() {
        store.send(.aiDateResult(Self.selected))
        store.send(.togglePreferences)
        #expect(store.displayedMonth == Self.selected)
        #expect(store.selectedDate == Self.selected)
        #expect(store.showingPreferences)
    }

    func completeCrossScreenShow() throws {
        #expect(crossScreenCompletions.count == 1)
        let completion = try #require(crossScreenCompletions.first)
        crossScreenCompletions.removeAll()
        completion()
    }

    private func makePanel(frame: NSRect, caret: CGFloat) -> CalendarPanel {
        allocations += 1
        let created = CalendarPanel(
            contentRect: frame, caretOffset: caret, calendarStore: store
        ) { _ in AnyView(Color.clear.frame(width: 316, height: 200)) }
        created.isReleasedWhenClosed = false
        panel = created
        observers.append(NotificationCenter.default.addObserver(
            forName: .calendarPanelDidShow, object: created, queue: nil
        ) { [weak self] _ in MainActor.assumeIsolated { self?.shows += 1 } })
        observers.append(NotificationCenter.default.addObserver(
            forName: .calendarPanelWillHide, object: created, queue: nil
        ) { [weak self] _ in MainActor.assumeIsolated { self?.hides += 1 } })
        return created
    }

    func close() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panel?.orderOut(nil)
        panel?.close()
    }
}
