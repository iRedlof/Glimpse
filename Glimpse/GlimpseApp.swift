import AppKit
import GlimpseCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let calendarStatusItem: CalendarStatusItem
    private let showCommand: CalendarShowCommand

    override init() {
        calendarStatusItem = CalendarStatusItem()
        showCommand = .shared
        super.init()
    }

    init(calendarStatusItem: CalendarStatusItem, showCommand: CalendarShowCommand) {
        self.calendarStatusItem = calendarStatusItem
        self.showCommand = showCommand
        super.init()
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
    }
}
