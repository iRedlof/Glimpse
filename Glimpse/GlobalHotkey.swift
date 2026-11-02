import AppKit
import Carbon
import Observation

struct HotkeyCombo: Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    static let `default` = HotkeyCombo(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey))

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: "hotkeyKeyCode")
        defaults.set(Int(modifiers), forKey: "hotkeyModifiers")
    }

    static func load(defaults: UserDefaults = .standard) -> HotkeyCombo {
        if defaults.object(forKey: "hotkeyKeyCode") != nil {
            let code = defaults.integer(forKey: "hotkeyKeyCode")
            let mods = defaults.integer(forKey: "hotkeyModifiers")
            let allowedModifiers = UInt32(cmdKey | shiftKey | optionKey | controlKey)
            guard (0...127).contains(code),
                  let keyCode = UInt32(exactly: code),
                  let modifiers = UInt32(exactly: mods),
                  modifiers != 0, modifiers & ~allowedModifiers == 0 else {
                AppLogger.preferences.error("Invalid saved hotkey; using default")
                return .default
            }
            return HotkeyCombo(keyCode: keyCode, modifiers: modifiers)
        }
        return .default
    }

    private func keyName(for code: UInt32) -> String {
        let mapping: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
        ]
        return mapping[code] ?? "Key\(code)"
    }
}

struct HotkeyEventID: Equatable, Sendable {
    static let glimpseSignature: UInt32 = 0x474C4D50
    let signature: UInt32
    let id: UInt32
}

struct HotkeyNativeResult<Reference> {
    let status: OSStatus
    let reference: Reference?
}

enum HotkeyRegistrationError: Error, Equatable, Sendable {
    case conflict
    case registrationFailed(OSStatus)
    case handlerInstallationFailed(OSStatus)
    case missingHotkeyReference
    case missingHandlerReference
    case replacementRetirementFailed(OSStatus)
    case unregisterFailed(OSStatus)
    case handlerRemovalFailed(OSStatus)
    case cleanupFailed(OSStatus)

    func message(isRegistered: Bool) -> String {
        switch self {
        case .conflict:
            return "That shortcut is already in use. Choose another combination."
                + (isRegistered ? " Your previous shortcut still works." : "")
        case .registrationFailed, .missingHotkeyReference,
             .handlerInstallationFailed, .missingHandlerReference,
             .replacementRetirementFailed:
            return isRegistered
                ? "Glimpse couldn’t use that shortcut. Try another combination. Your previous shortcut still works."
                : "Glimpse couldn’t enable this shortcut. Try again or choose another combination."
        case .unregisterFailed where isRegistered:
            return "Glimpse couldn’t turn off this shortcut. Try again."
        case .unregisterFailed, .handlerRemovalFailed, .cleanupFailed:
            return "Glimpse couldn’t confirm the shortcut’s status. Try again."
        }
    }
}

@MainActor
protocol HotkeyBackend: AnyObject {
    func register(combo: HotkeyCombo, id: HotkeyEventID) -> HotkeyNativeResult<EventHotKeyRef>
    func installHandler(_ receive: @escaping (HotkeyEventID) -> Void) -> HotkeyNativeResult<EventHandlerRef>
    func unregister(_ reference: EventHotKeyRef) -> OSStatus
    func removeHandler(_ reference: EventHandlerRef) -> OSStatus
}

@MainActor
final class CarbonHotkeyBackend: HotkeyBackend {
    private var receive: ((HotkeyEventID) -> Void)?

    func register(combo: HotkeyCombo, id: HotkeyEventID) -> HotkeyNativeResult<EventHotKeyRef> {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers,
            EventHotKeyID(signature: id.signature, id: id.id),
            GetApplicationEventTarget(), 0, &reference
        )
        return .init(status: status, reference: reference)
    }

    func installHandler(_ receive: @escaping (HotkeyEventID) -> Void) -> HotkeyNativeResult<EventHandlerRef> {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        var reference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var nativeID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &nativeID
                )
                guard status == noErr, nativeID.signature == HotkeyEventID.glimpseSignature else {
                    return OSStatus(eventNotHandledErr)
                }
                let backend = Unmanaged<CarbonHotkeyBackend>.fromOpaque(context).takeUnretainedValue()
                let id = HotkeyEventID(signature: nativeID.signature, id: nativeID.id)
                Task { @MainActor [weak backend] in backend?.receive?(id) }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &reference
        )
        if status == noErr, reference != nil { self.receive = receive }
        return .init(status: status, reference: reference)
    }

    func unregister(_ reference: EventHotKeyRef) -> OSStatus { UnregisterEventHotKey(reference) }

    func removeHandler(_ reference: EventHandlerRef) -> OSStatus {
        let status = RemoveEventHandler(reference)
        if status == noErr { receive = nil }
        return status
    }
}

struct HotkeyDiagnosticSnapshot: Sendable {
    var requested: Bool
    var registered: Bool
    var savedCombo: HotkeyCombo
    var activeCombo: HotkeyCombo?
    var error: HotkeyRegistrationError?
}

@MainActor
@Observable
final class GlobalHotkey {
    static let shared = GlobalHotkey(backend: CarbonHotkeyBackend(), defaults: .standard)

    private struct Registration {
        let reference: EventHotKeyRef
        let id: HotkeyEventID
        let combo: HotkeyCombo
        var handler: () -> Void
    }

    private let backend: any HotkeyBackend
    private let defaults: UserDefaults
    private var accepted: Registration?
    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private var pendingKeys: [EventHotKeyRef] = []
    @ObservationIgnored private var pendingHandlers: [EventHandlerRef] = []
    @ObservationIgnored private var nextID: UInt32 = 0
    private(set) var currentCombo: HotkeyCombo
    private(set) var lastError: HotkeyRegistrationError?

    var isRegistered: Bool { accepted != nil && eventHandler != nil }

    init(backend: any HotkeyBackend, defaults: UserDefaults) {
        self.backend = backend
        self.defaults = defaults
        currentCombo = .load(defaults: defaults)
    }

    @discardableResult
    func register(combo: HotkeyCombo, handler: @escaping () -> Void) -> Result<Void, HotkeyRegistrationError> {
        if let error = cleanupPending() { return fail(error) }
        if accepted?.combo == combo, isRegistered {
            accepted?.handler = handler
            lastError = nil
            return .success(())
        }
        let installedHandler = eventHandler == nil
        if let error = ensureHandler() { return fail(error) }
        let id = nextEventID()
        let candidate = backend.register(combo: combo, id: id)
        guard candidate.status == noErr, let reference = candidate.reference else {
            return rejectCandidate(candidate, installedHandler: installedHandler)
        }
        if let accepted {
            let status = backend.unregister(accepted.reference)
            guard status == noErr else {
                pendingKeys.append(reference)
                return fail(cleanupPending() ?? .replacementRetirementFailed(status))
            }
        }
        // This is the commit point: native ownership is complete before persistence.
        accepted = Registration(reference: reference, id: id, combo: combo, handler: handler)
        currentCombo = combo
        combo.save(defaults: defaults)
        lastError = nil
        AppLogger.general.info("Global hotkey registered: \(combo.displayString)")
        return .success(())
    }

    @discardableResult
    func unregister() -> Result<Void, HotkeyRegistrationError> {
        if let error = cleanupPending() { return fail(error) }
        if let accepted {
            let status = backend.unregister(accepted.reference)
            guard status == noErr else { return fail(.unregisterFailed(status)) }
            self.accepted = nil
        }
        if let error = releaseInactiveHandler() { return fail(error) }
        lastError = nil
        return .success(())
    }

    func snapshot() -> HotkeyDiagnosticSnapshot {
        .init(
            requested: defaults.object(forKey: "hotkeyEnabled") == nil
                || defaults.bool(forKey: "hotkeyEnabled"),
            registered: isRegistered, savedCombo: .load(defaults: defaults),
            activeCombo: isRegistered ? currentCombo : nil, error: lastError
        )
    }

    private func ensureHandler() -> HotkeyRegistrationError? {
        guard eventHandler == nil else { return nil }
        let result = backend.installHandler { [weak self] id in self?.receive(id) }
        guard result.status == noErr, let reference = result.reference else {
            if let reference = result.reference { pendingHandlers.append(reference) }
            return cleanupPending() ?? (result.status == noErr
                ? .missingHandlerReference : .handlerInstallationFailed(result.status))
        }
        eventHandler = reference
        return nil
    }

    private func rejectCandidate(
        _ candidate: HotkeyNativeResult<EventHotKeyRef>, installedHandler: Bool
    ) -> Result<Void, HotkeyRegistrationError> {
        if let reference = candidate.reference { pendingKeys.append(reference) }
        let cleanupError = cleanupPending()
        let handlerError = installedHandler ? releaseInactiveHandler() : nil
        let nativeError: HotkeyRegistrationError = candidate.status == noErr
            ? .missingHotkeyReference : (candidate.status == eventHotKeyExistsErr
                ? .conflict : .registrationFailed(candidate.status))
        return fail(cleanupError ?? handlerError ?? nativeError)
    }

    private func cleanupPending() -> HotkeyRegistrationError? {
        while let reference = pendingKeys.first {
            let status = backend.unregister(reference)
            guard status == noErr else { return .cleanupFailed(status) }
            pendingKeys.removeFirst()
        }
        while let reference = pendingHandlers.first {
            let status = backend.removeHandler(reference)
            guard status == noErr else { return .cleanupFailed(status) }
            pendingHandlers.removeFirst()
        }
        return nil
    }

    private func releaseInactiveHandler() -> HotkeyRegistrationError? {
        guard accepted == nil, let reference = eventHandler else { return nil }
        let status = backend.removeHandler(reference)
        eventHandler = nil
        guard status == noErr else {
            pendingHandlers.append(reference)
            return .handlerRemovalFailed(status)
        }
        return nil
    }

    private func nextEventID() -> HotkeyEventID {
        // Zero is unused; wrapping avoids an arithmetic trap after UInt32.max edits.
        nextID &+= 1
        if nextID == 0 { nextID = 1 }
        return .init(signature: HotkeyEventID.glimpseSignature, id: nextID)
    }

    private func receive(_ id: HotkeyEventID) {
        // Check after the native callback's main-actor hop, including queued events.
        guard isRegistered, let accepted, accepted.id == id else { return }
        accepted.handler()
    }

    private func fail(_ error: HotkeyRegistrationError) -> Result<Void, HotkeyRegistrationError> {
        lastError = error
        AppLogger.general.error("Global shortcut change failed: \(String(describing: error), privacy: .public)")
        return .failure(error)
    }
}
