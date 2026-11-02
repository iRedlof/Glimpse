import AppKit
import ApplicationServices
import SwiftUI
import Testing

/// SwiftUI exposes these public selectors without requiring protocol conformance.
@MainActor
struct AccessibilityTestNode {
    let object: AnyObject

    var role: NSAccessibility.Role? { object.accessibilityRole?() }
    var label: String? { object.accessibilityLabel?() }
    var value: Any? { object.accessibilityValue?() }
    var help: String? { object.accessibilityHelp?() }
    var frame: NSRect { object.accessibilityFrame?() ?? .zero }
    var enabled: Bool { object.isAccessibilityEnabled?() ?? false }
    var selected: Bool { object.isAccessibilitySelected?() ?? false }
    var children: [Any] { object.accessibilityChildren?() ?? [] }
    var contents: [Any] { object.accessibilityContents?() ?? [] }
    var visibleChildren: [Any] { object.accessibilityVisibleChildren?() ?? [] }

    @discardableResult
    func press() -> Bool { object.accessibilityPerformPress?() ?? false }
}

private enum AccessibilityHostError: Error {
    case timeout(String)
}

private final class AccessibilityFixtureWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// An owned, offscreen host: no global event delivery or assistive settings changes.
@MainActor
final class AccessibilityTestHost {
    let window: NSWindow
    let hosting: NSHostingView<AnyView>

    init<Content: View>(
        width: CGFloat, height: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        window = AccessibilityFixtureWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        hosting = NSHostingView(rootView: AnyView(
            content().environment(\.accessibilityEnabled, true)
        ))
        window.contentView = hosting
        let screens = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        window.setFrameOrigin(NSPoint(
            x: screens.minX - window.frame.width - 100,
            y: screens.minY - window.frame.height - 100
        ))
        window.orderBack(nil)
    }

    func close() {
        window.contentView = nil
        window.close()
    }

    func rect(_ screenRect: NSRect, in view: NSView) -> NSRect {
        view.convert(window.convertFromScreen(screenRect), from: nil)
    }

    /// A client read can materialize SwiftUI's virtual tree in the owned test process.
    func loadAccessibilityWindowTree() throws {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &windows
        )
        try #require(result == .success, "Own-process accessibility read returned \(result.rawValue)")
    }

    func elements() -> [AccessibilityTestNode] {
        var queue: [Any] = [hosting]
        var visited: Set<ObjectIdentifier> = []
        var result: [AccessibilityTestNode] = []
        var index = 0
        while index < queue.count {
            let object = queue[index] as AnyObject
            index += 1
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true,
                  visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let node = AccessibilityTestNode(object: object)
            result.append(node)
            queue.append(contentsOf: node.children)
            queue.append(contentsOf: node.contents)
            queue.append(contentsOf: node.visibleChildren)
        }
        return result
    }

    func controls(named name: String) -> [AccessibilityTestNode] {
        elements().filter {
            $0.label == name &&
            [.button, .checkBox, .popUpButton, .textField, .link].contains($0.role)
        }
    }

    func control(named name: String) throws -> AccessibilityTestNode {
        let matches = controls(named: name)
        #expect(matches.count == 1, "Expected one \(name); observed \(treeDescription)")
        return try #require(matches.first)
    }

    var treeDescription: String {
        elements().map {
            "\($0.role?.rawValue ?? "?") label=\($0.label ?? "") value=\(String(describing: $0.value))"
        }.joined(separator: "\n")
    }

    func settle(until predicate: () -> Bool = { true }) async throws {
        // Warm-up has a finite pass count, as in the existing About host.
        // Executor contention must not expire a condition budget before these finish.
        for _ in 0..<8 { await performLayoutPass() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                throw AccessibilityHostError.timeout(treeDescription)
            }
            await performLayoutPass()
        }
    }

    private func performLayoutPass() async {
        _ = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        pumpAppKitRunLoop()
        await Task.yield()
        #expect(!window.isKeyWindow)
        #expect(!window.isMainWindow)
    }

    private func pumpAppKitRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    func click(atScreenPoint point: NSPoint) async throws {
        let location = window.convertPoint(fromScreen: point)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            window.sendEvent(event)
        }
        try await settle()
    }
}

@Suite(.serialized) @MainActor
struct AccessibilityHostSettlingTests {
    @Test
    func readyControlSettlesAfterMainActorContention() async throws {
        var activations = 0
        let host = AccessibilityTestHost(width: 200, height: 80) {
            Button("Synthetic fixture action") { activations += 1 }
                .buttonStyle(.plain)
                .focusable(false)
        }
        defer { host.close() }
        let contention = Task { @MainActor in
            holdOwnedTestExecutor()
        }
        defer { contention.cancel() }
        try await host.settle()
        await contention.value
        #expect(try host.control(named: "Synthetic fixture action").press())
        #expect(activations == 1)
    }

    @Test
    func unavailableConditionStillTimesOut() async throws {
        let host = AccessibilityTestHost(width: 200, height: 80) {
            Text("Synthetic fixture")
        }
        defer { host.close() }
        let started = ContinuousClock.now
        do {
            try await host.settle(until: { false })
            Issue.record("A condition that never becomes ready must time out")
        } catch AccessibilityHostError.timeout {
            #expect(started.duration(to: .now) >= .seconds(1))
        }
    }

    private func holdOwnedTestExecutor() {
        // Reproduce contention beyond the old one-second warm-up budget.
        // This stalls only the guarded test process, never the installed app.
        Thread.sleep(forTimeInterval: 1.1)
    }
}
