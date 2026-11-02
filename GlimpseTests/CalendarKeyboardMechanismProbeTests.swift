import AppKit
import SwiftUI
import Testing

/// Opt-in native characterization. Failures are prototype limits, not product gates.
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["GLIMPSE_KEYBOARD_MECHANISM_PROBE"] == "1")
)
@MainActor
struct CalendarKeyboardMechanismProbeTests {
    @Test
    func nativeRovingDateFocusAndActivation() async throws {
        let fixture = KeyboardMechanismFixture()
        defer { fixture.close() }
        await fixture.settle()
        fixture.panel.makeKey()
        await fixture.settle()
        fixture.record("opened")
        #expect(fixture.panel.isKeyWindow, "Owned panel must actually become key")

        await fixture.focus(.before)
        fixture.expectNativeFocus(.before)
        try await fixture.send(.tab)
        fixture.expectNativeFocus(.dateOne)
        try await fixture.send(.tab)
        fixture.expectNativeFocus(.after)
        try await fixture.send(.backTab)
        fixture.expectNativeFocus(.dateOne)
        try await fixture.send(.backTab)
        fixture.expectNativeFocus(.before)
        #expect(fixture.model.actions.isEmpty, "Tab must not activate a control")

        await fixture.focus(.dateOne)
        fixture.expectNativeFocus(.dateOne)
        fixture.model.anchor = .dateTwo
        await fixture.focus(.dateTwo)
        fixture.expectNativeFocus(.dateTwo)
        try await fixture.send(.tab)
        fixture.expectNativeFocus(.after)
        try await fixture.send(.backTab)
        fixture.expectNativeFocus(.dateTwo)
        try await fixture.send(.backTab)
        fixture.expectNativeFocus(.before)
        #expect(fixture.model.actions.isEmpty, "Anchor transfer must not select a date")

        for key in [ProbeKey.returnKey, .keypadEnter, .space] {
            await fixture.focus(.dateTwo)
            fixture.expectNativeFocus(.dateTwo)
            let start = fixture.model.actions.count
            try await fixture.send(key)
            let delivered = Array(fixture.model.actions.dropFirst(start))
            #expect(delivered == [.dateTwo],
                    "\(key.rawValue) must activate the focused native date exactly once")
            fixture.record("activation-result-\(key.rawValue)", actions: delivered)
        }
    }

    @Test
    func anchorActivationAndReverseDispatch() async throws {
        let fixture = KeyboardMechanismFixture()
        defer { fixture.close() }
        await fixture.settle()
        fixture.panel.makeKey()
        await fixture.settle()
        fixture.record("phase2-opened")
        try #require(fixture.panel.isKeyWindow)

        await fixture.focus(.dateOne)
        fixture.expectNativeFocus(.dateOne)
        fixture.model.anchor = .dateTwo
        fixture.model.requestedFocus = .dateTwo
        await fixture.settle(until: { fixture.model.actualFocus == .dateTwo })
        fixture.record("phase2-anchor-before-any-tab")
        #expect(fixture.model.actions.isEmpty)
        try await fixture.send(.space)
        fixture.record("phase2-immediate-anchor-space-result")
        #expect(fixture.model.actions == [.dateTwo],
                "The newly eligible date must activate before any Tab reacquisition")

        try await fixture.send(.tab)
        fixture.expectNativeFocus(.after)
        for dispatch in ProbeDispatch.allCases {
            await fixture.focus(.after)
            fixture.expectNativeFocus(.after)
            try await fixture.send(.backTab, dispatch: dispatch)
            fixture.expectNativeFocus(.dateTwo)
            fixture.record("phase2-swiftui-\(dispatch.rawValue)-reverse-first")
            try await fixture.send(.backTab, dispatch: dispatch)
            fixture.expectNativeFocus(.before)
            fixture.record("phase2-swiftui-\(dispatch.rawValue)-reverse-second")
        }

        fixture.installAppKitBaseline()
        await fixture.settle()
        for dispatch in ProbeDispatch.allCases {
            for key in [ProbeKey.tab, .backTab] {
                try fixture.focusBaselineMiddle()
                fixture.record("phase2-appkit-\(dispatch.rawValue)-\(key.rawValue)-before")
                try await fixture.send(key, dispatch: dispatch)
                let expected = key == .tab ? "baseline-after" : "baseline-before"
                #expect(fixture.baselineResponderLabel == expected,
                        "Native AppKit \(dispatch.rawValue) \(key.rawValue) must reach \(expected)")
                fixture.record("phase2-appkit-\(dispatch.rawValue)-\(key.rawValue)-result")
            }
        }
    }
}

private enum ProbeDispatch: String, CaseIterable {
    case window, application
}

private enum ProbeTarget: String, Hashable {
    case before, dateOne, dateTwo, dateThree, after
}

private enum ProbeKey: String {
    case tab, backTab, returnKey, keypadEnter, space

    var keyCode: UInt16 {
        switch self {
        case .tab, .backTab: 48
        case .returnKey: 36
        case .keypadEnter: 76
        case .space: 49
        }
    }

    var characters: String {
        switch self {
        case .tab: "\t"
        case .backTab: "\u{19}"
        case .returnKey: "\r"
        case .keypadEnter: "\u{3}"
        case .space: " "
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .backTab: [.shift]
        case .keypadEnter: [.numericPad]
        default: []
        }
    }

    var charactersIgnoringModifiers: String {
        self == .backTab ? "\t" : characters
    }
}

@MainActor
private final class KeyboardProbeModel: ObservableObject {
    @Published var anchor: ProbeTarget = .dateOne
    @Published var requestedFocus: ProbeTarget?
    var actualFocus: ProbeTarget?
    var actions: [ProbeTarget] = []
}

private struct KeyboardProbeView: View {
    @ObservedObject var model: KeyboardProbeModel
    @FocusState private var focus: ProbeTarget?

    var body: some View {
        VStack(spacing: 12) {
            control(.before, label: "Before dates", eligible: true)
            HStack(spacing: 12) {
                control(.dateOne, label: "Synthetic date 1", eligible: model.anchor == .dateOne)
                control(.dateTwo, label: "Synthetic date 2", eligible: model.anchor == .dateTwo)
                control(.dateThree, label: "Synthetic date 3", eligible: model.anchor == .dateThree)
            }
            control(.after, label: "After dates", eligible: true)
        }
        .padding(20)
        .onChange(of: model.requestedFocus) { _, target in focus = target }
        .onChange(of: focus) { _, target in model.actualFocus = target }
    }

    @ViewBuilder
    private func control(_ target: ProbeTarget, label: String, eligible: Bool) -> some View {
        let button = Button(label) { model.actions.append(target) }.buttonStyle(.plain)
        if eligible {
            button.focused($focus, equals: target)
        } else {
            button.focusable(false).focused($focus, equals: target)
        }
    }
}

@MainActor
private final class KeyboardProbePanel: NSPanel {
    var syntheticEvent: NSEvent?
    var syntheticDispatch: ProbeDispatch?
    var syntheticDeliveryCount = 0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if let expected = syntheticEvent {
            syntheticDeliveryCount += 1
            #expect(event === expected, "Only the designated owned synthetic event may be dispatched")
            #expect(event.window === self)
            #expect(isKeyWindow)
            #expect(responderIsOwned(firstResponder, by: self))
            let receipt: [String: Any] = [
                "dispatch": syntheticDispatch?.rawValue ?? "nil",
                "eventType": event.type.rawValue,
                "keyCode": event.keyCode,
                "characters": event.characters ?? "",
                "charactersIgnoringModifiers": event.charactersIgnoringModifiers ?? "",
                "modifierFlags": event.modifierFlags.rawValue,
                "eventWindowOwned": event.window === self,
                "applicationKeyWindowOwned": NSApp.keyWindow === self,
                "firstResponderIdentity": firstResponder.map {
                    String(describing: ObjectIdentifier($0))
                } ?? "nil",
                "firstResponderOwned": responderIsOwned(firstResponder, by: self),
                // Never copy metadata from an unrelated current event.
                "applicationCurrentEventMatchesSent": NSApp.currentEvent === event,
                "applicationCurrentEventOwned": NSApp.currentEvent?.window === self,
                "windowCurrentEventMatchesSent": currentEvent === event,
                "windowCurrentEventOwned": currentEvent?.window === self,
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                print("GLIMPSE_KEYBOARD_DISPATCH \(String(decoding: data, as: UTF8.self))")
            } catch {
                Issue.record("Could not encode owned dispatch receipt: \(error)")
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
private func responderIsOwned(_ responder: NSResponder?, by window: NSWindow) -> Bool {
    guard let responder else { return false }
    if let view = responder as? NSView { return view.window === window }
    var cursor: NSResponder? = responder
    var visited: Set<ObjectIdentifier> = []
    while let current = cursor, visited.insert(ObjectIdentifier(current)).inserted {
        if current === window { return true }
        cursor = current.nextResponder
    }
    return false
}

@MainActor
private final class KeyboardMechanismFixture {
    let panel: KeyboardProbePanel
    let hosting: NSHostingView<AnyView>
    let model = KeyboardProbeModel()
    private var baselineControls: [NSButton] = []
    private var contentMode = "swiftUI"
    private var sequence = 0

    init() {
        panel = KeyboardProbePanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 180),
            styleMask: [.nonactivatingPanel, .titled], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        hosting = NSHostingView(rootView: AnyView(KeyboardProbeView(model: model)))
        panel.contentView = hosting
        let screens = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        panel.setFrameOrigin(NSPoint(
            x: screens.minX - panel.frame.width - 100,
            y: screens.minY - panel.frame.height - 100
        ))
        panel.orderBack(nil)
    }

    func focus(_ target: ProbeTarget) async {
        // Reset the request so a repeated request is observable by SwiftUI.
        model.requestedFocus = nil
        await settle()
        model.requestedFocus = target
        await settle(until: { self.model.actualFocus == target })
        record("requested-\(target.rawValue)")
    }

    func expectNativeFocus(_ target: ProbeTarget) {
        record("expected-\(target.rawValue)")
        #expect(model.actualFocus == target, "Actual FocusState must equal \(target.rawValue)")
        #expect(panel.firstResponder !== panel, "The window itself is not focused date evidence")
        #expect(firstResponderIsOwned, "Actual firstResponder must belong to the owned panel")
    }

    func send(_ key: ProbeKey, dispatch: ProbeDispatch = .window) async throws {
        try #require(panel.isKeyWindow)
        try #require(firstResponderIsOwned)
        if dispatch == .application {
            try #require(ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil,
                         "Application dispatch is restricted to the isolated test host")
            try #require(NSApp.keyWindow === panel)
        }
        record("before-key-\(key.rawValue)-\(dispatch.rawValue)")
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: key.modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil,
                characters: key.characters,
                charactersIgnoringModifiers: key.charactersIgnoringModifiers,
                isARepeat: false, keyCode: key.keyCode
            ))
            try #require(event.window === panel)
            let deliveries = panel.syntheticDeliveryCount
            panel.syntheticEvent = event
            panel.syntheticDispatch = dispatch
            switch dispatch {
            case .window: panel.sendEvent(event)
            case .application: NSApp.sendEvent(event)
            }
            #expect(panel.syntheticDeliveryCount == deliveries + 1,
                    "Each event must arrive once at the owned panel")
            panel.syntheticEvent = nil
            panel.syntheticDispatch = nil
            #expect(firstResponderIsOwned)
        }
        await settle()
        record("after-key-\(key.rawValue)-\(dispatch.rawValue)")
    }

    func installAppKitBaseline() {
        model.requestedFocus = nil
        hosting.rootView = AnyView(EmptyView())
        #expect(panel.makeFirstResponder(nil))
        contentMode = "appKit"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        baselineControls = ["baseline-before", "baseline-middle", "baseline-after"].enumerated().map {
            index, name in
            let button = NSButton(title: name, target: nil, action: nil)
            button.identifier = NSUserInterfaceItemIdentifier(name)
            button.frame = NSRect(x: 20, y: 120 - CGFloat(index) * 40, width: 200, height: 30)
            container.addSubview(button)
            return button
        }
        panel.contentView = container
        panel.autorecalculatesKeyViewLoop = false
        baselineControls[0].nextKeyView = baselineControls[1]
        baselineControls[1].nextKeyView = baselineControls[2]
        baselineControls[2].nextKeyView = baselineControls[0]
        panel.initialFirstResponder = baselineControls[1]
    }

    var baselineResponderLabel: String {
        (panel.firstResponder as? NSView)?.identifier?.rawValue ?? "unidentified"
    }

    func focusBaselineMiddle() throws {
        let middle = try #require(baselineControls.first {
            $0.identifier?.rawValue == "baseline-middle"
        })
        try #require(panel.makeFirstResponder(middle))
        try #require(panel.firstResponder === middle)
        try #require(middle.window === panel)
    }

    func settle(until ready: () -> Bool = { true }) async {
        // Finite layout warm-up, then a bounded observation budget; no focus timers.
        for _ in 0..<8 { await layoutPass() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !ready(), ContinuousClock.now < deadline { await layoutPass() }
    }

    private func layoutPass() async {
        if contentMode == "swiftUI" { _ = hosting.fittingSize }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
        pumpOwnedRunLoop()
        await Task.yield()
    }

    private func pumpOwnedRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    private var firstResponderIsOwned: Bool {
        responderIsOwned(panel.firstResponder, by: panel)
    }

    func record(_ stage: String, actions: [ProbeTarget]? = nil) {
        sequence += 1
        let responder = panel.firstResponder
        let receipt: [String: Any] = [
            "sequence": sequence, "stage": stage,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "keyboardNavigationEnabled": NSApp.isFullKeyboardAccessEnabled,
            "applicationActive": NSApp.isActive,
            "keyWindow": panel.isKeyWindow,
            "visible": panel.isVisible,
            "windowNumber": panel.windowNumber,
            "contentMode": contentMode,
            "focusStateApplicable": contentMode == "swiftUI",
            "firstResponderLabel": baselineResponderLabel,
            "anchor": model.anchor.rawValue,
            "requestedFocus": model.requestedFocus?.rawValue ?? "nil",
            "actualFocusState": model.actualFocus?.rawValue ?? "nil",
            "firstResponderType": responder.map { String(describing: type(of: $0)) } ?? "nil",
            "firstResponderIdentity": responder.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
            "firstResponderOwned": firstResponderIsOwned,
            "firstResponderIsWindow": responder === panel,
            "actions": (actions ?? model.actions).map(\.rawValue),
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
            print("GLIMPSE_KEYBOARD_PROBE \(String(decoding: data, as: UTF8.self))")
        } catch {
            Issue.record("Could not encode native mechanism receipt: \(error)")
        }
    }

    func close() {
        panel.syntheticEvent = nil
        panel.syntheticDispatch = nil
        model.requestedFocus = nil
        hosting.rootView = AnyView(EmptyView())
        #expect(panel.makeFirstResponder(nil))
        panel.initialFirstResponder = nil
        panel.contentView = nil
        baselineControls = []
        contentMode = "closed"
        panel.orderOut(nil)
        panel.close()
        record("closed")
        #expect(!panel.isVisible)
        #expect(!panel.isKeyWindow)
        #expect(panel.firstResponder == nil || panel.firstResponder === panel)
    }
}
