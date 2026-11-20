import AppKit
import Observation
import SwiftUI

/// How the user last drove the app. Focus rings follow it, like the web's `:focus-visible`:
/// keyboard use shows them, a pointer click never leaves one behind.
enum InputModality: Equatable, Sendable {
    case keyboard, pointer

    /// The modality an event of [type] signals, or nil when it says nothing (key-up, modifier
    /// changes, mouse-up/drag/move): those must not flip the current modality.
    init?(eventType type: NSEvent.EventType) {
        switch type {
        case .keyDown: self = .keyboard
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel: self = .pointer
        default: return nil
        }
    }

    static let monitoredEvents: NSEvent.EventTypeMask = [
        .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
    ]
}

/// App-wide input-modality state, observable by SwiftUI. Changes only on a real modality flip,
/// so repeated keys or clicks never invalidate views.
@MainActor @Observable
final class InputModalityTracker {
    nonisolated static let shared = InputModalityTracker()

    /// Pointer until the first key press: nothing shows a ring before keyboard use.
    private(set) var modality: InputModality = .pointer
    @ObservationIgnored private var monitor: Any?

    nonisolated init() {}

    var showsFocusRing: Bool { modality == .keyboard }
    var isMonitoring: Bool { monitor != nil }

    func note(_ modality: InputModality) {
        guard self.modality != modality else { return }
        self.modality = modality
    }

    func record(_ type: NSEvent.EventType) {
        if let modality = InputModality(eventType: type) { note(modality) }
    }

    /// Installs one passive local monitor for the tracker's lifetime (the tracker retains it).
    /// Local monitors run newest-first, so monitors that consume events (the calendar's key and
    /// scroll monitors, the shortcut recorder) must also call `note(_:)` themselves.
    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: InputModality.monitoredEvents) { [weak self] event in
            self?.record(event.type)
            return event
        }
    }

    func stopMonitoring() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

extension EnvironmentValues {
    @Entry var inputModality: InputModalityTracker = .shared
}
