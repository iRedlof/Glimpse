import GlimpseCore
import Combine
import EventKit
import SwiftUI

struct CalendarPresentationSnapshot: Equatable, Sendable {
    let keyboardSession: Int
    let editorFocused: Bool
}

struct CalendarPopoverView: View {
    @Bindable var store: StoreOf<CalendarFeature>
    @Environment(\.self) private var environment
    @Environment(\.inputModality) private var inputModality
    weak var panel: CalendarPanel?

    let layout: PanelLayoutState
    let keyboardObservation: ((CalendarKeyboardInvocation) -> Void)?
    let editorPresentation: ((@escaping @MainActor () -> Void) -> Void)?
    let querySubmissionObservation: (@MainActor (String, Task<Void, Never>) -> Void)?
    let loadAISettings: @MainActor () -> (enabled: Bool, preference: AIProvider)
    let presentationObservation: ((CalendarPresentationSnapshot) -> Void)?
    private let eventChangeNotificationCenter: NotificationCenter
    private let quitApplication: @MainActor () -> Void

    @State private var scrollRouter = CalendarScrollRouter()
    @State private var scrollMonitor: Any?
    @State private var isMouseOverCalendar = false
    /// Bumped when the pointer leaves the grid or the panel hides; day cells own hover.
    @State private var hoverResetToken = 0
    /// Per-day start/number/label, rebuilt only when the grid's days change.
    @State private var dayIndex = CalendarDayIndexCache()
    @State private var keyMonitor: Any?
    @State private var isRecordingHotkey = false
    @State private var aiQueryModel: AIDateQueryModel
    @FocusState private var aiFieldFocused: Bool
    @State private var editorFocusGeneration = 0
    @FocusState private var controlFocus: CalendarKeyboardOwner?
    @State private var logicalDate: Date?
    @State private var gridHasFocus = false
    @State private var keyboardSession = 0
    @State private var keyboardOwnerRelay = CalendarKeyboardOwnerRelay()
    @State private var showQuitConfirm: Bool = false
    @State private var pendingFooterFocus: CalendarKeyboardOwner?
    @State private var consumesQuitEscapeRepeats = false
    private let caretHeight = CalendarPanel.caretHeight

    init(store: StoreOf<CalendarFeature>, panel: CalendarPanel? = nil,
         layout: PanelLayoutState? = nil,
         keyboardObservation: ((CalendarKeyboardInvocation) -> Void)? = nil,
         editorPresentation: ((@escaping @MainActor () -> Void) -> Void)? = nil,
         aiQueryModel: AIDateQueryModel? = nil,
         loadAISettings: @escaping @MainActor () -> (enabled: Bool, preference: AIProvider) = {
             let preferences = PreferencesClient.liveValue
             return (preferences.loadShowAISearch(), preferences.loadAIProvider())
         },
         eventChangeNotificationCenter: NotificationCenter = .default,
         querySubmissionObservation: (@MainActor (String, Task<Void, Never>) -> Void)? = nil,
         presentationObservation: ((CalendarPresentationSnapshot) -> Void)? = nil,
         quitApplication: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }) {
        self.store = store
        self.panel = panel
        self.layout = layout ?? panel?.layoutState ?? PanelLayoutState()
        self.keyboardObservation = keyboardObservation
        self.editorPresentation = editorPresentation
        self.loadAISettings = loadAISettings
        self.eventChangeNotificationCenter = eventChangeNotificationCenter
        self.querySubmissionObservation = querySubmissionObservation
        self.presentationObservation = presentationObservation
        self.quitApplication = quitApplication
        let settings = loadAISettings()
        self._aiQueryModel = State(initialValue: aiQueryModel ?? AIDateQueryModel(
            client: .live, enabled: settings.enabled, preference: settings.preference,
            onIntent: { store.send(.aiIntent($0)) },
            onResultsInvalidated: { store.send(.aiResultsCleared) }
        ))
    }

    var body: some View {
        ScrollViewReader { reader in
            VStack(spacing: 0) {
                caretView.frame(height: caretHeight)
                PanelViewport(layout: layout) {
                    VStack(spacing: 0) {
                        VStack(spacing: 12) {
                            headerView.id("panel-header")
                            if store.showAISearch {
                                aiQueryField
                                    .id("panel-ai-input")
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                aiResults
                            }
                            CalendarGridKeyboardContent(
                                isEligible: store.days.count == 42,
                                focus: $controlFocus,
                                context: keyboardContext, move: moveLogicalDate,
                                activate: activateLogicalDate, observe: keyboardObservation
                            ) { focused in
                                calendarSection(keyboardFocused: focused)
                            }
                                .onPreferenceChange(CalendarGridFocusPreference.self) { gridHasFocus = $0 }
                                .onHover { hovering in
                                    isMouseOverCalendar = hovering
                                    if !hovering {
                                        hoverResetToken &+= 1
                                        scrollRouter.suspendNavigation()
                                    }
                                }
                            agendaDateContext
                            agendaContent
                        }
                        .padding()
                        footerView.id("panel-footer")
                    }
                    .id("panel-content-top")
                }
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg)
                        .fill(AppDesign.Colors.calendarSurface)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg))
            }
            .frame(width: PanelGeometry.panelWidth)
            .onAppear {
                store.send(.onAppear)
                let model = aiQueryModel
                let calendarStore = store
                panel?.aiSettingsDidChange = { [weak model, weak calendarStore] enabled, preference in
                    model?.synchronizeSettings(enabled: enabled, preference: preference)
                    if let calendarStore, calendarStore.showAISearch != enabled {
                        calendarStore.send(.reloadPreferences)
                    }
                }
                let settings = loadAISettings()
                synchronizeAISettings(settings.enabled, settings.preference)
                aiQueryModel.setPanelVisible(panel?.isVisible == true)
                reconcileLogicalDate()
                setupKeyMonitor()
                setupScrollMonitor()
            }
            .onDisappear {
                editorFocusGeneration += 1
                aiQueryModel.setPanelVisible(false)
                removeMonitors()
                pendingFooterFocus = nil
                consumesQuitEscapeRepeats = false
                store.send(.onDisappear)
            }
            .onChange(of: layout.isOverflowing) { _, _ in
                scrollRouter.suspendNavigation()
            }
            .onChange(of: aiQueryModel.isEditorOpen) { _, active in
                panel?.isTextInputActive = active
                if active { reader.scrollTo("panel-ai-input", anchor: .center) }
                else { editorFocusGeneration += 1 }
            }
            .onChange(of: store.days) { _, _ in reconcileLogicalDate() }
            .onChange(of: logicalDate) { _, date in
                if gridHasFocus, let date { reader.scrollTo(date, anchor: .center) }
            }
            .onChange(of: gridHasFocus) { _, focused in
                if focused, let logicalDate { reader.scrollTo(logicalDate, anchor: .center) }
            }
            .onChange(of: CalendarPresentationSnapshot(
                keyboardSession: keyboardSession, editorFocused: aiFieldFocused
            ), initial: true) { _, snapshot in
                presentationObservation?(snapshot)
            }
            .onChange(of: layout.viewportHeight) { _, _ in
                if gridHasFocus, let logicalDate { reader.scrollTo(logicalDate, anchor: .center) }
            }
            .background(CalendarKeyboardOwnerObserver(
                relay: keyboardOwnerRelay, panel: panel, session: keyboardSession,
                onOwnerChange: { owner in
                    switch owner {
                    case .previousMonth, .today, .nextMonth:
                        reader.scrollTo("panel-header", anchor: .center)
                    case .searchPrompt, .searchDismiss, .editor:
                        reader.scrollTo("panel-ai-input", anchor: .center)
                    case .footerQuit, .footerPin, .footerCalendar, .footerSettings,
                         .quitCancel, .quitConfirm:
                        reader.scrollTo("panel-footer", anchor: .bottom)
                    case let owner? where owner.isAgendaEvent || owner == .agendaJoin:
                        reader.scrollTo("panel-agenda", anchor: .center)
                    default: break
                    }
                }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .calendarPreferencesDidChange)) { _ in
                store.send(.reloadPreferences)
                let settings = loadAISettings()
                synchronizeAISettings(settings.enabled, settings.preference)
                showQuitConfirm = false
                pendingFooterFocus = nil
                consumesQuitEscapeRepeats = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarPanelWillHide)) { notification in
                guard notification.object as? CalendarPanel === panel else { return }
                editorFocusGeneration += 1
                removeMonitors()
                aiQueryModel.setPanelVisible(false)
                aiFieldFocused = false
                controlFocus = nil
                logicalDate = nil
                gridHasFocus = false
                keyboardOwnerRelay.reset()
                isRecordingHotkey = false
                showQuitConfirm = false
                pendingFooterFocus = nil
                consumesQuitEscapeRepeats = false
                isMouseOverCalendar = false
                hoverResetToken &+= 1
                let preservesContext = notification.userInfo?[CalendarPanel.hidePreservesContextKey] as? Bool == true
                store.send(preservesContext ? .hiddenPreservingContext : .onDisappear)
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarPanelWillPresentSettings)) { notification in
                guard notification.object as? CalendarPanel === panel else { return }
                editorFocusGeneration += 1
                aiFieldFocused = false
                pendingFooterFocus = nil
                consumesQuitEscapeRepeats = false
                scrollRouter.suspendNavigation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarPanelDidShow)) { notification in
                guard notification.object as? CalendarPanel === panel else { return }
                editorFocusGeneration += 1
                // Preparation is hidden. Only actual native visibility is authoritative.
                aiQueryModel.setPanelVisible(panel?.isVisible == true)
                controlFocus = nil
                aiFieldFocused = false
                keyboardOwnerRelay.reset()
                pendingFooterFocus = nil
                consumesQuitEscapeRepeats = false
                scrollRouter.reset()
                keyboardSession += 1
                reconcileLogicalDate()
                reader.scrollTo("panel-content-top", anchor: .top)
                setupKeyMonitor()
                setupScrollMonitor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarPanelDidCompleteReopen)) { notification in
                guard notification.object as? CalendarPanel === panel else { return }
                aiQueryModel.setPanelVisible(panel?.isVisible == true)
                // Re-observe the real hierarchy after the native post-key reset.
                // Session changes never manufacture an ownerless observation.
                pendingFooterFocus = nil
                consumesQuitEscapeRepeats = false
                keyboardSession += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .hotkeyRecordingDidChange)) { notification in
                isRecordingHotkey = notification.object as? Bool ?? false
                scrollRouter.suspendNavigation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleEventSaved)) { _ in
                // EventKit confirmed the save (reducer delegate → ScheduleEventsClient):
                // close the editor so ⌘Z means Undo, not text undo.
                closeEditorAfterSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // Compares authorization only; agenda data changes arrive via EKEventStoreChanged.
                if panel?.isVisible == true { store.send(.applicationDidBecomeActive) }
            }
            .onReceive(eventChangeNotificationCenter.publisher(for: .EKEventStoreChanged)
                .map { @Sendable _ in () }
                .receive(on: RunLoop.main)) { _ in
                refreshEventsAfterStoreChange()
            }
        }
    }

    private func closeEditorAfterSave() {
        // The panel stays key (no app hand-back) so the Undo chip and ⌘Z keep working.
        guard aiQueryModel.isEditorOpen else { return }
        aiQueryModel.discardEditor()
    }

    @MainActor
    private func refreshEventsAfterStoreChange() {
        guard panel?.isVisible == true else { return }
        store.send(.refreshCalendarAuthorization)
    }

    nonisolated static func scrollPhase(_ phase: NSEvent.Phase) -> CalendarScrollRouter.Phase {
        if phase.contains(.cancelled) { return .cancelled }
        if phase.contains(.ended) { return .ended }
        if !phase.intersection([.began, .mayBegin]).isEmpty { return .began }
        if !phase.intersection([.changed, .stationary]).isEmpty { return .changed }
        return .none
    }

    // MARK: - Event Monitors

    /// Routing contract for the reused panel and its text editors.
    nonisolated static func shouldHandleNavigation(
        panelVisible: Bool, eventIsForPanel: Bool,
        editingText: Bool, modified: Bool
    ) -> Bool {
        panelVisible && eventIsForPanel && !editingText && !modified
    }

    private func setupKeyMonitor() {
        guard keyMonitor == nil else { return }
        let inputModality = inputModality
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // This newer monitor runs before the app-wide tracker and may consume the key.
            inputModality.note(.keyboard)
            guard let panel, panel.isVisible, NSApp.keyWindow === panel, event.window === panel,
                  !isRecordingHotkey else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let editingText = panel.firstResponder is NSTextView
            if !event.isARepeat { consumesQuitEscapeRepeats = false }
            // Cmd+G — activate inline AI input (if enabled)
            if event.keyCode == 5 && modifiers == .command && store.showAISearch {
                aiQueryModel.setEditorOpen(true)
                return nil
            }
            if CalendarKeyboardRouter.joinsMeeting(
                keyCode: event.keyCode, commandOnly: modifiers == .command,
                isRepeat: event.isARepeat, canJoin: store.joinableEvent != nil
            ) {
                if let joinable = store.joinableEvent { joinMeeting(joinable) }
                return nil
            }
            if CalendarKeyboardRouter.undoesAddedEvent(
                keyCode: event.keyCode, commandOnly: modifiers == .command,
                canUndo: store.schedule.canUndo, editingText: editingText
            ) {
                store.send(.schedule(.undoTapped))
                return nil
            }
            switch CalendarKeyboardRouter.slotPicker(
                CalendarKeyboardKey(nativeCode: event.keyCode),
                phase: event.isARepeat ? .repeatPress : .down,
                choosingSlots: store.schedule.phase == .choosing && !store.schedule.slots.isEmpty,
                editorOpen: aiQueryModel.isEditorOpen, editingText: editingText, modified: !modifiers.isEmpty,
                ownership: keyboardOwnerRelay.browseOwnership(in: panel)
            ) {
            case let .move(delta):
                store.send(.schedule(.moveSelection(delta)))
                return nil
            case .activate:
                // Same honest rule as Return in the field: only a picked time saves.
                if AISubmitRouter.route(phase: store.schedule.phase, canConfirm: store.schedule.canConfirm) == .confirm {
                    store.send(.schedule(.confirmTapped))
                }
                return nil
            case .consume:
                return nil
            default:
                break
            }

            switch event.keyCode {
            case 53:
                if showQuitConfirm {
                    guard modifiers.isEmpty else { return event }
                    if !event.isARepeat {
                        consumesQuitEscapeRepeats = true
                        cancelQuitConfirmation()
                    }
                    return nil
                }
                if consumesQuitEscapeRepeats, event.isARepeat, modifiers.isEmpty { return nil }
                if aiQueryModel.isEditorOpen {
                    aiQueryModel.discardEditor()
                    panel.deactivateTextInput()
                    return nil
                }
                store.send(.closePanel)
                panel.isPinned = false
                panel.orderOut(nil)
                return nil
            default:
                let route = CalendarKeyboardRouter.browse(
                    CalendarKeyboardKey(nativeCode: event.keyCode),
                    phase: event.isARepeat ? .repeatPress : .down,
                    ownership: keyboardOwnerRelay.browseOwnership(in: panel),
                    context: CalendarKeyboardContext(
                        visible: panel.isVisible, key: NSApp.keyWindow === panel,
                        eventForPanel: event.window === panel, recording: isRecordingHotkey,
                        modified: !modifiers.isEmpty, editingText: editingText
                    )
                )
                switch route {
                case let .browse(intent): sendBrowseIntent(intent); return nil
                case .consume: return nil
                default: return event
                }
            }
        }
    }

    private func keyboardContext() -> CalendarKeyboardContext {
        guard let panel, let event = NSApp.currentEvent, event.window === panel else {
            return CalendarKeyboardContext(
                visible: panel?.isVisible == true,
                key: panel != nil && NSApp.keyWindow === panel,
                eventForPanel: false
            )
        }
        return CalendarKeyboardContext(
            visible: panel.isVisible, key: NSApp.keyWindow === panel,
            eventForPanel: true,
            recording: isRecordingHotkey,
            modified: !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
            editingText: panel.firstResponder is NSTextView
        )
    }

    private func sendBrowseIntent(_ intent: CalendarBrowseIntent) {
        switch intent {
        case .previousMonth: store.send(.goToPreviousMonth)
        case .nextMonth: store.send(.goToNextMonth)
        case .previousYear: store.send(.goToPreviousYear)
        case .nextYear: store.send(.goToNextYear)
        case .today: store.send(.goToToday)
        }
    }

    private func reconcileLogicalDate() {
        logicalDate = CalendarKeyboardRouter.reconcile(
            logicalDate, days: store.days.map(\.date), selected: store.selectedDate,
            today: .now, displayedMonth: store.displayedMonth, calendar: store.calendar
        )
    }

    private func moveLogicalDate(_ delta: Int) {
        logicalDate = CalendarKeyboardRouter.move(
            logicalDate, by: delta, days: store.days.map(\.date), calendar: store.calendar
        )
    }

    private func activateLogicalDate() {
        guard let logicalDate, store.days.contains(where: {
            store.calendar.isDate($0.date, inSameDayAs: logicalDate)
        }) else { return }
        store.send(.dateTapped(logicalDate))
    }

    private func setupScrollMonitor() {
        guard scrollMonitor == nil else { return }
        let inputModality = inputModality
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // This newer monitor runs before the app-wide tracker and may consume the scroll.
            inputModality.note(.pointer)
            let result = scrollRouter.route(
                delta: event.scrollingDeltaY,
                panelVisible: panel?.isVisible == true,
                eventIsForPanel: panel != nil && event.window === panel,
                overCalendar: isMouseOverCalendar,
                recordingShortcut: isRecordingHotkey,
                contentOverflows: layout.isOverflowing,
                phase: Self.scrollPhase(event.phase),
                momentumPhase: Self.scrollPhase(event.momentumPhase)
            )
            switch result.direction {
            case .previous: store.send(.goToPreviousMonth)
            case .next: store.send(.goToNextMonth)
            case nil: break
            }
            return result.consumesEvent ? nil : event
        }
    }

    private func removeMonitors() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        scrollRouter.reset()
    }

    // MARK: - Caret

    private var caretView: some View {
        GeometryReader { _ in
            let caretWidth = AppDesign.Caret.width
            let xOffset = layout.caretXOffset

            Path { path in
                let r = AppDesign.Caret.tipRadius
                path.move(to: CGPoint(x: xOffset - caretWidth / 2, y: caretHeight))
                path.addLine(to: CGPoint(x: xOffset - r, y: r))
                path.addQuadCurve(
                    to: CGPoint(x: xOffset + r, y: r),
                    control: CGPoint(x: xOffset, y: -1)
                )
                path.addLine(to: CGPoint(x: xOffset + caretWidth / 2, y: caretHeight))
                path.closeSubpath()
            }
            .fill(AppDesign.Colors.calendarSurface)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        CalendarHeaderControls(
            monthYearString: store.monthYearString,
            todayIsDisabled: store.isShowingCurrentMonth
                && store.selectedDate.map { store.calendar.isDateInToday($0) } == true,
            previous: { store.send(.goToPreviousMonth) },
            today: { store.send(.goToToday) },
            next: { store.send(.goToNextMonth) },
            keyboardContext: keyboardContext, keyboardObservation: keyboardObservation,
            controlFocus: $controlFocus
        )
    }

    // MARK: - AI Query Field

    private var aiQueryField: some View {
        CalendarDateSearchRow(
            query: Binding(get: { aiQueryModel.draft }, set: { aiQueryModel.setDraft($0) }),
            isActive: Binding(get: { aiQueryModel.isEditorOpen }, set: { aiQueryModel.setEditorOpen($0) }),
            isProcessing: aiQueryModel.isProcessing, error: aiQueryModel.errorMessage,
            clarification: aiQueryModel.clarification,
            trailingChip: store.schedule.phase == .choosing ? ScheduleCopy.freeTimes(store.schedule.slots.count) : nil,
            focused: $aiFieldFocused, onSubmit: {
                // Invocation belongs to native onSubmit, never an open-row flag.
                var context = keyboardContext()
                context.editingText = false
                guard context.allowsRouting else { return }
                switch AISubmitRouter.route(phase: store.schedule.phase, canConfirm: store.schedule.canConfirm) {
                case .confirm: store.send(.schedule(.confirmTapped))
                case .ignore: break
                case .submit: submitAIQuery()
                }
            },
            onDismiss: { aiQueryModel.discardEditor() },
            onEditorAppear: {
                let generation = editorFocusGeneration
                let requestFocus: @MainActor () -> Void = {
                    guard generation == editorFocusGeneration, aiQueryModel.isEditorOpen,
                          let panel, panel.isVisible, panel.isKeyWindow,
                          NSApp.keyWindow === panel else { return }
                    aiFieldFocused = true
                }
                if let editorPresentation {
                    editorPresentation(requestFocus)
                } else {
                    panel?.activateForTextInput()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        requestFocus()
                    }
                }
            }, keyboardContext: keyboardContext, keyboardObservation: keyboardObservation,
            controlFocus: $controlFocus
        )
    }

    @ViewBuilder
    private var aiResults: some View {
        if let answer = store.aiAnswer {
            AIAnswerRow(answer: answer)
        } else if let highlight = store.highlight {
            AIRangeSummaryRow(highlight: highlight, summary: AIRangeSummary(
                highlight: highlight, displayedMonth: store.displayedMonth, calendar: store.calendar
            ))
        }
    }

    private func synchronizeAISettings(_ enabled: Bool, _ preference: AIProvider) {
        aiQueryModel.synchronizeSettings(enabled: enabled, preference: preference)
        if store.showAISearch != enabled { store.send(.reloadPreferences) }
    }

    private func submitAIQuery() {
        aiQueryModel.setPanelVisible(panel?.isVisible == true)
        let settings = loadAISettings()
        synchronizeAISettings(settings.enabled, settings.preference)
        let draft = aiQueryModel.draft
        guard let task = aiQueryModel.submit() else { return }
        querySubmissionObservation?(draft, task)
    }

    // MARK: - Calendar Section

    // Weekday symbol arrays are locale-stable for the process lifetime; read once
    // instead of allocating Calendar.current on every render / grid cell.
    private static let shortWeekdaySymbols = Calendar.current.shortWeekdaySymbols
    private static let fullWeekdaySymbols = Calendar.current.weekdaySymbols
    private static let veryShortWeekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    private func calendarSection(keyboardFocused: Bool) -> some View {
        let cal = store.calendar
        let days = store.days
        let orderedDays = orderedWeekdaySymbols(startOfWeekday: store.startOfWeekday)
        let gridInfo = store.gridInfo
        let shortNames = Self.shortWeekdaySymbols
        let entries = dayIndex.entries(for: days, calendar: cal)
        let cellContext = dayCellContext(calendar: cal, keyboardFocused: keyboardFocused)

        if days.count != 42 {
            AppLogger.calendar.error("Expected 42 calendar days, got \(days.count)")
        }

        return VStack(spacing: AppDesign.Spacing.xs) {
            HStack(spacing: 0) {
                Text("Wk")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppDesign.Colors.calendarContextText)
                    .frame(width: AppDesign.Grid.weekNumberWidth)

                ForEach(orderedDays, id: \.index) { day in
                    let isWeekend = day.index == 1 || day.index == 7
                    Text(shortNames[day.index - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isWeekend ? Color.primary : AppDesign.Colors.calendarContextText)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Self.fullWeekdaySymbols[day.index - 1])
                }
            }

            if days.count == 42 {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { row in
                            let weekDate = days[row * 7].date
                            Text("\(cal.component(.weekOfYear, from: weekDate))")
                                .font(.caption2)
                                .foregroundStyle(AppDesign.Colors.calendarContextText)
                                .frame(
                                    width: AppDesign.Grid.weekNumberWidth,
                                    height: AppDesign.Grid.cellHeight
                                )
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { col in
                                    let index = row * 7 + col
                                    let weekday = orderedDays[col].index
                                    dayCell(days[index], entry: entries[index],
                                            isWorkdayColumn: store.workdays.contains(weekday),
                                            context: cellContext)
                                }
                            }
                        }
                    }
                    .overlay {
                        MonthBorderShape(
                            startCol: gridInfo.startCol,
                            endCol: gridInfo.endCol,
                            endRow: gridInfo.endRow
                        )
                        .stroke(
                            Color.secondary.opacity(AppDesign.Grid.monthBorderOpacity),
                            lineWidth: 1
                        )
                    }
                }
            }
        }
        .padding(AppDesign.Spacing.sm)
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg)
                .strokeBorder(
                    Color.secondary.opacity(AppDesign.Grid.outerBorderOpacity),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Calendar grid for \(store.monthYearString)" +
            (keyboardFocused ? logicalDate.map { ", focused date: \($0.formatted(Self.accessibilityDateStyle))" } ?? "" : "")
        )
        .accessibilityHint("Arrow keys move the focused date. Return or Space selects it.")
    }

    private func orderedWeekdaySymbols(startOfWeekday: Int) -> [(index: Int, symbol: String)] {
        let symbols = Self.veryShortWeekdaySymbols
        return (0..<7).map { offset in
            let weekday = ((startOfWeekday - 1 + offset) % 7) + 1
            return (index: weekday, symbol: symbols[weekday - 1])
        }
    }

    /// Resolved once per pass: three day starts and two accent colors for all 42 cells.
    private func dayCellContext(calendar cal: Calendar, keyboardFocused: Bool) -> DayCellContext {
        DayCellContext(
            todayStart: cal.startOfDay(for: Date()),
            selectedStart: store.selectedDate.map(cal.startOfDay(for:)),
            logicalStart: keyboardFocused ? logicalDate.map(cal.startOfDay(for:)) : nil,
            highlightedDays: store.highlightedDays,
            highlightSuffix: Self.highlightSuffix(store.highlight),
            keyboardFocused: keyboardFocused,
            showsFocusRing: inputModality.showsFocusRing,
            hoverResetToken: hoverResetToken,
            todayFill: AppDesign.Colors.calendarSolidFill(.accentColor, in: environment),
            accent: AppDesign.Colors.calendarEssentialAccent(in: environment)
        )
    }

    private func dayCell(
        _ day: GlimpseCore.CalendarDay, entry: CalendarDayEntry,
        isWorkdayColumn: Bool, context: DayCellContext
    ) -> some View {
        let model = DayCellModel(day: day, entry: entry, isWorkdayColumn: isWorkdayColumn, context: context)
        let store = store
        let logicalDate = $logicalDate
        return DayCell(model: model) {
            if model.keyboardFocused { logicalDate.wrappedValue = model.date }
            store.send(.dateTapped(model.date))
        }
        .equatable()
        .id(day.date)
    }

    // Thread-safe, allocation-free formatting (see gotchas.md: prefer Date.FormatStyle
    // over DateFormatter). Allocating a DateFormatter per day cell was the dominant
    // per-render cost — 42 allocations every body evaluation, evaluated eagerly by
    // .accessibilityLabel regardless of whether VoiceOver is active.
    private static let accessibilityDateStyle = Date.FormatStyle.dateTime
        .weekday(.wide).month(.wide).day().year()

    nonisolated static func highlightSuffix(_ highlight: DateRangeHighlight?) -> String {
        highlight.map { ", highlighted, \($0.label)" } ?? ", highlighted"
    }

    // MARK: - Agenda Date Context

    private static let agendaDateStyle = Date.FormatStyle.dateTime
        .weekday(.abbreviated).month(.abbreviated).day().year()

    private var agendaDateContext: some View {
        let date = store.eventsDate ?? store.selectedDate ?? Date()
        let isToday = store.calendar.isDateInToday(date)
        let selectedWeek = store.selectedDate.flatMap { selected in
            store.calendar.isDate(selected, inSameDayAs: date)
                ? Calendar.current.component(.weekOfYear, from: selected)
                : nil
        }
        var label = "Calendar events for \(date.formatted(Self.accessibilityDateStyle))"
        if isToday { label += ", today" }
        if let selectedWeek { label += ", selected date, Week \(selectedWeek)" }

        return HStack(alignment: .top, spacing: AppDesign.Spacing.sm) {
            Image(systemName: "calendar.circle")
                .font(.subheadline)
                .foregroundStyle(AppDesign.Colors.calendarEssentialAccent(in: environment))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text("Events · \(isToday ? "Today" : date.formatted(Self.agendaDateStyle))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let selectedWeek {
                    Text("Selected date · Week \(selectedWeek)")
                        .font(.caption)
                        .foregroundStyle(AppDesign.Colors.calendarContextText)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Events Section

    /// The events list, or the free-time proposal while an AI "create" is open,
    /// plus the Undo chip after a save.
    private var agendaContent: some View {
        VStack(spacing: 12) {
            if store.schedule.isProposing {
                ScheduleProposalView(
                    store: store.scope(state: \.schedule, action: \.schedule),
                    calendar: store.calendar,
                    keyboard: ScheduleKeyboard(context: keyboardContext, observe: keyboardObservation,
                                               focus: $controlFocus)
                )
            } else {
                eventsSection
            }
            if let chip = store.schedule.undo {
                ScheduleUndoChip(chip: chip) { store.send(.schedule(.undoTapped)) }
                    .transition(.opacity)
            }
        }
        .animation(AppDesign.Animation.chip, value: store.schedule.undo == nil)
    }

    private var calendarAccessMessage: String {
        switch store.calendarAuthorizationStatus {
        case .restricted: "Calendar access is restricted on this Mac."
        case .writeOnly: "Allow full calendar access to read events."
        default: "Calendar access is off."
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        if store.isRequestingCalendarAccess {
            HStack(spacing: AppDesign.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Requesting calendar access…").font(.subheadline)
            }
        } else if !store.calendarAccessGranted {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                if store.calendarAuthorizationStatus == .notDetermined {
                    Button("Show calendar events") { store.send(.requestCalendarAccess) }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .accessibilityLabel("Grant calendar access to show events")
                } else {
                    Text(calendarAccessMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    if store.calendarAuthorizationStatus != .restricted {
                        Button("Open Calendar Privacy Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .font(.caption)
                    }
                }
                if let error = store.calendarAccessError {
                    Text(error).font(.caption).foregroundStyle(.primary)
                }
            }
        } else if store.isLoadingEvents {
            HStack(spacing: AppDesign.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Loading events…").font(.subheadline).foregroundStyle(.primary)
            }
        } else if store.eventsError != nil {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text("Couldn’t load events.").font(.caption).foregroundStyle(.primary)
                Button("Retry") { store.send(.retryEvents) }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel("Retry loading calendar events")
            }
        } else if store.events.isEmpty {
            HStack {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("No events")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        } else {
            VStack(alignment: .leading, spacing: AppDesign.Agenda.rowSpacing) {
                let owners = CalendarKeyboardOwner.agendaEvents
                ForEach(Array(zip(store.events.prefix(owners.count), owners)), id: \.0.id) { event, owner in
                    CalendarAgendaEventRow(
                        event: event, owner: owner, open: { openEventInCalendar(event) },
                        join: event.id == store.joinableEventID ? { joinMeeting(event) } : nil,
                        badge: store.state.agendaBadge(for: event),
                        keyboardContext: keyboardContext, keyboardObservation: keyboardObservation,
                        controlFocus: $controlFocus
                    )
                }

                if store.events.count > owners.count {
                    Text("+\(store.events.count - owners.count) more")
                        .font(.caption)
                        .foregroundStyle(AppDesign.Colors.calendarContextText)
                        .padding(.horizontal, AppDesign.Agenda.rowHorizontalInset)
                }
                if let error = store.eventOpenError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppDesign.Agenda.rowHorizontalInset)
                        .announcing(error)
                }
            }
            .padding(.horizontal, AppDesign.Agenda.listHorizontalPadding)
            .padding(.vertical, AppDesign.Agenda.listVerticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.md)
                    .strokeBorder(Color.secondary.opacity(AppDesign.Grid.borderOpacity), lineWidth: 1)
            )
            .id("panel-agenda")
        }
    }

    /// Clicking or Return/Space on a row: the reducer opens Calendar through its client.
    /// Going to Calendar is a deliberate handoff, so the external-app restoration lease is
    /// abandoned (Glimpse must not re-front the previous app over Calendar) and any deferred
    /// editor focus is cancelled. A pinned panel stays; an unpinned one hides.
    private func openEventInCalendar(_ event: GlimpseCore.CalendarEvent) {
        editorFocusGeneration += 1
        store.send(.openEventInCalendar(event))
        panel?.prepareForExternalAppHandoff()
    }

    /// Join (button, Return on it, or ⌘J): the reducer opens the validated link through its
    /// client. Like opening Calendar, this hands off to another app, so the restoration lease
    /// is abandoned and deferred editor focus cancelled.
    private func joinMeeting(_ event: GlimpseCore.CalendarEvent) {
        editorFocusGeneration += 1
        store.send(.joinMeeting(event))
        panel?.prepareForExternalAppHandoff()
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 0) {
            Divider()

            if showQuitConfirm {
                quitConfirmation
            } else {
                footerButtons
            }
        }
    }

    private var footerButtons: some View {
        CalendarFooterControls(
            isPinned: store.isPinned,
            togglePin: { panel?.setPinned(!store.isPinned) },
            quit: beginQuitConfirmation,
            openSettings: { panel?.requestSettings?() },
            keyboardContext: keyboardContext,
            keyboardObservation: keyboardObservation,
            controlFocus: $controlFocus,
            trailingInset: layout.isOverflowing ? AppDesign.Footer.scrollbarClearance : 0
        )
        .onAppear { applyPendingFooterFocus(.footerQuit) }
        .transition(.identity)
    }

    /// The confirmation takes over the whole footer bar: Cancel fills the left half,
    /// the destructive Quit the right half, each a full-height hit target.
    private var quitConfirmation: some View {
        HStack(spacing: 0) {
            Button(action: cancelQuitConfirmation) {
                Text("Cancel")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .overlay { CalendarKeyboardFocusOutline() }
            }
            .buttonStyle(CalendarQuitHalfButtonStyle(role: .cancel))
            .modifier(CalendarControlReturn(
                owner: .quitCancel, context: keyboardContext, action: cancelQuitConfirmation,
                observe: keyboardObservation, focus: $controlFocus
            ))
            .accessibilityLabel("Cancel quitting Glimpse")
            .accessibilityInputLabels(["Cancel", "Cancel quitting Glimpse"])
            .help("Cancel quitting Glimpse")

            Button(action: confirmQuit) {
                Text("Quit Glimpse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .overlay { CalendarKeyboardFocusOutline(color: .white) }
            }
            .buttonStyle(CalendarQuitHalfButtonStyle(role: .destructive))
            .modifier(CalendarControlReturn(
                owner: .quitConfirm, context: keyboardContext, action: confirmQuit,
                observe: keyboardObservation, focus: $controlFocus
            ))
            .accessibilityLabel("Confirm quitting Glimpse")
            // Voice Control matches the visible text, not the AX label.
            .accessibilityInputLabels(["Quit Glimpse", "Quit", "Confirm quitting Glimpse"])
            // .help is AXHelp on macOS (as is .accessibilityHint): one string carries the question.
            .help("Quit Glimpse?")
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppDesign.Footer.height)
        .padding(.trailing, layout.isOverflowing ? AppDesign.Footer.scrollbarClearance : 0)
        .onAppear { applyPendingFooterFocus(.quitCancel) }
        .transition(.identity)
    }

    private func beginQuitConfirmation() {
        guard !showQuitConfirm else { return }
        editorFocusGeneration += 1
        pendingFooterFocus = .quitCancel
        controlFocus = nil
        showQuitConfirm = true
    }

    private func cancelQuitConfirmation() {
        guard showQuitConfirm else { return }
        editorFocusGeneration += 1
        pendingFooterFocus = .footerQuit
        controlFocus = nil
        showQuitConfirm = false
    }

    private func confirmQuit() {
        guard showQuitConfirm else { return }
        quitApplication()
    }

    private func applyPendingFooterFocus(_ owner: CalendarKeyboardOwner) {
        guard pendingFooterFocus == owner else { return }
        pendingFooterFocus = nil
        // This is a presentation request. Only the focused local handler and
        // its current event context can authorize keyboard activation.
        guard let panel, panel.isVisible, NSApp.keyWindow === panel,
              !isRecordingHotkey,
              showQuitConfirm == (owner == .quitCancel) else { return }
        controlFocus = owner
    }

}

@MainActor
struct CalendarHeaderControls: View {
    let monthYearString: String
    let todayIsDisabled: Bool
    let previous: () -> Void
    let today: () -> Void
    let next: () -> Void
    var keyboardContext: () -> CalendarKeyboardContext = { .init(visible: false) }
    var keyboardObservation: ((CalendarKeyboardInvocation) -> Void)? = nil
    var controlFocus: FocusState<CalendarKeyboardOwner?>.Binding? = nil

    var body: some View {
        HStack {
            Text(monthYearString)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            HStack(spacing: AppDesign.Spacing.sm + 2) {
                Button(action: previous) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: AppDesign.Control.iconTargetSize,
                               height: AppDesign.Control.iconTargetSize)
                        .contentShape(Rectangle())
                        .overlay { CalendarKeyboardFocusOutline() }
                }
                .buttonStyle(.plain)
                .modifier(CalendarControlReturn(
                    owner: .previousMonth, context: keyboardContext, action: previous,
                    observe: keyboardObservation, focus: controlFocus
                ))
                .accessibilityLabel("Previous month")

                Button(action: today) {
                    Text("Today")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(todayIsDisabled ? Color.secondary : Color.primary)
                        .frame(minWidth: AppDesign.Control.todayTargetWidth)
                        .frame(height: AppDesign.Control.iconTargetSize)
                        .background(
                            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm)
                                .fill(Color.secondary.opacity(AppDesign.Control.todayBackgroundOpacity))
                        )
                        .contentShape(Rectangle())
                        .overlay { CalendarKeyboardFocusOutline() }
                }
                .buttonStyle(.plain)
                .disabled(todayIsDisabled)
                .modifier(CalendarControlReturn(
                    owner: .today, context: keyboardContext, action: today,
                    observe: keyboardObservation, focus: controlFocus, isEnabled: !todayIsDisabled
                ))
                .accessibilityLabel("Go to today")
                .help("Go to today")

                Button(action: next) {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: AppDesign.Control.iconTargetSize,
                               height: AppDesign.Control.iconTargetSize)
                        .contentShape(Rectangle())
                        .overlay { CalendarKeyboardFocusOutline() }
                }
                .buttonStyle(.plain)
                .modifier(CalendarControlReturn(
                    owner: .nextMonth, context: keyboardContext, action: next,
                    observe: keyboardObservation, focus: controlFocus
                ))
                .accessibilityLabel("Next month")
            }
        }
        .padding(.trailing, AppDesign.Control.iconTrailingClearance)
    }

}

@MainActor
struct CalendarFooterControls: View {
    var isPinned = false
    var togglePin: () -> Void = {}
    let quit: () -> Void
    let openSettings: () -> Void
    var today: Date = Date()
    var keyboardContext: () -> CalendarKeyboardContext = { .init(visible: false) }
    var keyboardObservation: ((CalendarKeyboardInvocation) -> Void)? = nil
    var controlFocus: FocusState<CalendarKeyboardOwner?>.Binding? = nil
    var trailingInset: CGFloat = 0

    var body: some View {
        HStack(spacing: AppDesign.Footer.iconSpacing) {
            Text(todayContext)
                .font(.system(size: AppDesign.Footer.contextSize))
                .foregroundStyle(AppDesign.Colors.calendarContextText)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel("Today, \(todayContext)")
            Spacer(minLength: AppDesign.Spacing.sm)
            iconButton(isPinned ? "pin.fill" : "pin", owner: .footerPin,
                       name: isPinned ? "Unpin calendar window" : "Pin calendar window",
                       selected: isPinned, action: togglePin)
                .accessibilityValue(isPinned ? "Pinned" : "Not pinned")
                .help(isPinned ? "Unpin calendar window" : "Pin calendar window to keep it open")
            iconButton("gearshape", owner: .footerSettings,
                       name: "Open Glimpse Settings", action: openSettings)
                .help("Open Glimpse Settings (⌘,)")
            iconButton("power", owner: .footerQuit, name: "Quit Glimpse", action: quit)
                .accessibilityHint("Shows confirmation before quitting")
        }
        .padding(.leading, AppDesign.Footer.leadingInset)
        .padding(.trailing, AppDesign.Footer.trailingInset)
        .frame(height: AppDesign.Footer.height)
        .padding(.trailing, trailingInset)
    }

    /// e.g. "Week 45 · Thu, Nov 5" in the user's calendar and locale.
    private var todayContext: String {
        let week = Calendar.current.component(.weekOfYear, from: today)
        let date = today.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "Week \(week) · \(date)"
    }

    private func iconButton(
        _ symbol: String, owner: CalendarKeyboardOwner, name: String,
        selected: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: AppDesign.Footer.iconSize))
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .frame(width: AppDesign.Control.iconTargetSize, height: AppDesign.Control.iconTargetSize)
                .contentShape(Rectangle())
                .overlay { CalendarKeyboardFocusOutline() }
        }
        .buttonStyle(CalendarFooterButtonStyle(isSelected: selected))
        .modifier(CalendarControlReturn(
            owner: owner, context: keyboardContext, action: action,
            observe: keyboardObservation, focus: controlFocus
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .help(name)
    }
}

/// One half of the footer Quit confirmation: a flat full-cell fill with pressed/hover feedback.
private struct CalendarQuitHalfButtonStyle: ButtonStyle {
    enum Role { case cancel, destructive }
    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        CalendarQuitHalfAppearance(label: configuration.label, role: role, isPressed: configuration.isPressed)
    }
}

private struct CalendarQuitHalfAppearance<Label: View>: View {
    let label: Label
    let role: CalendarQuitHalfButtonStyle.Role
    let isPressed: Bool
    @Environment(\.self) private var environment
    @State private var isHovered = false

    var body: some View {
        label
            .background {
                switch role {
                case .cancel:
                    Color.primary.opacity(isPressed ? AppDesign.Footer.confirmationCancelPressedOpacity
                        : isHovered ? AppDesign.Footer.confirmationCancelHoverOpacity
                        : AppDesign.Footer.confirmationCancelOpacity)
                case .destructive:
                    // Darken (never lighten) on press so white text keeps its contrast.
                    AppDesign.Colors.calendarSolidFill(.red, in: environment)
                        .overlay(Color.black.opacity(isPressed ? AppDesign.Footer.confirmationDestructivePressedShade
                            : isHovered ? AppDesign.Footer.confirmationDestructiveHoverShade : 0))
                }
            }
            .onHover { isHovered = $0 }
    }
}

private struct CalendarFooterButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        CalendarFooterButtonAppearance(
            label: configuration.label, isPressed: configuration.isPressed, isSelected: isSelected
        )
    }
}

private struct CalendarFooterButtonAppearance<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        label
            .background(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm)
                    .fill(isSelected
                        ? Color.accentColor.opacity(AppDesign.Footer.pinnedBackgroundOpacity)
                        : Color.primary.opacity(isPressed ? AppDesign.Footer.pressedBackgroundOpacity
                            : isHovered ? AppDesign.Footer.hoverBackgroundOpacity : 0))
            )
            .onHover { isHovered = $0 }
    }
}
