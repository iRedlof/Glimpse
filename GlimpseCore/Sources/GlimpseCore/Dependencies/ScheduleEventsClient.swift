import ComposableArchitecture
import Foundation

extension Notification.Name {
    /// Posted on the main thread after EventKit confirms a Type to Schedule save.
    public static let scheduleEventSaved = Notification.Name("scheduleEventSaved")
}

/// Tells the app that a picked time was saved, so it can close the AI editor
/// (then ⌘Z means Undo, not text undo). The reducer reports the outcome; the
/// app owns the editor, which lives outside TCA state.
@DependencyClient
public struct ScheduleEventsClient: Sendable {
    public var eventSaved: @Sendable (SavedEvent) async -> Void
}

extension ScheduleEventsClient: DependencyKey {
    public static var liveValue: Self {
        Self(eventSaved: { _ in
            await MainActor.run {
                NotificationCenter.default.post(name: .scheduleEventSaved, object: nil)
            }
        })
    }

    public static let testValue = Self()
}

extension DependencyValues {
    public var scheduleEvents: ScheduleEventsClient {
        get { self[ScheduleEventsClient.self] }
        set { self[ScheduleEventsClient.self] = newValue }
    }
}
