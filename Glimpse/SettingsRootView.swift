import AppKit
import ComposableArchitecture
import GlimpseCore
import SwiftUI

struct SettingsRootView: View {
    let store: StoreOf<PreferencesFeature>
    let hotkeyPreferences: HotkeyPreferencesModel
    let notificationCenter: NotificationCenter
    let onAISettingsChange: (@MainActor (Bool, AIProvider) -> Void)?
    let recordingWindow: @MainActor () -> NSWindow?

    var body: some View {
        ScrollView(.vertical) {
            PreferencesView(
                store: store, hotkeyPreferences: hotkeyPreferences,
                notificationCenter: notificationCenter,
                onAISettingsChange: onAISettingsChange,
                recordingWindow: recordingWindow
            )
            .padding(AppDesign.Settings.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
