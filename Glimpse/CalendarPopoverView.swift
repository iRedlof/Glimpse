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
    @State private var hoveredDate: Date?
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
            onDate: { store.send(.aiDateResult($0)) }
        ))
    }

    var body: some View {
        ScrollViewReader { reader in
            VStack(spacing: 0) {
                caretView.frame(height: caretHeight)
                PanelViewport(layout: layout) {
                    VStack(spacing: 12) {
                        headerView.id("panel-header")
                        if store.showAISearch {
                            aiQueryField
                                .id("panel-ai-input")
                                .transition(.opacity.combined(with: .move(edge: .top)))
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
                                    hoveredDate = nil
                                    scrollRouter.suspendNavigation()
                                }
                            }
                        agendaDateContext
                        eventsSection
                        footerView.id("panel-footer")
                    }
                    .padding()
                    .id("panel-content-top")
                }
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg)
                        .fill(.regularMaterial)
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
            .onChange(of: store.days.map(\.date)) { _, _ in reconcileLogicalDate() }
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
                    case .footerQuit, .footerAbout, .footerPin, .footerCalendar, .footerSettings,
                         .quitCancel, .quitConfirm:
                        reader.scrollTo("panel-footer", anchor: .bottom)
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
                hoveredDate = nil
                store.send(.onDisappear)
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
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if panel?.isVisible == true { store.send(.refreshCalendarAuthorization) }
            }
            .onReceive(eventChangeNotificationCenter.publisher(for: .EKEventStoreChanged)
                .map { @Sendable _ in () }
                .receive(on: RunLoop.main)) { _ in
                refreshEventsAfterStoreChange()
            }
        }
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
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
            .fill(.regularMaterial)
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
            focused: $aiFieldFocused, onSubmit: {
                // Invocation belongs to native onSubmit, never an open-row flag.
                var context = keyboardContext()
                context.editingText = false
                guard context.allowsRouting else { return }
                submitAIQuery()
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

        if days.count != 42 {
            AppLogger.calendar.error("Expected 42 calendar days, got \(days.count)")
        }

        return VStack(spacing: AppDesign.Spacing.xs) {
            HStack(spacing: 0) {
                Text("Wk")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: AppDesign.Grid.weekNumberWidth)

                ForEach(orderedDays, id: \.index) { day in
                    let isWeekend = day.index == 1 || day.index == 7
                    Text(shortNames[day.index - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isWeekend ? .primary : .secondary)
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
                                .foregroundStyle(.secondary)
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
                                    let day = days[row * 7 + col]
                                    let weekday = orderedDays[col].index
                                    let isWorkday = store.workdays.contains(weekday)
                                    dayCell(day, using: cal, isWorkdayColumn: isWorkday,
                                            keyboardFocused: keyboardFocused)
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

    private func dayCell(
        _ day: GlimpseCore.CalendarDay,
        using cal: Calendar,
        isWorkdayColumn: Bool, keyboardFocused: Bool
    ) -> some View {
        let isToday = day.isCurrentMonth && cal.isDateInToday(day.date)
        let dayNumber = cal.component(.day, from: day.date)
        let isSelected = store.selectedDate.map { cal.isDate($0, inSameDayAs: day.date) } ?? false
        let isHovered = hoveredDate.map { cal.isDate($0, inSameDayAs: day.date) } ?? false

        return Button {
            if keyboardFocused { logicalDate = day.date }
            store.send(.dateTapped(day.date))
        } label: {
            Text("\(dayNumber)")
                .font(.system(.body, design: .rounded))
                .fontWeight(isToday || isSelected ? .bold : .regular)
                .foregroundStyle(foregroundColor(for: day, isToday: isToday, isSelected: isSelected))
                .frame(maxWidth: .infinity)
                .frame(height: AppDesign.Grid.cellHeight)
                .background {
                    if isToday {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(
                                width: AppDesign.Grid.todayCircleSize,
                                height: AppDesign.Grid.todayCircleSize
                            )
                    } else if isSelected {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .frame(
                                width: AppDesign.Grid.todayCircleSize,
                                height: AppDesign.Grid.todayCircleSize
                            )
                    } else if isHovered {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(AppDesign.Grid.hoverBorderOpacity), lineWidth: 1)
                            .frame(
                                width: AppDesign.Grid.todayCircleSize,
                                height: AppDesign.Grid.todayCircleSize
                            )
                    } else if isWorkdayColumn && day.isCurrentMonth {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(AppDesign.Grid.workdayTintOpacity))
                    }
                }
                .foregroundStyle(isToday ? .white : foregroundColor(for: day, isToday: false, isSelected: isSelected))
                .contentShape(Rectangle())
                .overlay {
                    if keyboardFocused, logicalDate.map({
                        cal.isDate($0, inSameDayAs: day.date)
                    }) == true {
                        RoundedRectangle(cornerRadius: AppDesign.Control.focusCornerRadius)
                            .strokeBorder(Color.accentColor, lineWidth: AppDesign.Control.focusLineWidth)
                            .padding(AppDesign.Control.focusInset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
            .buttonStyle(.plain)
            .focusable(false)
            .id(day.date)
            .onHover { hovering in
                hoveredDate = hovering ? day.date : nil
            }
            .accessibilityLabel(dayAccessibilityLabel(day, dayNumber: dayNumber, isToday: isToday))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // Thread-safe, allocation-free formatting (see gotchas.md: prefer Date.FormatStyle
    // over DateFormatter). Allocating a DateFormatter per day cell was the dominant
    // per-render cost — 42 allocations every body evaluation, evaluated eagerly by
    // .accessibilityLabel regardless of whether VoiceOver is active.
    private static let accessibilityDateStyle = Date.FormatStyle.dateTime
        .weekday(.wide).month(.wide).day().year()

    private func dayAccessibilityLabel(
        _ day: GlimpseCore.CalendarDay, dayNumber: Int, isToday: Bool
    ) -> String {
        var label = day.date.formatted(Self.accessibilityDateStyle)
        if isToday { label += ", today" }
        if !day.isCurrentMonth { label += ", outside current month" }
        return label
    }

    private func foregroundColor(
        for day: GlimpseCore.CalendarDay, isToday: Bool, isSelected: Bool = false
    ) -> Color {
        if isToday { return .white }
        if isSelected { return Color.accentColor }
        if !day.isCurrentMonth { return .secondary }
        return .primary
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
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text("Events · \(isToday ? "Today" : date.formatted(Self.agendaDateStyle))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let selectedWeek {
                    Text("Selected date · Week \(selectedWeek)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Events Section

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
                        .foregroundStyle(.secondary)
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
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        } else if store.isLoadingEvents {
            HStack(spacing: AppDesign.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Loading events…").font(.subheadline).foregroundStyle(.secondary)
            }
        } else if store.eventsError != nil {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text("Couldn’t load events.").font(.caption).foregroundStyle(.red)
                Button("Retry") { store.send(.retryEvents) }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel("Retry loading calendar events")
            }
        } else if store.events.isEmpty {
            HStack {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Text("No events")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                ForEach(store.events.prefix(5)) { event in
                    HStack(spacing: AppDesign.Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(event.timeString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(event.title), \(event.timeString)")
                }

                if store.events.count > 5 {
                    Text("+\(store.events.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(AppDesign.Spacing.sm)
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.md)
                    .strokeBorder(Color.secondary.opacity(AppDesign.Grid.borderOpacity), lineWidth: 1)
            )
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: AppDesign.Spacing.sm) {
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
            quit: beginQuitConfirmation,
            about: { AboutWindow.show() },
            togglePin: {
                store.send(.togglePin)
                panel?.isPinned = store.isPinned
            },
            openCalendar: openAppleCalendar,
            openSettings: { panel?.requestSettings?() },
            keyboardContext: keyboardContext,
            keyboardObservation: keyboardObservation,
            controlFocus: $controlFocus
        )
        .onAppear { applyPendingFooterFocus(.footerQuit) }
        .transition(.identity)
    }

    private var quitConfirmation: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: "power")
                .font(.body)
                .foregroundStyle(Color.red.opacity(0.8))

            Text("Quit Glimpse?")
                .font(.subheadline.weight(.medium))

            Spacer()

            Button(action: cancelQuitConfirmation) {
                Text("Cancel")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, AppDesign.Spacing.sm + 2)
                    .frame(height: AppDesign.Control.iconTargetSize)
                    .background(
                        RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .contentShape(Rectangle())
                    .overlay { CalendarKeyboardFocusOutline() }
            }
            .buttonStyle(.plain)
            .modifier(CalendarControlReturn(
                owner: .quitCancel, context: keyboardContext, action: cancelQuitConfirmation,
                observe: keyboardObservation, focus: $controlFocus
            ))
            .accessibilityLabel("Cancel quitting Glimpse")
            .help("Cancel quitting Glimpse")

            Button(action: confirmQuit) {
                Text("Quit")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppDesign.Spacing.sm + 2)
                    .frame(height: AppDesign.Control.iconTargetSize)
                    .background(
                        RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                            .fill(Color.red)
                    )
                    .contentShape(Rectangle())
                    .overlay { CalendarKeyboardFocusOutline() }
            }
            .buttonStyle(.plain)
            .modifier(CalendarControlReturn(
                owner: .quitConfirm, context: keyboardContext, action: confirmQuit,
                observe: keyboardObservation, focus: $controlFocus
            ))
            .accessibilityLabel("Confirm quitting Glimpse")
            .help("Quit Glimpse")
        }
        .frame(height: AppDesign.Control.iconTargetSize)
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

    private func openAppleCalendar() {
        if let calURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.iCal"
        ) {
            NSWorkspace.shared.openApplication(
                at: calURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
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
                        .foregroundStyle(todayIsDisabled ? Color.secondary : Color.accentColor)
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
    let isPinned: Bool
    let quit: () -> Void
    let about: () -> Void
    let togglePin: () -> Void
    let openCalendar: () -> Void
    let openSettings: () -> Void
    var keyboardContext: () -> CalendarKeyboardContext = { .init(visible: false) }
    var keyboardObservation: ((CalendarKeyboardInvocation) -> Void)? = nil
    var controlFocus: FocusState<CalendarKeyboardOwner?>.Binding? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons(spacing: AppDesign.Spacing.sm)
            buttons(spacing: AppDesign.Spacing.xs)
        }
        .frame(height: AppDesign.Control.iconTargetSize)
        .padding(.trailing, AppDesign.Control.iconTrailingClearance)
    }

    private func buttons(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            iconButton("power", owner: .footerQuit, name: "Quit Glimpse", action: quit)
                .accessibilityHint("Shows confirmation before quitting")
            iconButton("info.circle", owner: .footerAbout, name: "About Glimpse", action: about)
            pinButton
            iconButton("calendar", owner: .footerCalendar, name: "Open Calendar app", action: openCalendar)
            settingsButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func iconButton(
        _ symbol: String, owner: CalendarKeyboardOwner, name: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: AppDesign.Control.iconTargetSize,
                       height: AppDesign.Control.iconTargetSize)
                .contentShape(Rectangle())
                .overlay { CalendarKeyboardFocusOutline() }
        }
        .buttonStyle(.plain)
        .modifier(CalendarControlReturn(
            owner: owner, context: keyboardContext, action: action,
            observe: keyboardObservation, focus: controlFocus
        ))
        .accessibilityLabel(name)
        .help(name)
    }

    private var pinButton: some View {
        Button(action: togglePin) {
            HStack(spacing: AppDesign.Spacing.xs) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.body)
                    .foregroundStyle(isPinned ? Color.accentColor : Color.primary)
                    .rotationEffect(.degrees(isPinned ? 0 : 45))
                Text(isPinned ? "Pinned" : "Pin")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: AppDesign.Footer.pinTargetWidth,
                   height: AppDesign.Control.iconTargetSize)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Control.focusCornerRadius)
                    .fill(Color.accentColor.opacity(
                        isPinned ? AppDesign.Footer.pinnedBackgroundOpacity : 0
                    ))
            )
            .contentShape(Rectangle())
            .overlay { CalendarKeyboardFocusOutline() }
        }
        .buttonStyle(.plain)
        .modifier(CalendarControlReturn(
            owner: .footerPin, context: keyboardContext, action: togglePin,
            observe: keyboardObservation, focus: controlFocus
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPinned ? "Unpin calendar window" : "Pin calendar window")
        .accessibilityValue(isPinned ? "Pinned" : "Not pinned")
        .help(isPinned ? "Unpin calendar window" : "Pin calendar window to keep it open")
    }

    private var settingsButton: some View {
        Button(action: openSettings) {
            HStack(spacing: AppDesign.Spacing.xs) {
                Image(systemName: "gearshape")
                    .font(.body)
                Text("Settings")
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(width: AppDesign.Footer.settingsTargetWidth,
                   height: AppDesign.Control.iconTargetSize)
            .contentShape(Rectangle())
            .overlay { CalendarKeyboardFocusOutline() }
        }
        .buttonStyle(.plain)
        .modifier(CalendarControlReturn(
            owner: .footerSettings, context: keyboardContext, action: openSettings,
            observe: keyboardObservation, focus: controlFocus
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open Glimpse Settings")
        .help("Open Glimpse Settings (⌘,)")
    }

}

@MainActor
struct CalendarDateSearchRow: View {
    @Binding var query: String
    @Binding var isActive: Bool
    let isProcessing: Bool
    let error: String?
    let focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onDismiss: () -> Void
    let onEditorAppear: () -> Void
    var keyboardContext: () -> CalendarKeyboardContext = { .init(visible: false) }
    var keyboardObservation: ((CalendarKeyboardInvocation) -> Void)? = nil
    var controlFocus: FocusState<CalendarKeyboardOwner?>.Binding? = nil

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(
                    isProcessing ? Color.accentColor :
                    isActive ? Color.accentColor :
                    Color.secondary.opacity(0.4)
                )

            if isActive {
                TextField("e.g. next Friday, Christmas...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .accessibilityLabel("Go to date using AI")
                    .focused(focused)
                    .focusedValue(\.calendarKeyboardOwner, .editor)
                    .onSubmit { onSubmit() }
                    .onAppear(perform: onEditorAppear)

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button(action: dismissSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: AppDesign.Control.dismissTargetSize,
                                   height: AppDesign.Control.dismissTargetSize)
                            .contentShape(Rectangle())
                            .overlay { CalendarKeyboardFocusOutline() }
                    }
                    .buttonStyle(.plain)
                    .modifier(CalendarControlReturn(
                        owner: .searchDismiss, context: keyboardContext, action: dismissSearch,
                        observe: keyboardObservation, focus: controlFocus
                    ))
                    .accessibilityLabel("Close date search")
                    .accessibilityHint("Clears the query and closes date search.")
                }
            } else {
                Button(action: openSearch) {
                    Text("Go to date...  ⌘G")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { CalendarKeyboardFocusOutline() }
                }
                .buttonStyle(.plain)
                .modifier(CalendarControlReturn(
                    owner: .searchPrompt, context: keyboardContext, action: openSearch,
                    observe: keyboardObservation, focus: controlFocus
                ))
                .accessibilityLabel("Go to date using AI")
            }
        }
        .padding(.horizontal, AppDesign.Spacing.sm)
        .padding(.vertical, AppDesign.Spacing.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                .fill(Color.secondary.opacity(isActive ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                .strokeBorder(
                    isActive ? Color.accentColor.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive {
                isActive = true
            }
        }

        if let error = error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func openSearch() { isActive = true }

    private func dismissSearch() {
        onDismiss()
        // Keep the reused panel's existing text activation/restoration lifecycle.
    }
}
