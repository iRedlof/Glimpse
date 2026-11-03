import AppKit
import ComposableArchitecture
import GlimpseCore
import SwiftUI

struct SettingsRootView: View {
    let store: StoreOf<PreferencesFeature>
    let hotkeyPreferences: HotkeyPreferencesModel
    @Bindable var selection: SettingsSelection
    let notificationCenter: NotificationCenter
    let onAISettingsChange: (@MainActor (Bool, AIProvider) -> Void)?
    let selectSection: @MainActor (SettingsSection) -> Void
    let recordingWindow: @MainActor () -> NSWindow?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selectSection(section)
                    } label: {
                        Text(section.title)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppDesign.Settings.windowGap)
                            .padding(.vertical, AppDesign.Spacing.sm)
                            .background(
                                selection.section == section
                                    ? Color.accentColor.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: AppDesign.CornerRadius.md)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.title)
                    .onKeyPress(.return, phases: [.down, .repeat]) { press in
                        guard press.modifiers.intersection([.command, .shift, .option, .control]).isEmpty,
                              let owner = recordingWindow(), owner.isVisible,
                              NSApp.keyWindow === owner, NSApp.currentEvent?.window === owner else {
                            return .ignored
                        }
                        if press.phase == .down { selectSection(section) }
                        return .handled
                    }
                    .accessibilityAddTraits(selection.section == section ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(AppDesign.Settings.windowGap)
            .frame(width: AppDesign.Settings.sidebarWidth)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                    Text(selection.section.heading)
                        .font(.system(size: 17, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    PreferencesView(
                        store: store, hotkeyPreferences: hotkeyPreferences,
                        notificationCenter: notificationCenter,
                        onAISettingsChange: onAISettingsChange,
                        section: selection.section,
                        recordingWindow: recordingWindow
                    )
                }
                .padding(AppDesign.Settings.detailInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
