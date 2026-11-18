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

    var body: some View {
        // The page has no window footer: version and About live in its last section.
        ScrollView(.vertical) {
            PreferencesView(
                store: store, hotkeyPreferences: hotkeyPreferences,
                notificationCenter: notificationCenter,
                onAISettingsChange: onAISettingsChange,
                calendarActions: calendarActions,
                openAbout: about,
                recordingWindow: recordingWindow
            )
            .padding(AppDesign.Settings.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppDesign.Colors.settingsSurface(in: environment))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
