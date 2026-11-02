import AppIntents
import Foundation

enum CalendarShowError: LocalizedError {
    case notReady
    case unavailableAnchor
    case invalidGeometry

    var errorDescription: String? {
        switch self {
        case .notReady:
            "Glimpse is still starting. Try Show Calendar again."
        case .unavailableAnchor, .invalidGeometry:
            "Couldn't open the calendar. Try again from Glimpse's menu-bar icon."
        }
    }
}

@MainActor
final class CalendarShowCommand {
    static let shared = CalendarShowCommand()
    private var target: (@MainActor () throws -> Void)?

    @discardableResult
    func register(
        _ target: (@MainActor () throws -> Void)?
    ) -> (@MainActor () throws -> Void)? {
        let previous = self.target
        self.target = target
        return previous
    }

    func requestShow() throws {
        guard let target else { throw CalendarShowError.notReady }
        try target()
    }
}

struct ShowCalendarIntent: AppIntent {
    // Safety: AppIntent static properties are initialized once and read-only after init.
    // nonisolated(unsafe) required because AppIntent protocol properties are mutable static vars.
    nonisolated(unsafe) static var title: LocalizedStringResource = "Show Glimpse Calendar"
    nonisolated(unsafe) static var description = IntentDescription("Opens the Glimpse calendar popover")
    nonisolated(unsafe) static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try CalendarShowCommand.shared.requestShow()
        return .result()
    }
}

struct GlimpseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowCalendarIntent(),
            phrases: [
                "Show \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Show Calendar",
            systemImageName: "calendar"
        )
    }
}
