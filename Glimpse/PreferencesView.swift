import AppKit
import Carbon
import GlimpseCore
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @Bindable var store: StoreOf<PreferencesFeature>

    private let allWeekdays = Array(1...7)

    private var previewDateString: String {
        CalendarClient.liveValue.menuBarDateString(Date(), store.displayOptions)
    }

    private func notifyMenuBarChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .menuBarDisplayDidChange, object: nil)
        }
    }

    private func notifyCalendarChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .calendarPreferencesDidChange, object: nil)
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
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
                Toggle("", isOn: displayBinding(
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
        let options: [(String, WritableKeyPath<MenuBarDisplayOptions, Bool>, (Bool) -> PreferencesFeature.Action)] = [
            ("Icon", \.showIcon, { .setShowIcon($0) }),
            ("Day", \.showDayOfWeek, { .setShowDayOfWeek($0) }),
            ("Mon", \.showMonth, { .setShowMonth($0) }),
            ("Date", \.showDate, { .setShowDate($0) }),
            ("Year", \.showYear, { .setShowYear($0) }),
        ]

        return HStack(spacing: AppDesign.Spacing.xs + 2) {
            ForEach(options, id: \.0) { label, keyPath, action in
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
                Picker("", selection: Binding(
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
                Toggle("", isOn: Binding(
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
                    Picker("", selection: $store.aiProvider.sending(\.setAIProvider)) {
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
    // TODO: Extract hotkey recording into a dedicated HotkeyRecorderView
    // to separate concerns (SRP). The recording state, NSEvent monitor lifecycle,
    // and reserved shortcut validation are a self-contained subsystem.

    @State private var hotkeyEnabled: Bool = {
        UserDefaults.standard.object(forKey: "hotkeyEnabled") != nil
            ? UserDefaults.standard.bool(forKey: "hotkeyEnabled")
            : true
    }()
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any?
    @State private var hotkeyConflict: String?

    /// System shortcuts that must not be overridden.
    private static let reservedShortcuts: Set<HotkeyCombo> = {
        let cmd = UInt32(cmdKey)
        let cmdShift = UInt32(cmdKey | shiftKey)
        return [
            HotkeyCombo(keyCode: 12, modifiers: cmd),      // ⌘Q (Quit)
            HotkeyCombo(keyCode: 13, modifiers: cmd),      // ⌘W (Close)
            HotkeyCombo(keyCode: 4, modifiers: cmd),       // ⌘H (Hide)
            HotkeyCombo(keyCode: 46, modifiers: cmd),      // ⌘M (Minimize)
            HotkeyCombo(keyCode: 0, modifiers: cmd),       // ⌘A (Select All)
            HotkeyCombo(keyCode: 8, modifiers: cmd),       // ⌘C (Copy)
            HotkeyCombo(keyCode: 9, modifiers: cmd),       // ⌘V (Paste)
            HotkeyCombo(keyCode: 7, modifiers: cmd),       // ⌘X (Cut)
            HotkeyCombo(keyCode: 6, modifiers: cmd),       // ⌘Z (Undo)
            HotkeyCombo(keyCode: 49, modifiers: cmd),      // ⌘Space (Spotlight)
            HotkeyCombo(keyCode: 35, modifiers: cmd),      // ⌘P (Print)
            HotkeyCombo(keyCode: 1, modifiers: cmd),       // ⌘S (Save)
            HotkeyCombo(keyCode: 3, modifiers: cmd),       // ⌘F (Find)
            HotkeyCombo(keyCode: 17, modifiers: cmd),      // ⌘T (New Tab)
            HotkeyCombo(keyCode: 45, modifiers: cmd),      // ⌘N (New)
            HotkeyCombo(keyCode: 31, modifiers: cmd),      // ⌘O (Open)
            HotkeyCombo(keyCode: 4, modifiers: cmdShift),  // ⌘⇧H (Hide Others variant)
        ]
    }()

    private var hotkeyRow: some View {
        VStack(spacing: AppDesign.Spacing.sm) {
            settingsRow {
                Text("Global shortcut")
                Spacer()
                Toggle("", isOn: $hotkeyEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .onChange(of: hotkeyEnabled) { _, enabled in
                        if enabled {
                            let combo = HotkeyCombo.load()
                            GlobalHotkey.register(combo: combo) {
                                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                                    appDelegate.calendarStatusItem.statusItemClicked()
                                }
                            }
                        } else {
                            GlobalHotkey.unregister()
                        }
                        UserDefaults.standard.set(enabled, forKey: "hotkeyEnabled")
                    }
            }

            if hotkeyEnabled {
                Button {
                    if isRecordingHotkey {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Text(isRecordingHotkey ? "Press shortcut..." : GlobalHotkey.currentCombo.displayString)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(
                            isRecordingHotkey
                                ? Color.accentColor
                                : Color.primary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppDesign.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                                .fill(isRecordingHotkey
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.secondary.opacity(0.12)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                                .strokeBorder(
                                    isRecordingHotkey ? Color.accentColor : Color.clear,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)

                if let conflict = hotkeyConflict {
                    Text(conflict)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: .calendarPanelWillHide)) { _ in
            stopRecording()
        }
    }

    private func startRecording() {
        guard !isRecordingHotkey,
              let panel = NSApplication.shared.keyWindow as? NSPanel,
              panel.isVisible else { return }
        isRecordingHotkey = true
        hotkeyConflict = nil
        NotificationCenter.default.post(name: .hotkeyRecordingDidChange, object: true)
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard let panel, panel.isVisible,
                  NSApplication.shared.keyWindow === panel,
                  event.window === panel else { return event }
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !modifiers.isEmpty else { return event }

            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }

            let combo = HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonMods)

            if Self.reservedShortcuts.contains(combo) {
                hotkeyConflict = "\(combo.displayString) is a system shortcut"
                return nil
            }
            hotkeyConflict = nil
            combo.save()

            GlobalHotkey.register(combo: combo) {
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.calendarStatusItem.statusItemClicked()
                }
            }

            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        let wasRecording = isRecordingHotkey
        isRecordingHotkey = false
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
        if wasRecording {
            NotificationCenter.default.post(name: .hotkeyRecordingDidChange, object: false)
        }
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
