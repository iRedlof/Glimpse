import AppKit
import ComposableArchitecture
import GlimpseCore
import SwiftUI

struct SettingsRootView: View {
    @Environment(\.self) private var environment
    let store: StoreOf<PreferencesFeature>
    let hotkeyPreferences: HotkeyPreferencesModel
    let notificationCenter: NotificationCenter
    let onAISettingsChange: (@MainActor (Bool, AIProvider) -> Void)?
    let recordingWindow: @MainActor () -> NSWindow?
    let calendarActions: SettingsCalendarActions
    let about: @MainActor () -> Void
    let openCalendar: @MainActor () -> Void
    let requestQuit: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                PreferencesView(
                    store: store, hotkeyPreferences: hotkeyPreferences,
                    notificationCenter: notificationCenter,
                    onAISettingsChange: onAISettingsChange,
                    calendarActions: calendarActions,
                    recordingWindow: recordingWindow
                )
                .padding(AppDesign.Settings.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: AppDesign.Settings.linkSpacing) {
                Button("About", action: about)
                    .accessibilityLabel("About Glimpse")
                Button("Open Calendar", action: openCalendar)
                    .accessibilityLabel("Open Calendar app")
                Button("Quit", action: requestQuit)
                    .accessibilityLabel("Quit Glimpse")
                    .accessibilityHint("Shows confirmation before quitting")
                Spacer(minLength: AppDesign.Spacing.sm)
                Text("Glimpse \(appVersion)")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.link)
            .font(.system(size: AppDesign.Settings.supportingFontSize))
            .controlSize(.small)
            .padding(.horizontal, AppDesign.Settings.contentInset)
            .padding(.vertical, AppDesign.Spacing.sm)
        }
        .background(AppDesign.Colors.settingsSurface(in: environment))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
