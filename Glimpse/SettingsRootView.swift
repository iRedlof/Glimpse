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
    let updater: SparkleUpdater
    let diagnostics: DiagnosticsExportModel
    var inputModality: InputModalityTracker = .shared

    var body: some View {
        // The page has no window footer: updates and About are its last sections.
        ScrollView(.vertical) {
            PreferencesView(
                store: store, hotkeyPreferences: hotkeyPreferences,
                notificationCenter: notificationCenter,
                onAISettingsChange: onAISettingsChange,
                calendarActions: calendarActions,
                updater: updater, diagnostics: diagnostics,
                recordingWindow: recordingWindow
            )
            .padding(AppDesign.Settings.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppDesign.Colors.settingsSurface(in: environment))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Native controls keep focus, Tab order and Space/Return; only their rings are hidden
        // until the keyboard is used, so a gear-click open or a mouse click leaves no ring.
        .focusEffectDisabled(!inputModality.showsFocusRing)
        .environment(\.inputModality, inputModality)
    }
}
