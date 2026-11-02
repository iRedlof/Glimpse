import AppKit
import ApplicationServices
import ComposableArchitecture
import GlimpseCore
import SwiftUI
import Testing

@testable import Glimpse

/// Owned key panels are opt-in so ordinary concurrent AX hosts cannot steal keys.
@Suite(.serialized, .enabled(if:
    ProcessInfo.processInfo.environment["GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE"] == "1"
))
@MainActor
struct CalendarKeyboardOwnershipTests {
    @Test
    func normalOpenRetainsBrowseMonthYearAndToday() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        fixture.trace("normal-open")
        try fixture.send(.right)
        #expect(fixture.monthNumber == 12)
        try fixture.send(.up)
        #expect(fixture.yearNumber == 2029)
        try fixture.send(.returnKey)
        #expect(fixture.monthNumber == 11)
        #expect(fixture.yearNumber == 2030)
        #expect(fixture.store.selectedDate == fixture.today)
        #expect(fixture.actions.value == ["nextMonth", "previousYear", "today"])
        #expect(fixture.actionCurrentEvents.value.allSatisfy { $0 })
    }

    @Test
    func queuedTabAndImmediateArrowSpaceActivateNewLogicalDate() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        fixture.trace("after-four-tabs-no-settle")
        let beforeMovement = fixture.callbackRows.count
        try fixture.send(.right)
        fixture.expectInvocation(after: beforeMovement, owner: .grid, key: .right, route: "move(1)")
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.store.selectedDate == fixture.today)
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(.space)
        fixture.expectInvocation(after: beforeActivation, owner: .grid, key: .space, route: "activate")
        fixture.trace("immediate-arrow-space")
        #expect(fixture.store.selectedDate == fixture.date(day: 16))
        #expect(fixture.monthNumber == 11)
        #expect(fixture.actions.value == ["date:16"])
        #expect(fixture.actionCurrentEvents.value == [true])
    }

    @Test
    func firstHeaderReturnUsesFocusedActionRatherThanToday() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        try fixture.send(.tab)
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeActivation, owner: .previousMonth, key: .returnKey, route: "activate")
        #expect(fixture.monthNumber == 10)
        #expect(fixture.actions.value == ["previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
    }

    @Test
    func heldHeaderSpaceActivatesOnceAndConsumesRepeat() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        try fixture.send(.tab)
        let beforeReturn = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeReturn, owner: .previousMonth, key: .returnKey, route: "activate")
        #expect(fixture.monthNumber == 10)
        #expect(fixture.actions.value == ["previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
        let beforeSpace = fixture.callbackRows.count
        try fixture.send(.space) // Complete down/up pair: exactly one local action.
        fixture.expectInvocation(after: beforeSpace, owner: .previousMonth, key: .space, route: "activate")
        #expect(fixture.monthNumber == 9)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        await fixture.settleRendering()
        #expect(fixture.monthNumber == 9)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        let beforeRepeat = fixture.callbackRows.count
        try fixture.send(.space, repeatPress: true)
        fixture.expectInvocation(after: beforeRepeat, owner: .previousMonth, key: .space,
                                 route: "consume", phase: "repeatPress")
        #expect(fixture.monthNumber == 9)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        await fixture.settleRendering()
        #expect(fixture.monthNumber == 9)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        let beforeFinalReturn = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeFinalReturn, owner: .previousMonth, key: .returnKey, route: "activate")
        #expect(fixture.monthNumber == 8)
        #expect(fixture.actions.value == ["previousMonth", "previousMonth", "previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true, true, true])
        fixture.trace("held-header-local-space-once-repeat-completed")
    }

    @Test
    func todayBecomingDisabledHasNoExtraTodayAction() async throws {
        // Production disabled state uses public live today; other fixtures retain2030.
        let fixture = try CalendarKeyboardRootFixture(initialToday: Date())
        defer { fixture.close() }
        try await fixture.open()
        try fixture.send(.tab)
        try fixture.send(.returnKey) // Move away so Today is enabled.
        await fixture.settleRendering()
        try fixture.send(.tab)
        let beforeToday = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeToday, owner: .today, key: .returnKey, route: "activate")
        #expect(fixture.actions.value == ["previousMonth", "today"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        await fixture.settleRendering()
        #expect(fixture.store.isShowingCurrentMonth)
        #expect(fixture.store.selectedDate.map { Calendar.current.isDateInToday($0) } == true)
        for repeatPress in [false, true] {
            let before = fixture.callbackRows.count
            let disabledBeforeEvent = fixture.store.isShowingCurrentMonth
                && fixture.store.selectedDate.map { Calendar.current.isDateInToday($0) } == true
            try fixture.send(.space, repeatPress: repeatPress)
            let rows = Array(fixture.callbackRows.dropFirst(before))
            let todayRows = rows.filter { $0["owner"] as? String == CalendarKeyboardOwner.today.rawValue }
            if disabledBeforeEvent {
                #expect(todayRows.allSatisfy { $0["route"] as? String == "consume" })
            }
            #expect(rows.allSatisfy {
                $0["eventWindowOwned"] as? Bool == true && $0["currentEventMatchesExpected"] as? Bool == true
            })
            #expect(fixture.actions.value.filter { $0 == "today" }.count == 1)
            // Withdrawal is valid; no absent callback is relabeled disabled-handler proof.
            print("GLIMPSE_KEYBOARD_DISABLED_TODAY_OBSERVATION repeat=\(repeatPress) disabledBeforeEvent=\(disabledBeforeEvent) localCallbacks=\(rows.count) todayOwnerCallbacks=\(todayRows.count) disabledOwnerHandlerExercised=\(disabledBeforeEvent && !todayRows.isEmpty) owners=\(rows.compactMap { $0["owner"] as? String })")
            fixture.trace("today-disabled-after-space-\(repeatPress)")
        }
    }

    @Test
    func reverseTabReturnsToHeaderWithoutCustomTraversal() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        try fixture.send(.backTab)
        fixture.trace("immediate-reverse-tab")
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeActivation, owner: .nextMonth, key: .returnKey, route: "activate")
        #expect(fixture.actions.value == ["nextMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
    }

    @Test
    func gridExitAndReopenWithdrawOwnerBeforeBrowse() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        let beforeMovement = fixture.callbackRows.count
        try fixture.send(.right)
        fixture.expectInvocation(after: beforeMovement, owner: .grid, key: .right, route: "move(1)")
        #expect(fixture.actions.value.isEmpty)
        try fixture.send(.tab)
        let beforeExitActivation = fixture.callbackRows.count
        try fixture.send(.returnKey)
        fixture.expectInvocation(after: beforeExitActivation, owner: .previousMonth, key: .returnKey, route: "activate")
        #expect(fixture.actions.value == ["previousMonth"])
        fixture.panel.orderOut(nil)
        try await fixture.open()
        fixture.trace("reopen-before-browse")
        #expect(fixture.lastPublishedOwner == nil)
        // Keep the exact identity condition while avoiding a private proxy dump.
        let responderIsWindow = fixture.panel.firstResponder === fixture.panel
        #expect(responderIsWindow)
        try fixture.send(.right)
        #expect(fixture.actions.value == ["nextMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
        #expect(fixture.monthNumber == 12)
        try fixture.send(.returnKey)
        #expect(fixture.actions.value == ["nextMonth", "today"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        #expect(fixture.monthNumber == 11)
        #expect(fixture.store.selectedDate == fixture.today)
        #expect(fixture.callbackRows.isEmpty)
    }

    @Test
    func settledTraversalCharacterizesGridBeforeImmediateArrowSpace() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 {
            try fixture.send(.tab)
            // Characterization only: separate from immediate Tab freshness.
            await fixture.opportunityForFocusRendering()
        }
        fixture.trace("settled-four-tabs")
        #expect(fixture.lastPublishedOwner == .grid)
        try fixture.send(.right)
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.store.selectedDate == fixture.today)
        // No Tab, yield or rendering opportunity between movement and activation.
        try fixture.send(.space)
        #expect(fixture.actions.value == ["date:16"])
        #expect(fixture.store.selectedDate == fixture.date(day: 16))
        #expect(fixture.actionCurrentEvents.value == [true])
        #expect(fixture.callbackRows.contains {
            $0["owner"] as? String == "grid" && $0["route"] as? String == "move(1)"
                && $0["currentEventMatchesExpected"] as? Bool == true
        })
    }

    @Test(arguments: [CalendarOwnedKey.returnKey, .keypadEnter])
    func gridReturnKeypadRepeatAndModifierOwnership(key: CalendarOwnedKey) async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        try fixture.send(.right)
        let beforeRepeat = fixture.callbackRows.count
        try fixture.send(key, repeatPress: true)
        fixture.expectInvocation(after: beforeRepeat, owner: .grid, key: key.routerKey,
                                 route: "consume", phase: "repeatPress")
        try fixture.send(key, modifiers: .command)
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.store.selectedDate == fixture.today)
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(key)
        fixture.expectInvocation(after: beforeActivation, owner: .grid, key: key.routerKey, route: "activate")
        #expect(fixture.actions.value == ["date:16"])
        #expect(fixture.store.selectedDate == fixture.date(day: 16))
        try fixture.send(key, repeatPress: true)
        #expect(fixture.actions.value == ["date:16"])
        try fixture.send(.right, modifiers: .command)
        try fixture.send(.space)
        #expect(fixture.store.selectedDate == nil) // Selecting the same16 again deselects.
        #expect(fixture.actions.value == ["date:16", "date:16"])
        #expect(fixture.actionCurrentEvents.value == [true, true])
        fixture.trace("grid-return-repeat-modifier-\(key.rawValue)")
    }

    @Test
    func recorderPreferencesAndOwnedPeerKeepCalendarKeys() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close(); fixture.setRecording(false) }
        try await fixture.open()
        for _ in 0..<4 { try fixture.send(.tab) }
        fixture.setRecording(true)
        try fixture.send(.right)
        try fixture.send(.space)
        try fixture.send(.returnKey)
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.store.selectedDate == fixture.today)
        fixture.setRecording(false)
        try fixture.send(.space)
        #expect(fixture.actions.value == ["date:15"])
        #expect(fixture.store.selectedDate == nil) // Same-day activation retains existing deselection.

        fixture.clearActionReceipts()
        fixture.store.send(.togglePreferences)
        await fixture.settleRendering()
        #expect(fixture.store.showingPreferences)
        try fixture.send(.right)
        try fixture.send(.returnKey)
        #expect(fixture.actions.value.isEmpty)
        fixture.store.send(.togglePreferences)
        await fixture.settleRendering()

        let peer = CalendarKeyboardOwnedPeer()
        defer { peer.close() }
        try peer.makeKey()
        let calendarIsNonkey = !fixture.panel.isKeyWindow && NSApp.keyWindow !== fixture.panel
        #expect(calendarIsNonkey)
        fixture.clearActionReceipts()
        try fixture.send(.right, to: peer)
        #expect(peer.receivedKeys == 1)
        #expect(peer.currentEventMatched)
        #expect(fixture.actions.value.isEmpty)
        #expect(fixture.callbackRows.isEmpty)
        fixture.trace("guard-owned-peer-dispatched")
    }

    @Test
    func repeatedVisibleShowRetainsGridFocusAndAnchor() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        try await fixture.openThroughShowOwner()
        for _ in 0..<4 { try fixture.send(.tab) }
        try fixture.send(.right)
        let before = fixture.store.state
        let responder = fixture.panel.firstResponder
        let shows = fixture.completions
        for _ in 0..<2 { try fixture.showOwner.showCalendar() }
        let responderRetained = fixture.panel.firstResponder === responder
        #expect(responderRetained)
        #expect(fixture.store.state == before)
        #expect(fixture.panel.contentView === fixture.hosting)
        #expect(fixture.completions == shows)
        let beforeActivation = fixture.callbackRows.count
        try fixture.send(.space)
        fixture.expectInvocation(after: beforeActivation, owner: .grid, key: .space, route: "activate")
        #expect(fixture.actions.value == ["date:16"])
        #expect(fixture.store.selectedDate == fixture.date(day: 16))
        #expect(fixture.actionCurrentEvents.value == [true])
    }

    @Test
    func nativeEditorSubmitEscapeAndHiddenReopen() async throws {
        try await withAIDateKeyboardRootFixture { fixture in
            try await fixture.openThroughShowOwner()
            for _ in 0..<4 { try fixture.send(.tab) }
            // The focused prompt locally handles Space; no AX action or panel-wide activation.
            try fixture.send(.space)
            fixture.trace("native-search-prompt-space")
            await fixture.settleRendering()
            try fixture.loadOwnedAccessibilityTree()
            let field = try fixture.nativeEditorField()
            let editor = try #require(field.currentEditor() as? NSTextView)
            let editorIsResponder = fixture.panel.firstResponder === editor
            #expect(editorIsResponder)
            // Public mutation sets up only this synthetic draft; native Return is queued.
            editor.insertText("synthetic next Friday", replacementRange: NSRange(location: NSNotFound, length: 0))
            await fixture.settleRendering()
            editor.setSelectedRange(NSRange(location: 3, length: 5))
            let responder = fixture.panel.firstResponder
            for _ in 0..<2 { try fixture.showOwner.showCalendar() }
            let responderRetained = fixture.panel.firstResponder === responder
            #expect(responderRetained)
            #expect(editor.string == "synthetic next Friday")
            #expect(editor.selectedRange() == NSRange(location: 3, length: 5))
            try fixture.send(.left)
            #expect(fixture.actions.value.isEmpty)
            #expect(editor.selectedRange() != NSRange(location: 3, length: 5))
            try fixture.send(.returnKey)
            #expect(fixture.submissions == ["synthetic next Friday"])
            #expect(fixture.submissionCurrentEvents == [true])
            #expect(fixture.actions.value.isEmpty)
            try await fixture.awaitAcceptedSubmissions()
            try fixture.send(.escape)
            await fixture.settleRendering()
            #expect(fixture.panel.isVisible)
            #expect(fixture.nativeEditorFields.isEmpty)
            #expect(fixture.submissions.count == 1)
            try fixture.send(.searchShortcut)
            await fixture.settleRendering()
            #expect(fixture.nativeEditorFields.count == 1)
            fixture.panel.orderOut(nil)
            try await fixture.openThroughShowOwner()
            #expect(fixture.nativeEditorFields.isEmpty)
            let responderIsWindow = fixture.panel.firstResponder === fixture.panel
            #expect(responderIsWindow)
            #expect(fixture.lastPublishedOwner == nil)
            try fixture.send(.right)
            try fixture.send(.returnKey)
            #expect(fixture.actions.value == ["nextMonth", "today"])
            #expect(fixture.submissions.count == 1)
            #expect(fixture.actionCurrentEvents.value == [true, true])
        }
    }

    @Test(arguments: [CGFloat(312), 812])
    func focusedLogicalDateStaysVisibleInCappedViewport(maximumHeight: CGFloat) async throws {
        let fixture = try CalendarKeyboardRootFixture(maximumHeight: maximumHeight)
        defer { fixture.close() }
        try await fixture.openThroughShowOwner()
        try fixture.loadOwnedAccessibilityTree()
        let scroll = try #require(accessibilityScrollView(in: fixture.hosting))
        let document = try #require(scroll.documentView)
        for _ in 0..<4 { try fixture.send(.tab) }
        for _ in 0..<4 { try fixture.send(.down) }
        await fixture.settleRendering()
        fixture.trace("viewport-anchor-settled-\(Int(maximumHeight))")
        let nodes = fixture.accessibilityNodes()
        let dates = nodes.filter { $0.role == .button && $0.label?.contains("2030") == true }
        let expectedLastDate = try #require(fixture.store.days.last?.date)
        let expectedLabel = expectedLastDate.formatted(
            Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year()
        )
        let expectedGridLabel = "Calendar grid for \(fixture.store.monthYearString), focused date: \(expectedLabel)"
        let gridMatches = nodes.filter { $0.label?.hasPrefix("Calendar grid for \(fixture.store.monthYearString)") == true }
        let expectedDate = dates.first { $0.label?.hasPrefix(expectedLabel) == true }
        let expectedDateFrame = expectedDate?.frame
        let clip = fixture.panel.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
        try fixture.saveFocusedDateBitmap(clip, name: "viewport-\(Int(maximumHeight))-before-assertions")
        if let expectedDateFrame {
            try fixture.saveFocusedDateBitmap(
                expectedDateFrame, name: "expected-anchor-\(Int(maximumHeight))-before-assertions"
            )
        }
        let gridRenderingFocused = fixture.gridRenderingFocused
        #expect(gridRenderingFocused)
        #expect(fixture.lastPublishedOwner == .grid)
        #expect(dates.count == 42)
        let grid = try #require(nodes.first { $0.label?.hasPrefix("Calendar grid for ") == true })
        let exactlyOneGridLabel = gridMatches.count == 1
        #expect(exactlyOneGridLabel)
        let actualLabelMatchesExpected = grid.label == expectedGridLabel
        #expect(actualLabelMatchesExpected)
        try fixture.expectOwnedPublicAXGridLabel(expectedGridLabel)
        let focusedDate = try #require(dates.first { $0.label?.hasPrefix(expectedLabel) == true })
        #expect(clip.contains(focusedDate.frame))
        #expect(fixture.store.selectedDate == fixture.today)
        #expect(fixture.actions.value.isEmpty)
        #expect(accessibilityScrollView(in: fixture.hosting) === scroll)
        #expect(scroll.documentView === document)
        let focusedDateFrame = focusedDate.frame
        try fixture.saveFocusedDateBitmap(focusedDateFrame, name: "viewport-\(Int(maximumHeight))")
        // Header's native reverse/Return changes month; forward Tab returns to grid.
        try fixture.send(.backTab)
        try fixture.send(.returnKey)
        try fixture.send(.tab)
        await fixture.settleRendering()
        #expect(fixture.monthNumber == 12)
        let finalGridRenderingFocused = fixture.gridRenderingFocused
        #expect(finalGridRenderingFocused)
        #expect(accessibilityScrollView(in: fixture.hosting) === scroll)
        #expect(scroll.documentView === document)
    }

    @Test
    func completionGuardsDoNotResetUnpreparedHiddenOrNonkeyPanels() async throws {
        let fixture = try CalendarKeyboardRootFixture()
        defer { fixture.close() }
        #expect(!fixture.panel.completeReopenPresentation())
        #expect(fixture.completions == 0)
        fixture.panel.prepareForReopen()
        #expect(!fixture.panel.completeReopenPresentation())
        #expect(fixture.completions == 0)
        fixture.panel.makeKeyAndOrderFront(nil)
        let peer = CalendarKeyboardOwnedPeer()
        defer { peer.close() }
        try peer.makeKey()
        #expect(!fixture.panel.completeReopenPresentation())
        #expect(fixture.completions == 0)
        fixture.panel.makeKeyAndOrderFront(nil)
        #expect(fixture.panel.completeReopenPresentation())
        #expect(fixture.completions == 1)
        await fixture.settleRendering()
        try fixture.send(.tab)
        let responder = fixture.panel.firstResponder
        #expect(!fixture.panel.completeReopenPresentation())
        let responderRetained = fixture.panel.firstResponder === responder
        #expect(responderRetained)
        #expect(fixture.completions == 1)
        try fixture.send(.returnKey)
        #expect(fixture.actions.value == ["previousMonth"])
        #expect(fixture.actionCurrentEvents.value == [true])
    }
}

@MainActor
final class CalendarKeyboardRootFixture {
    let today: Date
    let store: StoreOf<CalendarFeature>
    let panel: CalendarPanel
    let hosting: NSHostingView<AnyView>
    let preferences: StoreOf<PreferencesFeature>
    let aiModel: AIDateQueryModel
    let aiSettings: LockIsolated<AIDateIntegrationSettings>
    private let aiTaskReceipts: AIDateIntegrationTaskReceipts
    var aiTasks: [AIDateIntegrationTrackedTask] { aiTaskReceipts.tasks }
    let aiSettingSaves = LockIsolated<[AIDateIntegrationSettings]>([])
    let actions = LockIsolated<[String]>([])
    let actionCurrentEvents = LockIsolated<[Bool]>([])
    private let dispatch = CalendarKeyboardDispatchReceipt()
    private let focus = CalendarKeyboardFocusReceipt()
    private let callbacks = CalendarKeyboardCallbackReceipt()
    private let effects = CalendarKeyboardEffectReceipt()
    private let hotkeyFixture = HotkeyFixture()
    private let lifecycle = CalendarKeyboardLifecycleReceipt()
    private var completionObserver: NSObjectProtocol?
    private let maximumHeight: CGFloat
    private var sequence = 0
    var lastPublishedOwner: CalendarKeyboardOwner? { focus.owner }
    var callbackRows: [[String: Any]] { callbacks.rows }
    var submissions: [String] { effects.submissions }
    var submissionCurrentEvents: [Bool] { effects.currentEvents }
    var editorPresentationRequests: Int { effects.presentationRequests }
    var completions: Int { lifecycle.completions }
    var gridRenderingFocused: Bool { focus.gridRenderingFocused }
    var matchesCurrentDispatchedEvent: Bool {
        dispatch.expected != nil && NSApp.currentEvent === dispatch.expected
    }

    lazy var showOwner: CalendarStatusItem = {
        let origin = panel.frame.origin
        let anchor = CalendarStatusItem.PanelAnchor(
            statusItemFrame: NSRect(x: origin.x + 138, y: origin.y + maximumHeight + 16, width: 40, height: 24),
            visibleFrame: NSRect(x: origin.x - 100, y: origin.y, width: 1000, height: maximumHeight + 64)
        )
        let panel = panel
        return CalendarStatusItem(anchorProvider: { anchor }, panelFactory: { _, _ in panel })
    }()

    var monthNumber: Int { store.calendar.component(.month, from: store.displayedMonth) }
    var yearNumber: Int { store.calendar.component(.year, from: store.displayedMonth) }

    init(
        showAI: Bool = false, maximumHeight: CGFloat = 550, initialToday: Date? = nil,
        aiClient: AIDateQueryClient = AIDateIntegrationClient.immediateNoDate,
        allowAISettings: Bool = false
    ) throws {
        self.maximumHeight = maximumHeight
        if let initialToday {
            today = initialToday
        } else {
            today = try #require(Calendar.current.date(from: DateComponents(
                year: 2030, month: 11, day: 15, hour: 12
            )))
        }
        aiSettings = LockIsolated(AIDateIntegrationSettings(enabled: showAI, preference: .auto))
        let aiSettings = aiSettings
        let aiSettingSaves = aiSettingSaves
        let fixedToday = today
        let actions = actions
        let events = actionCurrentEvents
        let dispatch = dispatch
        store = Store(initialState: CalendarFeature.State(displayedMonth: today)) {
            Reduce<CalendarFeature.State, CalendarFeature.Action> { state, action in
                let name: String?
                switch action {
                case .goToPreviousMonth: name = "previousMonth"
                case .goToNextMonth: name = "nextMonth"
                case .goToPreviousYear: name = "previousYear"
                case .goToNextYear: name = "nextYear"
                case .goToToday: name = "today"
                case .aiDateResult(.some(_)): name = "aiDate"
                case let .dateTapped(date):
                    name = "date:\(state.calendar.component(.day, from: date))"
                default: name = nil
                }
                if let name {
                    actions.withValue { $0.append(name) }
                    MainActor.assumeIsolated {
                        let matches = NSApp.currentEvent === dispatch.expected
                        events.withValue { $0.append(matches) }
                    }
                }
                return .none
            }
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(fixedToday)
            $0.calendarClient = .liveValue
            $0.calendarClient.menuBarDateString = { _, _ in
                Issue.record("Keyboard fixture must not use a status item")
                return ""
            }
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { aiSettings.value.enabled }
            $0.eventKitClient = EventKitClient(
                requestAccess: {
                    Issue.record("Keyboard fixture must not request calendar access")
                    return false
                },
                fetchEvents: { _ in
                    Issue.record("Keyboard fixture must not read calendars")
                    return []
                },
                authorizationStatus: { .notDetermined }
            )
        }
        preferences = Store(initialState: PreferencesFeature.State()) {
            Reduce<PreferencesFeature.State, PreferencesFeature.Action> { _, action in
                switch action {
                case .onAppear, .refreshLaunchAtLogin:
                    break // Existing view lifecycle reads only injected clients.
                case .setShowAISearch, .setAIProvider, .delegate(.preferencesChanged):
                    if !allowAISettings { Issue.record("Keyboard fixture must not change AI preferences") }
                default:
                    Issue.record("Keyboard fixture must not change preferences")
                }
                return .none
            }
            PreferencesFeature()
        } withDependencies: {
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadDisplayOptions = { .default }
            $0.preferencesClient.loadShowAISearch = { aiSettings.value.enabled }
            $0.preferencesClient.loadAIProvider = { aiSettings.value.preference }
            $0.preferencesClient.saveShowAISearch = { enabled in
                aiSettings.withValue { $0.enabled = enabled }
                aiSettingSaves.withValue { $0.append(aiSettings.value) }
            }
            $0.preferencesClient.saveAIProvider = { preference in
                aiSettings.withValue { $0.preference = preference }
                aiSettingSaves.withValue { $0.append(aiSettings.value) }
            }
            $0.launchAtLoginClient = .testValue
            $0.launchAtLoginClient.status = { .notRegistered }
        }
        let store = store
        aiModel = AIDateQueryModel(
            client: aiClient, enabled: showAI, preference: .auto,
            onDate: { store.send(.aiDateResult($0)) }
        )
        panel = CalendarPanel(
            contentRect: NSRect(x: -1000, y: -1000, width: 316, height: maximumHeight),
            caretOffset: 150, calendarStore: store, content: { _ in AnyView(EmptyView()) }
        )
        panel.isReleasedWhenClosed = false
        let callbacks = callbacks
        let panel = panel
        let focus = focus
        let rendering = focus.gridRenderingSnapshot
        let effects = effects
        let hotkeyModel = HotkeyPreferencesModel(
            hotkey: hotkeyFixture.hotkey, defaults: hotkeyFixture.defaults
        ) { Issue.record("Keyboard fixture must not operate a global hotkey") }
        // Replace only fixture presentation to inject the existing root preferences seam.
        // This keyboard test does not accept the private KVO resize path.
        let aiModel = aiModel
        let taskReceipts = AIDateIntegrationTaskReceipts()
        aiTaskReceipts = taskReceipts
        hosting = NSHostingView(rootView: AnyView(
            CalendarPopoverView(
                store: store, panel: panel, layout: panel.layoutState,
                preferencesStore: preferences, keyboardObservation: { invocation in
                    let row: [String: Any] = [
                        "owner": invocation.owner.rawValue,
                        "key": String(describing: invocation.key),
                        "phase": String(describing: invocation.phase),
                        "route": String(describing: invocation.route),
                        "contextAllowsRouting": invocation.context.allowsRouting,
                        "eventWindowOwned": NSApp.currentEvent?.window === panel,
                        "currentEventMatchesExpected": NSApp.currentEvent === dispatch.expected,
                        "firstResponderIsWindow": panel.firstResponder === panel,
                        "focusRenderingSnapshot": invocation.focusRenderingSnapshot.map { $0 ? "true" : "false" } ?? "not-used"
                    ]
                    callbacks.rows.append(row)
                    let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                    if let data { print("GLIMPSE_KEYBOARD_CALLBACK \(String(decoding: data, as: UTF8.self))") }
                },
                preferencesHotkeyModel: hotkeyModel,
                editorPresentation: { requestFocus in
                    effects.presentationRequests += 1
                    print("GLIMPSE_KEYBOARD_EDITOR_PRESENTATION count=\(effects.presentationRequests)")
                    requestFocus()
                },
                aiQueryModel: aiModel,
                loadAISettings: {
                    let settings = aiSettings.value
                    return (settings.enabled, settings.preference)
                },
                querySubmissionObservation: { query, task in
                    taskReceipts.tasks.append(AIDateIntegrationTrackedTask(task))
                    let matched = NSApp.currentEvent === dispatch.expected
                    effects.submissions.append(query)
                    effects.currentEvents.append(matched)
                    print("GLIMPSE_KEYBOARD_SUBMIT count=\(effects.submissions.count) currentEvent=\(matched) editor=\(panel.firstResponder is NSTextView)")
                }
            )
            .environment(\.accessibilityEnabled, true)
            .background(CalendarKeyboardTestOwnerObserver(receipt: focus))
            .onPreferenceChange(CalendarGridFocusPreference.self) {
                rendering.setValue($0)
            }
        ))
        panel.contentView = hosting
        let bounds = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        panel.setFrameOrigin(NSPoint(x: bounds.minX - 1000, y: bounds.minY - 1000))
        panel.isPinned = true
        panel.layoutState.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 150)
        let lifecycle = lifecycle
        completionObserver = NotificationCenter.default.addObserver(
            forName: .calendarPanelDidCompleteReopen, object: panel, queue: nil
        ) { _ in MainActor.assumeIsolated { lifecycle.completions += 1 } }
    }

    func awaitAcceptedSubmissions() async throws {
        let cleanup = Task { @MainActor in
            var failedReceipts: [Int] = []
            for (index, receipt) in self.aiTasks.enumerated() {
                do { try await receipt.finish() }
                catch { failedReceipts.append(index) }
            }
            // Every actual receipt is visited before reporting unresolved work.
            if !failedReceipts.isEmpty {
                throw AIDateIntegrationFixtureFailure.receiptFailures(failedReceipts)
            }
        }
        try await cleanup.value
    }

    func trackEligibilityProbe(_ task: Task<Void, Never>) {
        aiTaskReceipts.tasks.append(AIDateIntegrationTrackedTask(task))
    }

    func date(day: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: 2030, month: 11, day: day))
    }

    func open() async throws {
        panel.prepareForReopen()
        panel.makeKeyAndOrderFront(nil)
        let completed = panel.completeReopenPresentation()
        let responderIsWindow = panel.firstResponder === panel
        print("GLIMPSE_KEYBOARD_REOPEN \(completed) responderIsWindow=\(responderIsWindow)")
        #expect(completed)
        #expect(responderIsWindow)
        await settleRendering()
        try #require(panel.isVisible && panel.isKeyWindow && NSApp.keyWindow === panel)
        clearActionReceipts()
    }

    func openThroughShowOwner() async throws {
        let before = completions
        try showOwner.showCalendar()
        #expect(completions == before + 1)
        let responderIsWindow = panel.firstResponder === panel
        #expect(responderIsWindow)
        await settleRendering()
        try #require(panel.isVisible && panel.isKeyWindow && NSApp.keyWindow === panel)
        clearActionReceipts()
    }

    func clearActionReceipts() {
        actions.setValue([])
        actionCurrentEvents.setValue([])
        callbacks.rows = []
    }

    func expectInvocation(
        after count: Int, owner: CalendarKeyboardOwner, key: CalendarKeyboardKey,
        route: String, phase: String = "down"
    ) {
        let rows = Array(callbacks.rows.dropFirst(count))
        #expect(rows.count == 1)
        #expect(rows.allSatisfy {
            $0["owner"] as? String == owner.rawValue
                && $0["key"] as? String == String(describing: key)
                && $0["phase"] as? String == phase
                && $0["route"] as? String == route
                && $0["contextAllowsRouting"] as? Bool == true
                && $0["eventWindowOwned"] as? Bool == true
                && $0["currentEventMatchesExpected"] as? Bool == true
                && $0["firstResponderIsWindow"] as? Bool == false
        })
    }

    func opportunityForFocusRendering() async {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        pumpRunLoop()
        await Task.yield()
    }

    func settleRendering() async {
        for _ in 0..<8 { await opportunityForFocusRendering() }
    }

    func setRecording(_ active: Bool) {
        NotificationCenter.default.post(name: .hotkeyRecordingDidChange, object: active)
    }

    var nativeEditorFields: [NSTextField] {
        var queue = [hosting as NSView]
        var fields: [NSTextField] = []
        while let view = queue.popLast() {
            if let field = view as? NSTextField, field.isEditable { fields.append(field) }
            queue.append(contentsOf: view.subviews)
        }
        return fields
    }

    func nativeEditorField() throws -> NSTextField {
        #expect(nativeEditorFields.count == 1)
        return try #require(nativeEditorFields.first)
    }

    /// Read only the self-process window positively matched to this owned panel.
    /// No system-wide AX object, trust request, action, permission or fallback.
    func expectOwnedPublicAXGridLabel(_ expectedGridLabel: String) throws {
        let inTestHost = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        try #require(inTestHost)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        func attribute(_ element: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return (error, value)
        }
        func isOwnProcess(_ element: AXUIElement) -> Bool {
            var pid: pid_t = 0
            return AXUIElementGetPid(element, &pid) == .success && pid == ownPID
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        func frame(_ element: AXUIElement) -> CGRect? {
            let (positionError, positionValue) = attribute(element, kAXPositionAttribute)
            let (sizeError, sizeValue) = attribute(element, kAXSizeAttribute)
            guard positionError == .success, sizeError == .success,
                  let positionValue, let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(),
                  CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
            let positionAX = positionValue as! AXValue
            let sizeAX = sizeValue as! AXValue
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetType(positionAX) == .cgPoint,
                  AXValueGetType(sizeAX) == .cgSize,
                  AXValueGetValue(positionAX, .cgPoint, &position),
                  AXValueGetValue(sizeAX, .cgSize, &size),
                  position.x.isFinite, position.y.isFinite,
                  size.width.isFinite, size.height.isFinite else { return nil }
            return CGRect(origin: position, size: size)
        }
        let application = AXUIElementCreateApplication(ownPID)
        let appPIDMatches = isOwnProcess(application)
        try #require(appPIDMatches)
        let (windowsError, windowsValue) = attribute(application, kAXWindowsAttribute)
        let windowsQuerySucceeded = windowsError == .success
        try #require(windowsQuerySucceeded)
        let windows = windowsValue as? [AXUIElement]
        let windowListIsBounded = windows != nil && (windows?.count ?? 0) <= 16
        try #require(windowListIsBounded)
        let primaryScreen = NSScreen.screens.first
        let screenExists = primaryScreen != nil
        try #require(screenExists)
        // AX uses global top-left coordinates; AppKit's main screen has bottom-left origin.
        let expectedFrame = CGRect(
            x: panel.frame.minX, y: primaryScreen!.frame.maxY - panel.frame.maxY,
            width: panel.frame.width, height: panel.frame.height
        )
        let expectedFrameIsFinite = expectedFrame.origin.x.isFinite && expectedFrame.origin.y.isFinite &&
            expectedFrame.width.isFinite && expectedFrame.height.isFinite
        try #require(expectedFrameIsFinite)
        var matchingWindows: [AXUIElement] = []
        for window in windows! {
            let windowPIDMatches = isOwnProcess(window)
            try #require(windowPIDMatches)
            if frame(window) == expectedFrame { matchingWindows.append(window) }
        }
        let exactlyOneOwnedFrame = matchingWindows.count == 1
        try #require(exactlyOneOwnedFrame)
        let ownedWindow = matchingWindows[0]
        var queue = [ownedWindow]
        var index = 0
        var matches = 0
        while index < queue.count {
            let node = queue[index]
            index += 1
            let nodePIDMatches = isOwnProcess(node)
            try #require(nodePIDMatches)
            if !CFEqual(node, ownedWindow) {
                let window = element(attribute(node, kAXWindowAttribute).1)
                let nodeWindowMatches = window.map { CFEqual($0, ownedWindow) } ?? false
                try #require(nodeWindowMatches)
                let parent = element(attribute(node, kAXParentAttribute).1)
                let parentIsOwned = parent.map { parent in
                    guard isOwnProcess(parent) else { return false }
                    if CFEqual(parent, ownedWindow) { return true }
                    return element(attribute(parent, kAXWindowAttribute).1)
                        .map { CFEqual($0, ownedWindow) } ?? false
                } ?? false
                try #require(parentIsOwned)
            }
            let (descriptionError, descriptionValue) = attribute(node, kAXDescriptionAttribute)
            let (titleError, titleValue) = attribute(node, kAXTitleAttribute)
            let description = descriptionValue as? String
            let title = titleValue as? String
            if description == expectedGridLabel || title == expectedGridLabel {
                let role = attribute(node, kAXRoleAttribute).1 as? String
                let finiteFrame = frame(node) != nil
                let successfulLabelReadMatches =
                    (descriptionError == .success && description == expectedGridLabel) ||
                    (titleError == .success && title == expectedGridLabel)
                try #require(successfulLabelReadMatches)
                let roleIsGroup = role == kAXGroupRole
                try #require(roleIsGroup)
                try #require(finiteFrame)
                matches += 1
            }
            for name in [kAXChildrenAttribute, kAXContentsAttribute] {
                var count: CFIndex = 0
                let countError = AXUIElementGetAttributeValueCount(node, name as CFString, &count)
                if countError == .attributeUnsupported || countError == .noValue { continue }
                let childCountIsBounded = countError == .success && count >= 0 && count <= 256
                try #require(childCountIsBounded)
                if count == 0 { continue }
                var values: CFArray?
                let childrenError = AXUIElementCopyAttributeValues(node, name as CFString, 0, count, &values)
                let childrenQuerySucceeded = childrenError == .success
                try #require(childrenQuerySucceeded)
                let children = values as? [AXUIElement]
                let childrenAreElements = children != nil
                try #require(childrenAreElements)
                for child in children! where !queue.contains(where: { CFEqual($0, child) }) {
                    let queueRemainsBounded = queue.count < 256
                    try #require(queueRemainsBounded)
                    queue.append(child)
                }
            }
        }
        let exactlyOneExpectedLabel = matches == 1
        try #require(exactlyOneExpectedLabel)
    }

    func loadOwnedAccessibilityTree() throws {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
        try #require(result == .success)
    }

    func accessibilityNodes() -> [AccessibilityTestNode] {
        var queue: [Any] = [hosting]
        var visited: Set<ObjectIdentifier> = []
        var nodes: [AccessibilityTestNode] = []
        var index = 0
        while index < queue.count {
            let object = queue[index] as AnyObject
            index += 1
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true,
                  visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let node = AccessibilityTestNode(object: object)
            nodes.append(node)
            queue.append(contentsOf: node.children + node.contents + node.visibleChildren)
        }
        return nodes
    }

    func saveFocusedDateBitmap(_ screenRect: NSRect, name: String) throws {
        let rect = hosting.convert(panel.convertFromScreen(screenRect), from: nil)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: rect))
        hosting.cacheDisplay(in: rect, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let base = ProcessInfo.processInfo.environment["GLIMPSE_KEYBOARD_ARTIFACT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("keyboard-rendering", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let output = base.appendingPathComponent(name + ".png")
        try data.write(to: output)
        print("GLIMPSE_KEYBOARD_RENDERING bitmap=\(output.path) focused=\(gridRenderingFocused)")
    }

    /// Retrieve the exact owned event from this isolated test application's queue.
    /// No global CG event, direct NSWindow dispatch or unrelated-event inspection.
    func send(
        _ key: CalendarOwnedKey, repeatPress: Bool = false,
        modifiers: NSEvent.ModifierFlags? = nil, to ownedPeer: CalendarKeyboardOwnedPeer? = nil
    ) throws {
        let window = ownedPeer?.panel ?? panel
        try #require(ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil)
        try #require(window.isVisible && window.isKeyWindow && NSApp.keyWindow === window)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers ?? key.modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: key.characters, charactersIgnoringModifiers: key.ignoringModifiers,
                isARepeat: type == .keyDown && repeatPress, keyCode: key.code
            ))
            try #require(event.window === window)
            NSApp.postEvent(event, atStart: true)
            let mask: NSEvent.EventTypeMask = type == .keyDown ? .keyDown : .keyUp
            let retrieved = try #require(NSApp.nextEvent(
                matching: mask, until: Date(), inMode: .default, dequeue: true
            ))
            guard retrieved.window === window,
                  retrieved.type == event.type,
                  retrieved.windowNumber == event.windowNumber,
                  abs(retrieved.timestamp - event.timestamp) < 0.001,
                  retrieved.keyCode == event.keyCode,
                  retrieved.characters == event.characters,
                  retrieved.charactersIgnoringModifiers == event.charactersIgnoringModifiers,
                  retrieved.modifierFlags.intersection(Self.semanticModifiers) ==
                    event.modifierFlags.intersection(Self.semanticModifiers),
                  retrieved.isARepeat == event.isARepeat else {
                var guardEvidence: [String: Bool] = [
                    "objectIdentityMatches": retrieved === event,
                    "retrievedWindowOwned": retrieved.window === window,
                    "postedWindowOwned": event.window === window,
                    "retrievedTypeMatches": retrieved.type == type
                ]
                // Only inspect payload after positive owned-window/type identity.
                // Report equality booleans, never unrelated input or raw key data.
                if retrieved.window === window, retrieved.type == type {
                    guardEvidence["windowNumberMatches"] = retrieved.windowNumber == event.windowNumber
                    guardEvidence["timestampMatches"] = retrieved.timestamp == event.timestamp
                    guardEvidence["timestampWithinOneMillisecond"] = abs(retrieved.timestamp - event.timestamp) < 0.001
                    guardEvidence["keyCodeMatches"] = retrieved.keyCode == event.keyCode
                    guardEvidence["charactersMatch"] = retrieved.characters == event.characters
                    guardEvidence["ignoringModifiersMatch"] = retrieved.charactersIgnoringModifiers == event.charactersIgnoringModifiers
                    guardEvidence["modifierFlagsMatch"] = retrieved.modifierFlags == event.modifierFlags
                    guardEvidence["semanticModifierFlagsMatch"] =
                        retrieved.modifierFlags.intersection(Self.semanticModifiers) ==
                        event.modifierFlags.intersection(Self.semanticModifiers)
                    guardEvidence["repeatMatches"] = retrieved.isARepeat == event.isARepeat
                }
                let data = try JSONSerialization.data(withJSONObject: guardEvidence, options: [.sortedKeys])
                print("GLIMPSE_KEYBOARD_QUEUE_GUARD \(String(decoding: data, as: UTF8.self))")
                NSApp.postEvent(retrieved, atStart: true)
                Issue.record("Unexpected event requeued; no unrelated event dispatched or read")
                throw CalendarKeyboardFixtureError.unexpectedEvent
            }
            dispatch.expected = retrieved
            trace("queue-retrieved-\(key.rawValue)-\(type.rawValue)")
            NSApp.sendEvent(retrieved)
            trace("application-dispatched-\(key.rawValue)-\(type.rawValue)")
            dispatch.expected = nil
        }
    }

    func trace(_ stage: String) {
        sequence += 1
        let row: [String: Any] = [
            "sequence": sequence, "stage": stage,
            "windowVisible": panel.isVisible, "windowKey": panel.isKeyWindow,
            "firstResponderIsWindow": panel.firstResponder === panel,
            "firstResponderIsHosting": panel.firstResponder === hosting,
            "currentEventMatchesExpected": dispatch.expected != nil && NSApp.currentEvent === dispatch.expected,
            "lastPublishedOwner": focus.owner?.rawValue ?? "nil",
            "ownerObservations": focus.observations,
            "gridRenderingFocused": focus.gridRenderingFocused,
            "completionNotifications": lifecycle.completions,
            "editorPresentationRequests": effects.presentationRequests,
            "actions": actions.value
        ]
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print("GLIMPSE_KEYBOARD_ROOT \(text)")
        }
    }

    func close() {
        dispatch.expected = nil
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        completionObserver = nil
        panel.orderOut(nil)
        hosting.rootView = AnyView(EmptyView())
        panel.makeFirstResponder(nil)
        panel.initialFirstResponder = nil
        panel.contentView = nil
        panel.close()
        hotkeyFixture.cleanupDefaults()
        #expect(hotkeyFixture.backend.operations.isEmpty)
        #expect(!panel.isVisible && !panel.isKeyWindow)
        #expect(panel.firstResponder == nil || panel.firstResponder === panel)
        trace("closed")
    }

    private func pumpRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    // Arrow/numeric-pad/function/device flags describe key classification.
    // Preserve every modifier which can alter application routing or text case.
    private static let semanticModifiers: NSEvent.ModifierFlags = [
        .command, .control, .option, .shift, .capsLock
    ]
}

@MainActor
private final class CalendarKeyboardDispatchReceipt {
    var expected: NSEvent?
}

@MainActor
private final class CalendarKeyboardFocusReceipt {
    var owner: CalendarKeyboardOwner?
    var observations: [String] = []
    let gridRenderingSnapshot = LockIsolated(false)
    var gridRenderingFocused: Bool { gridRenderingSnapshot.value }
}

@MainActor
private final class CalendarKeyboardCallbackReceipt {
    var rows: [[String: Any]] = []
}

@MainActor
private final class CalendarKeyboardEffectReceipt {
    var presentationRequests = 0
    var submissions: [String] = []
    var currentEvents: [Bool] = []
}

@MainActor
private final class CalendarKeyboardLifecycleReceipt {
    var completions = 0
}

/// One owned native responder proves peer delivery while the calendar is nonkey.
/// It records only its own keyDown; it implements no traversal or production route.
@MainActor
private final class CalendarKeyboardPeerView: NSView {
    var receivedKeys = 0
    var currentEventMatched = false
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        receivedKeys += 1
        currentEventMatched = event.window === window && NSApp.currentEvent === event
    }
}

@MainActor
final class CalendarKeyboardOwnedPeer {
    let panel = NSPanel(
        contentRect: NSRect(x: -1800, y: -1800, width: 120, height: 80),
        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false
    )
    private let view = CalendarKeyboardPeerView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
    var receivedKeys: Int { view.receivedKeys }
    var currentEventMatched: Bool { view.currentEventMatched }

    init() {
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = view
        let screens = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        panel.setFrameOrigin(NSPoint(x: screens.minX - 1800, y: screens.minY - 1800))
    }

    func makeKey() throws {
        panel.makeKeyAndOrderFront(nil)
        try #require(panel.isKeyWindow && NSApp.keyWindow === panel)
        #expect(panel.makeFirstResponder(view))
        let responderOwned = panel.firstResponder === view
        #expect(responderOwned)
    }

    func close() {
        panel.orderOut(nil)
        panel.makeFirstResponder(nil)
        panel.initialFirstResponder = nil
        panel.contentView = nil
        panel.close()
        #expect(!panel.isVisible && !panel.isKeyWindow)
    }
}

@MainActor
private struct CalendarKeyboardTestOwnerObserver: View {
    @FocusedValue(\.calendarKeyboardOwner) private var owner
    let receipt: CalendarKeyboardFocusReceipt

    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .onChange(of: owner, initial: true) { _, owner in
                receipt.owner = owner
                receipt.observations.append(owner?.rawValue ?? "nil")
            }
    }
}

private enum CalendarKeyboardFixtureError: Error {
    case unexpectedEvent
}

enum CalendarOwnedKey: String, Sendable {
    case tab, backTab, left, right, up, down, returnKey, keypadEnter, space, searchShortcut, escape

    var code: UInt16 {
        switch self {
        case .tab, .backTab: 48
        case .left: 123
        case .right: 124
        case .up: 126
        case .down: 125
        case .returnKey: 36
        case .keypadEnter: 76
        case .space: 49
        case .searchShortcut: 5
        case .escape: 53
        }
    }
    var characters: String {
        switch self {
        case .tab: "\t"
        case .backTab: "\u{19}"
        case .left: "\u{F702}"
        case .right: "\u{F703}"
        case .up: "\u{F700}"
        case .down: "\u{F701}"
        case .returnKey: "\r"
        case .keypadEnter: "\u{3}"
        case .space: " "
        case .searchShortcut: "g"
        case .escape: "\u{1B}"
        }
    }
    // Apple's charactersIgnoringModifiers preserves Shift. Backtab therefore
    // retains U+0019 here rather than reverting to an unshifted Tab character.
    var ignoringModifiers: String { characters }
    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .backTab: .shift
        case .keypadEnter: .numericPad
        case .searchShortcut: .command
        default: []
        }
    }
    var routerKey: CalendarKeyboardKey { CalendarKeyboardKey(nativeCode: code) }
}
