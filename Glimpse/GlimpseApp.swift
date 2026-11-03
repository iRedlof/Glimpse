import AppKit
import GlimpseCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let calendarStatusItem: CalendarStatusItem
    private let showCommand: CalendarShowCommand
    private var settingsController: SettingsWindowController?

    override init() {
        calendarStatusItem = CalendarStatusItem()
        showCommand = .shared
        super.init()
        connectSettingsEntry()
    }

    init(calendarStatusItem: CalendarStatusItem, showCommand: CalendarShowCommand,
         settingsController: SettingsWindowController? = nil) {
        self.calendarStatusItem = calendarStatusItem
        self.showCommand = showCommand
        self.settingsController = settingsController
        super.init()
        connectSettingsEntry()
    }

    private func connectSettingsEntry() {
        calendarStatusItem.requestSettings = { [weak self] in self?.showSettings() }
    }

    func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                onAISettingsChange: { [weak calendarStatusItem] enabled, preference in
                    calendarStatusItem?.synchronizeAISettings(enabled: enabled, preference: preference)
                }
            )
        }
        let placement = calendarStatusItem.prepareForSettingsPresentation()
        settingsController?.show(visibleFrame: placement.visibleFrame, avoiding: placement.avoiding)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        calendarStatusItem.setup()
        showCommand.register { [weak calendarStatusItem] in
            guard let calendarStatusItem else { throw CalendarShowError.notReady }
            try calendarStatusItem.showCalendar()
        }
        _ = SparkleUpdater.shared
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        // About-window visibility is independent of the reusable calendar panel.
        do {
            try showCommand.requestShow()
        } catch {
            AppLogger.statusItem.error("Cannot reopen calendar: \(error.localizedDescription, privacy: .public)")
        }
        return false
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
}

@main
struct GlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
