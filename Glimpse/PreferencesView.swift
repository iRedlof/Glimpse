import AppKit
import GlimpseCore
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @Bindable var store: StoreOf<PreferencesFeature>
    @State private var hotkeyPreferences: HotkeyPreferencesModel
    private let notificationCenter: NotificationCenter

    init(
        store: StoreOf<PreferencesFeature>,
        hotkeyPreferences: HotkeyPreferencesModel? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        _hotkeyPreferences = State(initialValue: hotkeyPreferences ?? HotkeyPreferencesModel())
        self.notificationCenter = notificationCenter
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
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm + 2) {
            displayCard
            calendarCard
            featuresCard
            brandedDivider
                .padding(.top, AppDesign.Spacing.xs)
        }
        .onAppear { store.send(.onAppear) }
        .onReceive(notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.send(.refreshLaunchAtLogin)
        }
    }

    // MARK: - Reusable Card Container

    private func settingsCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                content()
            }
            .padding(AppDesign.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.md)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
    }

    // MARK: - Display Card

    private var displayCard: some View {
        settingsCard("Display") {
            // Preview
            menuBarPreview
                .frame(maxWidth: .infinity)

            // Toggle pills row
            displayToggleRow

            cardDivider

            // Filled background
            settingsRow {
                Text("Filled background")
                Spacer()
                Toggle("Filled background", isOn: displayBinding(
                    keyPath: \.showFilledBackground,
                    action: { .setShowFilledBackground($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
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
    }

    private var displayToggleRow: some View {
        let options: [(String, String, WritableKeyPath<MenuBarDisplayOptions, Bool>, (Bool) -> PreferencesFeature.Action)] = [
            ("Icon", "Show icon in menu bar", \.showIcon, { .setShowIcon($0) }),
            ("Day", "Show day of week in menu bar", \.showDayOfWeek, { .setShowDayOfWeek($0) }),
            ("Mon", "Show month in menu bar", \.showMonth, { .setShowMonth($0) }),
            ("Date", "Show date in menu bar", \.showDate, { .setShowDate($0) }),
            ("Year", "Show year in menu bar", \.showYear, { .setShowYear($0) }),
        ]

        return HStack(spacing: AppDesign.Spacing.xs + 2) {
            ForEach(options, id: \.0) { label, accessibilityName, keyPath, action in
                let isOn = store.displayOptions[keyPath: keyPath]
                Button {
                    store.send(action(!isOn))
                    notifyMenuBarChanged()
                } label: {
                    Text(label)
                        .font(.caption2.weight(isOn ? .bold : .regular))
                        .padding(.horizontal, AppDesign.Spacing.sm)
                        .padding(.vertical, AppDesign.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                                .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12))
                        )
                        .foregroundStyle(isOn ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .contentShape(RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2))
                .accessibilityLabel(accessibilityName)
                .accessibilityValue(isOn ? "On" : "Off")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Calendar Card

    private var calendarCard: some View {
        settingsCard("Calendar") {
            // Week starts on
            settingsRow {
                Text("Week starts on")
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
                .frame(width: 110)
            }

            cardDivider

            // Workdays
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text("Workdays")
                    .font(.subheadline)

                HStack(spacing: AppDesign.Spacing.xs) {
                    ForEach(allWeekdays, id: \.self) { weekday in
                        workdayPill(weekday)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func workdayPill(_ weekday: Int) -> some View {
        let isSelected = store.workdays.contains(weekday)
        let symbol = Calendar.current.veryShortWeekdaySymbols[weekday - 1]
        let fullName = Calendar.current.weekdaySymbols[weekday - 1]

        return Button {
            store.send(.toggleWorkday(weekday))
            notifyCalendarChanged()
        } label: {
            Text(symbol)
                .font(.caption.weight(isSelected ? .bold : .regular))
                .frame(
                    width: AppDesign.Grid.todayCircleSize,
                    height: AppDesign.Grid.todayCircleSize
                )
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isSelected ? .white : .secondary)
                .contentShape(RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel("\(fullName), \(isSelected ? "workday" : "not a workday")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Features Card

    private var featuresCard: some View {
        settingsCard("Features") {
            // AI date search
            settingsRow {
                Text("AI date search")
                Spacer()
                Toggle("AI date search", isOn: Binding(
                    get: { store.showAISearch },
                    set: { newValue in
                        store.send(.setShowAISearch(newValue))
                    }
                ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }

            if store.showAISearch {
                cardDivider

                settingsRow {
                    Text("Provider")
                    Spacer()
                    Picker("AI provider", selection: $store.aiProvider.sending(\.setAIProvider)) {
                        ForEach(GlimpseCore.AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            cardDivider

            // Global shortcut
            hotkeyRow

            cardDivider

            launchAtLoginRow
        }
    }

    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            settingsRow {
                Text("Launch at login")
                Spacer()
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.send(.setLaunchAtLogin($0)) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(store.isUpdatingLaunchAtLogin || launchAtLoginNeedsRecovery)
                .accessibilityLabel("Launch at login")
                .accessibilityValue(launchAtLoginStatusText)
            }

            if store.isUpdatingLaunchAtLogin {
                HStack(spacing: AppDesign.Spacing.xs) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Updating login item…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(launchAtLoginStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = store.launchAtLoginError {
                Text("Couldn’t change launch at login: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if launchAtLoginNeedsRecovery || store.launchAtLoginError != nil {
                Button("Open Login Items") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, AppDesign.Spacing.xs)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(store.isUpdatingLaunchAtLogin)
                .accessibilityLabel("Open Login Items in System Settings")
            }
        }
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
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            settingsRow {
                Text("Global shortcut")
                Spacer()
                Toggle("Global shortcut", isOn: Binding(
                    get: { hotkeyPreferences.isEnabled },
                    set: { hotkeyPreferences.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Global shortcut")
                .accessibilityValue(hotkeyPreferences.isEnabled ? "On" : "Off")
            }

            Button {
                if hotkeyPreferences.isRecording {
                    hotkeyPreferences.cancelRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(hotkeyRecorderLabel)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(hotkeyPreferences.isEnabled ? 1.5 : 0)
                    .foregroundStyle(hotkeyPreferences.isRecording ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppDesign.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                            .fill(hotkeyPreferences.isRecording
                                ? Color.accentColor.opacity(0.1)
                                : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                            .strokeBorder(
                                hotkeyPreferences.isRecording ? Color.accentColor : Color.clear,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .contentShape(Rectangle())
            .accessibilityLabel(hotkeyPreferences.isRecording
                ? "Cancel shortcut recording"
                : (hotkeyPreferences.isEnabled ? "Change global shortcut" : "Set and enable shortcut"))
            .accessibilityValue(hotkeyPreferences.displayedCombo.displayString)
            .accessibilityHint(hotkeyRecorderHint)

            Text(hotkeyStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !hotkeyPreferences.isEnabled && hotkeyPreferences.isRequested {
                Button("Keep shortcut off") {
                    hotkeyPreferences.setEnabled(false)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, AppDesign.Spacing.xs)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Keep global shortcut off")
            }

            if let error = hotkeyPreferences.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { hotkeyPreferences.cancelRecording() }
        .onReceive(notificationCenter.publisher(for: .calendarPanelWillHide)) { _ in
            hotkeyPreferences.cancelRecording()
        }
    }

    private var hotkeyRecorderLabel: String {
        if hotkeyPreferences.isRecording { return "Press shortcut…" }
        return hotkeyPreferences.isEnabled
            ? hotkeyPreferences.displayedCombo.displayString : "Set and enable shortcut"
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
              let panel = NSApplication.shared.keyWindow as? NSPanel,
              panel.isVisible else { return }
        hotkeyPreferences.beginRecording(using: .live(panel: panel))
    }

    // MARK: - Branded Divider

    private var brandedDivider: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            VStack { Divider() }
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppDesign.Colors.accentRed)
                    .frame(width: AppDesign.Icon.accentLineWidth, height: AppDesign.Icon.accentLineHeight + 0.5)
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            VStack { Divider() }
        }
    }

    // MARK: - Shared Components

    private func settingsRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            content()
        }
        .font(.subheadline)
    }

    private var cardDivider: some View {
        Divider()
    }
}
