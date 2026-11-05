import AppKit
import GlimpseCore
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @Bindable var store: StoreOf<PreferencesFeature>
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.self) private var environment
    @State private var hotkeyPreferences: HotkeyPreferencesModel
    private let notificationCenter: NotificationCenter
    private let onAISettingsChange: (@MainActor (Bool, AIProvider) -> Void)?
    private let recordingWindow: @MainActor () -> NSWindow?
    private let section: SettingsSection?
    private let calendarActions: SettingsCalendarActions?

    init(
        store: StoreOf<PreferencesFeature>,
        hotkeyPreferences: HotkeyPreferencesModel? = nil,
        notificationCenter: NotificationCenter = .default,
        onAISettingsChange: (@MainActor (Bool, AIProvider) -> Void)? = nil,
        calendarActions: SettingsCalendarActions? = nil,
        section: SettingsSection? = nil,
        recordingWindow: @escaping @MainActor () -> NSWindow? = { nil }
    ) {
        self.store = store
        _hotkeyPreferences = State(initialValue: hotkeyPreferences ?? HotkeyPreferencesModel())
        self.notificationCenter = notificationCenter
        self.onAISettingsChange = onAISettingsChange
        self.recordingWindow = recordingWindow
        self.section = section
        self.calendarActions = calendarActions
    }

    private let allWeekdays = Array(1...7)

    private var previewDateString: String {
        CalendarClient.liveValue.menuBarDateString(Date(), store.displayOptions)
    }

    private func notifyMenuBarChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            notificationCenter.post(name: .menuBarDisplayDidChange, object: nil)
        }
    }

    private func notifyCalendarChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            notificationCenter.post(name: .calendarPreferencesDidChange, object: nil)
        }
    }

    private func displayBinding(
        keyPath: WritableKeyPath<MenuBarDisplayOptions, Bool>,
        action: @escaping (Bool) -> PreferencesFeature.Action
    ) -> Binding<Bool> {
        Binding(
            get: { store.displayOptions[keyPath: keyPath] },
            set: { newValue in
                store.send(action(newValue))
                notifyMenuBarChanged()
            }
        )
    }

    var body: some View {
        // Keep all categories mounted so scrolling never tears down recording ownership.
        VStack(alignment: .leading, spacing: AppDesign.Settings.sectionSpacing) {
            if let section {
                settingsSection(section)
            } else {
                ForEach(SettingsSection.allCases) { section in
                    settingsSection(section)
                }
            }
        }
        .font(.system(size: AppDesign.Settings.labelFontSize))
        .foregroundStyle(.primary)
        .controlSize(.small)
        .onAppear { store.send(.onAppear) }
        .onReceive(notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.send(.refreshLaunchAtLogin)
        }
    }

    private func settingsSection(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Settings.headingSpacing) {
            Text(section.heading)
                .font(.system(size: AppDesign.Settings.headingFontSize, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 0) {
                switch section {
                case .general:
                    launchAtLoginRow
                    settingsDivider
                    hotkeyRow
                    if let calendarActions {
                        settingsDivider
                        pinCalendarRow(calendarActions)
                    }
                case .menuBar:
                    menuBarSettings
                case .calendar:
                    calendarSettings
                case .aiDateSearch:
                    aiSettingsRows
                }
            }
            .padding(.horizontal, AppDesign.Settings.groupHorizontalInset)
            .padding(.vertical, AppDesign.Settings.groupVerticalInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppDesign.Colors.settingsGroup(in: environment),
                in: RoundedRectangle(cornerRadius: AppDesign.Settings.groupCornerRadius)
            )
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: AppDesign.Settings.groupCornerRadius)
                        .strokeBorder(Color(nsColor: .labelColor),
                                      lineWidth: AppDesign.Settings.increasedContrastBorderWidth)
                }
            }
        }
    }

    // MARK: - Menu Bar

    private var menuBarSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuBarPreview
            .frame(maxWidth: .infinity)
            .frame(height: AppDesign.Settings.previewHeight)

            displayToggleRow

            settingsDivider

            settingsRow {
                Text("Filled background")
                Spacer()
                Toggle("Filled background", isOn: displayBinding(
                    keyPath: \.showFilledBackground,
                    action: { .setShowFilledBackground($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    private var menuBarPreview: some View {
        // The border and filled background are drawn into the composited image by
        // MenuBarItemRenderer, so no SwiftUI background/overlay is needed here.
        StatusItemPreview(
            displayOptions: store.displayOptions,
            dateString: previewDateString
        )
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("Menu bar preview")
        .accessibilityValue(previewAccessibilityDescription)
    }

    private var previewAccessibilityDescription: String {
        let dateString = previewDateString
        let hasDateText = !dateString.isEmpty
        let hasIcon = store.displayOptions.showIcon || !hasDateText
        let content = [
            hasIcon ? "Calendar icon" : nil,
            hasDateText ? dateString : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        return content + (store.displayOptions.showFilledBackground
            ? ", filled background" : ", bordered background")
    }

    private var displayToggleRow: some View {
        let options: [(String, String, WritableKeyPath<MenuBarDisplayOptions, Bool>, (Bool) -> PreferencesFeature.Action)] = [
            ("Icon", "Show icon in menu bar", \.showIcon, { .setShowIcon($0) }),
            ("Day of week", "Show day of week in menu bar", \.showDayOfWeek, { .setShowDayOfWeek($0) }),
            ("Month", "Show month in menu bar", \.showMonth, { .setShowMonth($0) }),
            ("Date", "Show date in menu bar", \.showDate, { .setShowDate($0) }),
            ("Year", "Show year in menu bar", \.showYear, { .setShowYear($0) }),
        ]

        return SettingsCheckboxFlow(spacing: AppDesign.Settings.checkboxSpacing) {
            ForEach(options, id: \.0) { label, accessibilityName, keyPath, action in
                Toggle(isOn: displayBinding(keyPath: keyPath, action: action)) {
                    Text(label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
                .frame(minHeight: AppDesign.Settings.minimumRowHeight, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel(accessibilityName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Calendar

    private var calendarSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsRow {
                Text("Week starts on")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Picker("Week starts on", selection: Binding(
                    get: { store.startOfWeekday },
                    set: { newValue in
                        store.send(.setStartOfWeekday(newValue))
                        notifyCalendarChanged()
                    }
                )) {
                    ForEach(allWeekdays, id: \.self) { weekday in
                        Text(Calendar.current.weekdaySymbols[weekday - 1])
                            .tag(weekday)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            settingsDivider

            VStack(alignment: .leading, spacing: AppDesign.Settings.statusSpacing) {
                Text("Workdays")
                SettingsCheckboxFlow(
                    spacing: AppDesign.Settings.workdaySpacing,
                    minimumCellWidth: AppDesign.Settings.workdayMinimumWidth
                ) {
                    ForEach(allWeekdays, id: \.self) { weekday in
                        workdayCheckbox(weekday)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            }
        }
    }

    private func workdayCheckbox(_ weekday: Int) -> some View {
        let shortNames = Calendar.current.shortWeekdaySymbols
        let compactNames = shortNames.map { String($0.prefix(2)) }
        let shortName = compactNames[weekday - 1]
        let fullName = Calendar.current.weekdaySymbols[weekday - 1]
        let label = compactNames.filter { $0 == shortName }.count > 1 ? fullName : shortName

        return Toggle(isOn: Binding(
            get: { store.workdays.contains(weekday) },
            set: { isSelected in
                guard isSelected != store.workdays.contains(weekday) else { return }
                store.send(.toggleWorkday(weekday))
                notifyCalendarChanged()
            }
        )) {
            Text(label)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .toggleStyle(.button)
        .frame(minHeight: AppDesign.Settings.minimumRowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel("\(fullName) workday")
        .help(fullName)
    }

    // MARK: - AI Date Search

    @ViewBuilder
    private var aiSettingsRows: some View {
        settingsRow {
            Text("Enabled")
            Spacer()
            Toggle("Enable AI date search", isOn: Binding(
                get: { store.showAISearch },
                set: { newValue in
                    store.send(.setShowAISearch(newValue))
                    onAISettingsChange?(store.showAISearch, store.aiProvider)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }

        if store.showAISearch {
            settingsDivider

            settingsRow {
                Text("Provider")
                Spacer()
                Picker("AI provider", selection: Binding(
                    get: { store.aiProvider },
                    set: { provider in
                        store.send(.setAIProvider(provider))
                        onAISettingsChange?(store.showAISearch, store.aiProvider)
                    }
                )) {
                    ForEach(GlimpseCore.AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: AppDesign.Settings.statusSpacing) {
            settingsRow {
                Text("Launch at login")
                Spacer()
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.send(.setLaunchAtLogin($0)) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(store.isUpdatingLaunchAtLogin || launchAtLoginNeedsRecovery)
                .accessibilityLabel("Launch at login")
                .accessibilityValue(launchAtLoginStatusText)
            }

            if store.isUpdatingLaunchAtLogin {
                HStack(spacing: AppDesign.Settings.statusSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating login item…")
                }
                .font(.system(size: AppDesign.Settings.labelFontSize))
                .accessibilityElement(children: .combine)
            } else if launchAtLoginNeedsRecovery {
                Text(launchAtLoginStatusText)
                    .font(.system(size: AppDesign.Settings.labelFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = store.launchAtLoginError {
                Text("Couldn’t change launch at login: \(error)")
                    .font(.system(size: AppDesign.Settings.labelFontSize))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if launchAtLoginNeedsRecovery || store.launchAtLoginError != nil {
                Button("Open Login Items") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: AppDesign.Settings.minimumRowHeight)
                .disabled(store.isUpdatingLaunchAtLogin)
                .accessibilityLabel("Open Login Items in System Settings")
            }
        }
        .help(launchAtLoginStatusText)
    }

    private var launchAtLoginNeedsRecovery: Bool {
        switch store.launchAtLoginStatus {
        case .requiresApproval, .notFound, .unavailable: true
        case .enabled, .notRegistered: false
        }
    }

    private var launchAtLoginStatusText: String {
        switch store.launchAtLoginStatus {
        case .enabled:
            "Enabled for your next login."
        case .requiresApproval:
            "Approval required. Allow Glimpse in Login Items to launch at login."
        case .notRegistered:
            "Off. Glimpse won’t open automatically when you log in."
        case .notFound:
            "macOS couldn’t find Glimpse’s login item. Check that Glimpse is installed in Applications."
        case .unavailable:
            "macOS couldn’t determine Glimpse’s login item status."
        }
    }

    // MARK: - Hotkey

    private var hotkeyRow: some View {
        VStack(alignment: .leading, spacing: AppDesign.Settings.statusSpacing) {
            settingsRow {
                Text("Global shortcut")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                hotkeyRecorder
                Toggle("Global shortcut", isOn: Binding(
                    get: { hotkeyPreferences.isEnabled },
                    set: { hotkeyPreferences.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Global shortcut")
                .accessibilityValue(hotkeyPreferences.isEnabled ? "On" : "Off")
            }

            if hotkeyPreferences.isRecording ||
                (!hotkeyPreferences.isEnabled && hotkeyPreferences.isRequested) {
                Text(hotkeyStatusText)
                    .font(.system(size: AppDesign.Settings.supportingFontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !hotkeyPreferences.isEnabled && hotkeyPreferences.isRequested {
                Button("Keep shortcut off") {
                    hotkeyPreferences.setEnabled(false)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: AppDesign.Settings.minimumRowHeight)
                .accessibilityLabel("Keep global shortcut off")
            }

            if let error = hotkeyPreferences.errorMessage {
                Text(error)
                    .font(.system(size: AppDesign.Settings.labelFontSize))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(hotkeyStatusText)
        .onDisappear { hotkeyPreferences.cancelRecording() }
    }

    private var hotkeyRecorder: some View {
        Button {
            if hotkeyPreferences.isRecording {
                hotkeyPreferences.cancelRecording()
            } else {
                startRecording()
            }
        } label: {
            Text(hotkeyRecorderLabel)
                .font(.system(size: AppDesign.Settings.labelFontSize))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .frame(width: AppDesign.Settings.recorderWidth)
        .frame(minHeight: AppDesign.Settings.minimumRowHeight)
        .accessibilityLabel(hotkeyPreferences.isRecording
            ? "Cancel shortcut recording"
            : (hotkeyPreferences.isEnabled ? "Change global shortcut" : "Set and enable shortcut"))
        .accessibilityValue(hotkeyPreferences.displayedCombo.displayString)
        .accessibilityHint(hotkeyRecorderHint)
    }

    private var hotkeyRecorderLabel: String {
        hotkeyPreferences.isRecording ? "Press shortcut…" : hotkeyPreferences.displayedCombo.displayString
    }

    private var hotkeyRecorderHint: String {
        if hotkeyPreferences.isRecording {
            return "Press a key with a modifier. Press Escape or activate this button again to cancel."
        }
        return hotkeyPreferences.isEnabled
            ? "Record another combination to replace the current global shortcut."
            : "Record a combination to set and enable the global shortcut."
    }

    private var hotkeyStatusText: String {
        if hotkeyPreferences.isRecording {
            return "Include a modifier key. Press Escape to cancel."
        }
        if hotkeyPreferences.isEnabled {
            return "On. \(hotkeyPreferences.displayedCombo.displayString) opens the calendar."
        }
        let saved = "Off. Saved shortcut: \(hotkeyPreferences.displayedCombo.displayString)."
        return hotkeyPreferences.isRequested ? saved + " Glimpse will try it again next launch." : saved
    }

    private func startRecording() {
        guard !hotkeyPreferences.isRecording,
              let window = recordingWindow(), window.isVisible, window.isKeyWindow,
              NSApplication.shared.keyWindow === window else { return }
        hotkeyPreferences.beginRecording(using: .live(window: window))
    }

    // MARK: - Shared Components

    private func pinCalendarRow(_ actions: SettingsCalendarActions) -> some View {
        settingsRow {
            Text("Pin calendar")
            Spacer()
            Toggle("Pin calendar", isOn: Binding(
                get: { actions.isPinned },
                set: { actions.isPinned = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(actions.calendar == nil)
            .accessibilityLabel("Pin calendar")
            .help("Keep the calendar open when you switch to another app.")
        }
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color(nsColor: contrast == .increased ? .labelColor : .separatorColor))
            .frame(height: AppDesign.Settings.groupBorderWidth)
            .padding(.vertical, AppDesign.Settings.dividerInset)
            .accessibilityHidden(true)
    }

    private func settingsRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: AppDesign.Settings.rowSpacing) {
            content()
        }
        .font(.system(size: AppDesign.Settings.labelFontSize))
        .frame(minHeight: AppDesign.Settings.minimumRowHeight)
    }

}

/// Measures native checkbox labels before wrapping, preserving document/focus order.
/// Workdays use equally sized adaptive cells; menu-bar choices use their natural widths.
private struct SettingsCheckboxFlow: Layout {
    var spacing: CGFloat
    var minimumCellWidth: CGFloat? = nil

    private struct Arrangement {
        var frames: [CGRect]
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, layout.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangement(width: CGFloat?, subviews: Subviews) -> Arrangement {
        guard !subviews.isEmpty else { return Arrangement(frames: [], size: .zero) }
        let idealSizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = idealSizes.reduce(CGFloat.zero) { $0 + $1.width }
            + spacing * CGFloat(subviews.count - 1)
        let availableWidth = max(1, width?.isFinite == true ? (width ?? naturalWidth) : naturalWidth)
        let cellWidth = minimumCellWidth.map { minimum in
            let required = max(minimum, idealSizes.map(\.width).max() ?? minimum)
            let fittingColumns = min(
                CGFloat(subviews.count), (availableWidth + spacing) / (required + spacing)
            )
            let columns = max(1, Int(fittingColumns))
            return max(1, (availableWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        }
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let itemWidth = min(availableWidth, cellWidth ?? idealSizes[index].width)
            if x > 0 && x + itemWidth > availableWidth + AppDesign.Settings.layoutTolerance {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: size.height))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return Arrangement(frames: frames, size: CGSize(width: availableWidth, height: y + rowHeight))
    }
}
