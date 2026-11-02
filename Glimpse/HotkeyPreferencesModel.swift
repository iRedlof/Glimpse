import AppKit
import Carbon
import Observation

struct HotkeyRecordingInput {
    var keyCode: UInt32
    var modifiers: UInt32
    var ownerIsVisible = true
    var ownerIsKey = true
    var eventIsForOwner = true
}

@MainActor
struct HotkeyRecordingClient {
    var install: (@escaping (HotkeyRecordingInput) -> Bool) -> Any?
    var remove: (Any) -> Void
    var didChange: (Bool) -> Void

    static func live(panel: NSPanel) -> Self {
        .init(
            install: { [weak panel] receive in
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
                    guard let panel else { return event }
                    let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                    var carbonModifiers: UInt32 = 0
                    if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
                    if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
                    if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
                    if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
                    let consumed = receive(.init(
                        keyCode: UInt32(event.keyCode), modifiers: carbonModifiers,
                        ownerIsVisible: panel.isVisible,
                        ownerIsKey: NSApplication.shared.keyWindow === panel,
                        eventIsForOwner: event.window === panel
                    ))
                    return consumed ? nil : event
                }
            },
            remove: { NSEvent.removeMonitor($0) },
            didChange: {
                NotificationCenter.default.post(name: .hotkeyRecordingDidChange, object: $0)
            }
        )
    }
}

enum HotkeyRecordingError: Equatable {
    case reserved(HotkeyCombo)
    case registration(HotkeyRegistrationError)
    case monitorUnavailable

    func message(isRegistered: Bool) -> String {
        switch self {
        case .reserved(let combo): "\(combo.displayString) is a reserved shortcut. Choose another combination."
        case .registration(let error): error.message(isRegistered: isRegistered)
        case .monitorUnavailable: "Glimpse couldn’t record a shortcut. Try again."
        }
    }
}

@MainActor
@Observable
final class HotkeyPreferencesModel {
    private let hotkey: GlobalHotkey
    private let defaults: UserDefaults
    private let handler: () -> Void
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var recordingClient: HotkeyRecordingClient?
    private(set) var isRecording = false
    private(set) var recordingError: HotkeyRecordingError?
    private(set) var isRequested: Bool

    var isEnabled: Bool { hotkey.isRegistered }
    var displayedCombo: HotkeyCombo { hotkey.currentCombo }
    var errorMessage: String? {
        recordingError?.message(isRegistered: isEnabled)
            ?? hotkey.lastError?.message(isRegistered: isEnabled)
    }

    init(hotkey: GlobalHotkey, defaults: UserDefaults, handler: @escaping () -> Void) {
        self.hotkey = hotkey
        self.defaults = defaults
        self.handler = handler
        isRequested = defaults.object(forKey: "hotkeyEnabled") == nil
            || defaults.bool(forKey: "hotkeyEnabled")
    }

    convenience init() {
        self.init(hotkey: .shared, defaults: .standard) {
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.calendarStatusItem.statusItemClicked()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        cancelRecording()
        if enabled {
            if case .success = hotkey.register(combo: displayedCombo, handler: handler) {
                defaults.set(true, forKey: "hotkeyEnabled")
                isRequested = true
            }
        } else {
            // Explicit off is user intent even if native cleanup must be retried.
            defaults.set(false, forKey: "hotkeyEnabled")
            isRequested = false
            hotkey.unregister()
        }
    }

    func beginRecording(using client: HotkeyRecordingClient) {
        guard !isRecording else { return }
        recordingError = nil
        guard let monitor = client.install({ [weak self] input in self?.handle(input) ?? false }) else {
            recordingError = .monitorUnavailable
            return
        }
        self.monitor = monitor
        recordingClient = client
        isRecording = true
        client.didChange(true)
    }

    func handle(_ input: HotkeyRecordingInput) -> Bool {
        guard isRecording, input.ownerIsVisible, input.ownerIsKey, input.eventIsForOwner else { return false }
        if input.keyCode == 53 {
            cancelRecording()
            return true
        }
        guard input.modifiers != 0 else { return false }
        let combo = HotkeyCombo(keyCode: input.keyCode, modifiers: input.modifiers)
        if Self.reservedShortcuts.contains(combo) {
            recordingError = .reserved(combo)
            return true
        }
        recordingError = nil
        switch hotkey.register(combo: combo, handler: handler) {
        case .success:
            defaults.set(true, forKey: "hotkeyEnabled")
            isRequested = true
            cancelRecording()
        case .failure(let error):
            recordingError = .registration(error)
        }
        return true
    }

    func cancelRecording() {
        let wasRecording = isRecording
        isRecording = false
        if let monitor { recordingClient?.remove(monitor) }
        monitor = nil
        if wasRecording { recordingClient?.didChange(false) }
        recordingClient = nil
        recordingError = nil
    }

    private static let reservedShortcuts: Set<HotkeyCombo> = {
        let command = UInt32(cmdKey)
        return Set([12, 13, 4, 46, 0, 8, 9, 7, 6, 49, 35, 1, 3, 17, 45, 31].map {
            HotkeyCombo(keyCode: UInt32($0), modifiers: command)
        }).union([HotkeyCombo(keyCode: 4, modifiers: UInt32(cmdKey | shiftKey))])
    }()
}
