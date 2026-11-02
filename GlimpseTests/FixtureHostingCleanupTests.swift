import AppKit
import SwiftUI
import Testing

/// Terminal helper cleanup, measured separately from the preserved experiments.
@Suite(.serialized) @MainActor
struct FixtureHostingCleanupTests {
    @Test
    func aboutCloseReleasesHostingAfterScopeExit() async throws {
        let probe = try await closeAboutHost()
        try await expectHostingRelease(probe)
    }

    @Test
    func accessibilityCloseReleasesHostingAfterScopeExit() async throws {
        let probe = try await closeAccessibilityHost()
        try await expectHostingRelease(probe)
    }

    private func closeAboutHost() async throws -> HostingReleaseProbe {
        let fixture = UpdaterFixture()
        let host = AboutUpdateHost(updater: fixture.updater, fullAbout: false)
        let probe = HostingReleaseProbe(
            kind: "about", host: host, hosting: host.window.contentView
        )
        defer {
            host.close()
            fixture.delay.drain()
        }
        await host.settle()
        let treeCount = host.elements().count
        let subjectsPresent = probe.hostAlive && probe.hostingAlive
        try #require(subjectsPresent && treeCount > 0, "Measure a real settled About host")
        probe.record("settled-before-close")
        return probe
    }

    private func closeAccessibilityHost() async throws -> HostingReleaseProbe {
        let host = AccessibilityTestHost(width: 200, height: 80) {
            Button("Hosting cleanup fixture") {}
                .buttonStyle(.plain)
                .focusable(false)
        }
        let probe = HostingReleaseProbe(
            kind: "accessibility", host: host, hosting: host.hosting
        )
        defer { host.close() }
        try await host.settle()
        let treeCount = host.elements().count
        let subjectsPresent = probe.hostAlive && probe.hostingAlive
        try #require(subjectsPresent && treeCount > 0, "Measure a real settled accessibility host")
        probe.record("settled-before-close")
        return probe
    }

    private func expectHostingRelease(_ probe: HostingReleaseProbe) async throws {
        probe.record("after-scope-exit")
        let hostReleased = !probe.hostAlive
        try #require(hostReleased, "Release the helper before measuring its hosting view")
        let started = ContinuousClock.now
        let deadline = started.advanced(by: .seconds(1))
        var passes = 0
        defer {
            probe.record(
                "drain-ended", passes: passes,
                elapsed: started.duration(to: ContinuousClock.now)
            )
        }
        for _ in 0..<40 {
            try Task.checkCancellation()
            guard probe.hostingAlive && ContinuousClock.now < deadline else { break }
            pumpOwnedRunLoop()
            try await Task.sleep(for: .milliseconds(25))
            passes += 1
        }
        let hostingReleased = !probe.hostingAlive
        #expect(hostingReleased, "Terminal close must release hosting content after helper scope exit")
    }

    private func pumpOwnedRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.005, true)
    }
}

@MainActor
private final class HostingReleaseProbe {
    private weak var host: AnyObject?
    private weak var hosting: NSView?
    private let kind: String

    init(kind: String, host: AnyObject, hosting: NSView?) {
        self.kind = kind
        self.host = host
        self.hosting = hosting
    }

    var hostAlive: Bool { host != nil }
    var hostingAlive: Bool { hosting != nil }

    func record(_ phase: String, passes: Int = 0, elapsed: Duration = .zero) {
        let parts = elapsed.components
        let observation = HostingReleaseObservation(
            kind: kind, phase: phase, processID: ProcessInfo.processInfo.processIdentifier,
            hostAlive: hostAlive, hostingAlive: hostingAlive,
            drainPasses: passes,
            drainMilliseconds: Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15,
            taskCancelled: Task.isCancelled
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(observation)
            print("FIXTURE_HOSTING_CLEANUP \(String(decoding: data, as: UTF8.self))")
        } catch {
            Issue.record("Could not encode hosting cleanup observation: \(error)")
        }
    }
}

private struct HostingReleaseObservation: Encodable {
    let kind: String
    let phase: String
    let processID: Int32
    let hostAlive: Bool
    let hostingAlive: Bool
    let drainPasses: Int
    let drainMilliseconds: Double
    let taskCancelled: Bool
}
