import GlimpseCore
import EventKit
import SwiftUI

struct CalendarPopoverView: View {
    @Bindable var store: StoreOf<CalendarFeature>
    weak var panel: CalendarPanel?

    let layout: PanelLayoutState

    @State private var scrollRouter = CalendarScrollRouter()
    @State private var scrollMonitor: Any?
    @State private var isMouseOverCalendar = false
    @State private var hoveredDate: Date?
    @State private var keyMonitor: Any?
    @State private var isRecordingHotkey = false
    @State private var aiTask: Task<Void, Never>?
    @State private var aiQueryText: String = ""
    @State private var aiProcessing: Bool = false
    @State private var aiErrorMessage: String?
    @State private var aiFieldActive: Bool = false
    @FocusState private var aiFieldFocused: Bool
    @State private var showQuitConfirm: Bool = false
    @State private var preferencesStore: StoreOf<PreferencesFeature>
    private let caretHeight = CalendarPanel.caretHeight

    init(store: StoreOf<CalendarFeature>, panel: CalendarPanel? = nil,
         layout: PanelLayoutState? = nil,
         preferencesStore: StoreOf<PreferencesFeature>? = nil) {
        self.store = store
        self.panel = panel
        self.layout = layout ?? panel?.layoutState ?? PanelLayoutState()
        self._preferencesStore = State(initialValue: preferencesStore ?? Store(
            initialState: PreferencesFeature.State.live()
        ) { PreferencesFeature() })
    }

    var body: some View {
        ScrollViewReader { reader in
            VStack(spacing: 0) {
                caretView.frame(height: caretHeight)
                PanelViewport(layout: layout) {
                    VStack(spacing: 12) {
                        if store.showingPreferences {
                            PreferencesView(store: preferencesStore)
                        }
                        headerView
                        if store.showAISearch {
                            aiQueryField
                                .id("panel-ai-input")
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        calendarSection
                            .onHover { hovering in
                                isMouseOverCalendar = hovering
                                if !hovering {
                                    hoveredDate = nil
                                    scrollRouter.suspendNavigation()
                                }
                            }
                        selectedDateInfo
                        eventsSection
                        footerView
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
                setupKeyMonitor()
                setupScrollMonitor()
            }
            .onDisappear {
                removeMonitors()
                store.send(.onDisappear)
            }
            .onChange(of: store.showingPreferences) { _, _ in
                reader.scrollTo("panel-content-top", anchor: .top)
                scrollRouter.suspendNavigation()
            }
            .onChange(of: layout.isOverflowing) { _, _ in
                scrollRouter.suspendNavigation()
            }
            .onChange(of: aiFieldActive) { _, active in
                panel?.isTextInputActive = active
                if active { reader.scrollTo("panel-ai-input", anchor: .center) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarPreferencesDidChange)) { _ in
                store.send(.reloadPreferences)
                showQuitConfirm = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarPanelWillHide)) { notification in
                guard notification.object as? CalendarPanel === panel else { return }
                removeMonitors()
                aiTask?.cancel()
                aiTask = nil
                aiProcessing = false
                aiFieldActive = false
                aiQueryText = ""
                aiErrorMessage = nil
                isRecordingHotkey = false
                showQuitConfirm = false
                isMouseOverCalendar = false
                hoveredDate = nil
                store.send(.onDisappear)
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarPanelDidShow)) { notification in
                guard notification.object as? CalendarPanel === panel else { return }
                scrollRouter.reset()
                reader.scrollTo("panel-content-top", anchor: .top)
                setupKeyMonitor()
                setupScrollMonitor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .hotkeyRecordingDidChange)) { notification in
                isRecordingHotkey = notification.object as? Bool ?? false
                scrollRouter.suspendNavigation()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if panel?.isVisible == true { store.send(.refreshCalendarAuthorization) }
            }
        }
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
            guard let panel, panel.isVisible, event.window === panel,
                  !isRecordingHotkey else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let editingText = panel.firstResponder is NSTextView || store.showingPreferences
            // Cmd+G — activate inline AI input (if enabled)
            if event.keyCode == 5 && modifiers == .command && store.showAISearch {
                aiFieldActive = true
                return nil
            }

            if [123, 124, 125, 126].contains(event.keyCode),
               !Self.shouldHandleNavigation(
                    panelVisible: panel.isVisible, eventIsForPanel: event.window === panel,
                    editingText: editingText, modified: !modifiers.isEmpty
               ) {
                return event
            }
            switch event.keyCode {
            case 123:
                store.send(.goToPreviousMonth)
                return nil
            case 124:
                store.send(.goToNextMonth)
                return nil
            case 125: // Down arrow
                store.send(.goToNextYear)
                return nil
            case 126: // Up arrow
                store.send(.goToPreviousYear)
                return nil
            case 36, 76: // Enter
                guard modifiers.isEmpty else { return event }
                if aiFieldActive {
                    submitAIQuery()
                } else if !editingText {
                    store.send(.goToToday)
                } else {
                    return event
                }
                return nil
            case 53:
                if aiFieldActive {
                    aiFieldActive = false
                    aiQueryText = ""
                    aiErrorMessage = nil
                    panel.deactivateTextInput()
                    return nil
                }
                if store.showingPreferences {
                    withAnimation(AppDesign.Animation.standard) {
                        _ = store.send(.togglePreferences)
                    }
                } else {
                    store.send(.closePanel)
                    panel.isPinned = false
                    panel.orderOut(nil)
                }
                return nil
            default:
                return event
            }
        }
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
            isShowingCurrentMonth: store.isShowingCurrentMonth,
            todayIsDisabled: store.isShowingCurrentMonth
                && store.selectedDate.map { store.calendar.isDateInToday($0) } == true,
            previous: { store.send(.goToPreviousMonth) },
            today: { store.send(.goToToday) },
            next: { store.send(.goToNextMonth) }
        )
    }

    // MARK: - AI Query Field

    private var aiQueryField: some View {
        CalendarDateSearchRow(
            query: $aiQueryText, isActive: $aiFieldActive,
            isProcessing: aiProcessing, error: $aiErrorMessage,
            focused: $aiFieldFocused, onSubmit: submitAIQuery,
            onEditorAppear: {
                panel?.activateForTextInput()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    aiFieldFocused = true
                }
            }
        )
    }

    private func submitAIQuery() {
        let query = aiQueryText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !aiProcessing else { return }
        aiProcessing = true
        aiErrorMessage = nil

        guard AIDateHelper.activeProvider() != .none else {
            aiProcessing = false
            aiErrorMessage = "On-device AI is unavailable. Choose Cloud AI in Preferences."
            return
        }

        aiTask?.cancel()
        aiTask = Task { @MainActor in
            let date = await AIDateHelper.parseNaturalLanguageDate(query)
            guard !Task.isCancelled else { return }
            aiProcessing = false
            if let date {
                aiQueryText = ""
                aiFieldActive = false
                store.send(.aiDateResult(date))
            } else {
                aiErrorMessage = "Couldn't parse that date. Try: \"next Friday\" or \"Jan 2028\""
            }
        }
    }

    // MARK: - Calendar Section

    // Weekday symbol arrays are locale-stable for the process lifetime; read once
    // instead of allocating Calendar.current on every render / grid cell.
    private static let shortWeekdaySymbols = Calendar.current.shortWeekdaySymbols
    private static let fullWeekdaySymbols = Calendar.current.weekdaySymbols
    private static let veryShortWeekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    private var calendarSection: some View {
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
                                .foregroundStyle(.tertiary)
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
                                    dayCell(day, using: cal, isWorkdayColumn: isWorkday)
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
                    Color.secondary.opacity(AppDesign.Grid.borderOpacity),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar grid for \(store.monthYearString)")
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
        isWorkdayColumn: Bool
    ) -> some View {
        let isToday = day.isCurrentMonth && cal.isDateInToday(day.date)
        let dayNumber = cal.component(.day, from: day.date)
        let isSelected = store.selectedDate.map { cal.isDate($0, inSameDayAs: day.date) } ?? false
        let isHovered = hoveredDate.map { cal.isDate($0, inSameDayAs: day.date) } ?? false

        return Button {
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
        }
            .buttonStyle(.plain)
            .focusable(false)
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
        if !day.isCurrentMonth { return .secondary.opacity(AppDesign.Grid.dimmedTextOpacity) }
        return .primary
    }

    // MARK: - Selected Date Info

    @ViewBuilder
    private var selectedDateInfo: some View {
        if let info = store.selectedDateInfo {
            HStack(spacing: AppDesign.Spacing.sm) {
                Image(systemName: "calendar.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                Text(info)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityLabel("Selected date: \(info)")
        }
    }

    // MARK: - Events Section

    private var eventsDayTitle: String {
        let date = store.eventsDate ?? store.selectedDate ?? Date()
        return store.calendar.isDateInToday(date)
            ? "Today"
            : date.formatted(.dateTime.month(.abbreviated).day().year())
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
        } else if let error = store.eventsError {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text("Couldn’t load events: \(error)").font(.caption).foregroundStyle(.red)
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
                Text(eventsDayTitle == "Today" ? "No events today" : "No events on \(eventsDayTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text(eventsDayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

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
            showingPreferences: store.showingPreferences,
            quit: {
                withAnimation(AppDesign.Animation.standard) {
                    showQuitConfirm = true
                }
            },
            about: { AboutWindow.show() },
            togglePin: {
                store.send(.togglePin)
                panel?.isPinned = store.isPinned
            },
            openCalendar: openAppleCalendar,
            togglePreferences: {
                withAnimation(AppDesign.Animation.standard) {
                    _ = store.send(.togglePreferences)
                }
            }
        )
    }

    private var quitConfirmation: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: "power")
                .font(.body)
                .foregroundStyle(Color.red.opacity(0.8))

            Text("Quit Glimpse?")
                .font(.subheadline.weight(.medium))

            Spacer()

            Button {
                withAnimation(AppDesign.Animation.standard) {
                    showQuitConfirm = false
                }
            } label: {
                Text("Cancel")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, AppDesign.Spacing.sm + 2)
                    .padding(.vertical, AppDesign.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppDesign.Spacing.sm + 2)
                    .padding(.vertical, AppDesign.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                            .fill(Color.red)
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
    let isShowingCurrentMonth: Bool
    let todayIsDisabled: Bool
    let previous: () -> Void
    let today: () -> Void
    let next: () -> Void

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
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Previous month")

                Button(action: today) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(
                            isShowingCurrentMonth
                                ? Color.secondary.opacity(0.3)
                                : Color.accentColor
                        )
                        .frame(width: AppDesign.Control.iconTargetSize,
                               height: AppDesign.Control.iconTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(todayIsDisabled)
                .accessibilityLabel("Go to today")

                Button(action: next) {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: AppDesign.Control.iconTargetSize,
                               height: AppDesign.Control.iconTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Next month")
            }
        }
        .padding(.trailing, AppDesign.Control.iconTrailingClearance)
    }

}

@MainActor
struct CalendarFooterControls: View {
    let isPinned: Bool
    let showingPreferences: Bool
    let quit: () -> Void
    let about: () -> Void
    let togglePin: () -> Void
    let openCalendar: () -> Void
    let togglePreferences: () -> Void

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Button {
                quit()
            } label: {
                Image(systemName: "power")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: AppDesign.Control.iconTargetSize,
                           height: AppDesign.Control.iconTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Quit Glimpse")

            Spacer()

            Button {
                about()
            } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: AppDesign.Control.iconTargetSize,
                           height: AppDesign.Control.iconTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("About Glimpse")

            Button {
                togglePin()
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.body)
                    .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                    .rotationEffect(.degrees(isPinned ? 0 : 45))
                    .frame(width: AppDesign.Control.iconTargetSize,
                           height: AppDesign.Control.iconTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(isPinned ? "Unpin window" : "Pin window")

            Button(action: openCalendar) {
                Image(systemName: "calendar")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: AppDesign.Control.iconTargetSize,
                           height: AppDesign.Control.iconTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Open Calendar app")

            Button {
                togglePreferences()
            } label: {
                Image(systemName: showingPreferences ? "gearshape.fill" : "gearshape")
                    .font(.body)
                    .foregroundStyle(
                        showingPreferences ? Color.accentColor : .secondary
                    )
                    .frame(width: AppDesign.Control.iconTargetSize,
                           height: AppDesign.Control.iconTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(
                showingPreferences ? "Close preferences" : "Open preferences"
            )
        }
        .padding(.trailing, AppDesign.Control.iconTrailingClearance)
    }

}

@MainActor
struct CalendarDateSearchRow: View {
    @Binding var query: String
    @Binding var isActive: Bool
    let isProcessing: Bool
    @Binding var error: String?
    let focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onEditorAppear: () -> Void

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
                    .onSubmit { onSubmit() }
                    .onAppear(perform: onEditorAppear)

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button {
                        isActive = false
                        query = ""
                        error = nil
                        // Don't call deactivateTextInput — it closes the panel
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: AppDesign.Control.dismissTargetSize,
                                   height: AppDesign.Control.dismissTargetSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel("Close date search")
                    .accessibilityHint("Clears the query and closes date search.")
                }
            } else {
                Button {
                    isActive = true
                } label: {
                    Text("Go to date...  ⌘G")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .focusable(false)
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
}
