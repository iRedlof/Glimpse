import Foundation
import Testing

@testable import Glimpse

struct DiagnosticsExportTests {
    private static let inactiveHotkey = HotkeyDiagnosticSnapshot(
        requested: false, registered: false, savedCombo: .default, activeCombo: nil, error: nil
    )

    @Test
    func exportWritesMetadataAndLogsToChosenDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Export-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Cleanup is best effort after the assertions; it cannot affect the report.
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("chosen-report.txt")
        let result = try await DiagnosticsExport.export(to: destination, hotkey: Self.inactiveHotkey) {
            .init(output: "fixture log excerpt", timedOut: false, truncated: false)
        }
        #expect(result == destination)
        let report = try String(contentsOf: destination, encoding: .utf8)
        #expect(report.contains("=== Glimpse Diagnostics ==="))
        #expect(report.contains("App Version:"))
        #expect(report.contains("Launch at login:"))
        #expect(report.contains("fixture log excerpt"))
    }

    @Test
    func collectorFailureStillSavesUsefulReportAtChosenDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Export-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Cleanup is best effort after the assertions; it cannot affect the report.
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("partial-report.txt")
        _ = try await DiagnosticsExport.export(to: destination, hotkey: Self.inactiveHotkey) {
            throw NSError(domain: "GlimpseFixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "fixture collector failure"])
        }
        let report = try String(contentsOf: destination, encoding: .utf8)
        #expect(report.contains("App Version:"))
        #expect(report.contains("=== Preferences ==="))
        #expect(report.contains("Log collection failed: fixture collector failure"))
    }

    @Test
    func destinationWriteFailureIsReportedToCaller() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Export-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Cleanup is best effort after the assertions; it cannot affect the report.
            try? FileManager.default.removeItem(at: directory)
        }
        await #expect(throws: (any Error).self) {
            _ = try await DiagnosticsExport.export(to: directory, hotkey: Self.inactiveHotkey) {
                .init(output: "", timedOut: false, truncated: false)
            }
        }
    }

    @Test
    func reportDistinguishesStartupIntentFromFailedRegistration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Hotkey-Report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Best-effort cleanup follows report assertions, with no host preferences.
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("startup-failure.txt")
        _ = try await DiagnosticsExport.export(
            to: destination, hotkey: .init(
                requested: true, registered: false, savedCombo: .default,
                activeCombo: nil, error: .registrationFailed(-50)
            )
        ) {
            .init(output: "", timedOut: false, truncated: false)
        }
        let report = try String(contentsOf: destination, encoding: .utf8)
        #expect(report.contains("Hotkey requested: true"))
        #expect(report.contains("Hotkey registered: false"))
        #expect(report.contains("Hotkey active combo: (none)"))
        #expect(report.contains("registrationFailed(-50)"))
    }

    @Test
    func reportDistinguishesExplicitOffFromFailedNativeTeardown() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Hotkey-Report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            // Best-effort cleanup follows report assertions, with no host preferences.
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("disable-failure.txt")
        _ = try await DiagnosticsExport.export(
            to: destination, hotkey: .init(
                requested: false, registered: true, savedCombo: .default,
                activeCombo: .default, error: .unregisterFailed(-50)
            )
        ) {
            .init(output: "", timedOut: false, truncated: false)
        }
        let report = try String(contentsOf: destination, encoding: .utf8)
        #expect(report.contains("Hotkey requested: false"))
        #expect(report.contains("Hotkey registered: true"))
        #expect(report.contains("Hotkey saved combo: ⇧⌘C"))
        #expect(report.contains("Hotkey active combo: ⇧⌘C"))
        #expect(report.contains("unregisterFailed(-50)"))
    }

    private static func entry(
        _ message: String, date: Date = Date(),
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        subsystem: String = "com.rohit.Glimpse"
    ) -> DiagnosticsExport.LogEntry {
        .init(date: date, processIdentifier: pid, subsystem: subsystem,
              category: "fixture", level: "info", message: message)
    }

    private static func report(_ collect: @escaping @Sendable () async throws -> DiagnosticsExport.LogResult) async throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse-Collector-Report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("report.txt")
        _ = try await DiagnosticsExport.export(to: destination, hotkey: inactiveHotkey, collect: collect)
        return try String(contentsOf: destination, encoding: .utf8)
    }

    // Synchronization belongs to the fixture boundary: the real collector is
    // responsible for deciding whether and how often it invokes this provider.
    private final class ReaderProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var starts = 0
        private var candidates = 0
        private var exits = 0
        private let release = DispatchSemaphore(value: 0)

        var startCount: Int { lock.withLock { starts } }
        var candidateCount: Int { lock.withLock { candidates } }
        var exitCount: Int { lock.withLock { exits } }
        func recordStart() { lock.withLock { starts += 1 } }
        func recordCandidate() { lock.withLock { candidates += 1 } }
        func unblock() { release.signal() }
        func block() {
            recordStart()
            // A test watchdog also prevents a broken collector from stranding the runner.
            _ = release.wait(timeout: .now() + 5)
            lock.withLock { exits += 1 }
        }
        func waitForStart() async throws -> Bool {
            let deadline = ContinuousClock.now + .seconds(1)
            while startCount == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            return startCount > 0
        }
    }

    private static func collectAfterWorkerExit(_ collector: DiagnosticsExport.LogCollector) async throws -> DiagnosticsExport.LogResult {
        let deadline = ContinuousClock.now + .seconds(2)
        while true {
            do {
                return try await collector.collect(timeout: 1, outputLimit: 1024) {
                    AnySequence([entry("collection after exit")])
                }
            } catch DiagnosticsExport.CollectionError.alreadyCollecting {
                if ContinuousClock.now >= deadline { throw DiagnosticsExport.CollectionError.alreadyCollecting }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    @Test
    func currentProcessEntriesAppearInReport() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let report = try await Self.report {
            try await collector.collect(timeout: 1, outputLimit: 1024) {
                AnySequence([Self.entry("current fixture <private>")])
            }
        }
        #expect(report.contains("current fixture <private>"))
    }

    @Test
    func unrelatedAndOldEntriesAreExcluded() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let result = try await collector.collect(timeout: 1, outputLimit: 1024) {
            AnySequence([
                Self.entry("foreign process", pid: -1),
                Self.entry("foreign subsystem", subsystem: "com.example.Other"),
                Self.entry("old entry", date: Date().addingTimeInterval(-301)),
                Self.entry("valid entry")
            ])
        }
        #expect(result.output.contains("valid entry"))
        #expect(!result.output.contains("foreign process"))
        #expect(!result.output.contains("foreign subsystem"))
        #expect(!result.output.contains("old entry"))
    }

    @Test
    func emptyEntriesProduceValidEmptyResult() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let result = try await collector.collect(timeout: 1, outputLimit: 1024) { AnySequence([]) }
        #expect(result.output.isEmpty)
        #expect(!result.timedOut)
        #expect(!result.truncated)
        let report = try await Self.report { result }
        #expect(report.contains("current launch"))
        #expect(report.contains("No matching retained entries"))
        #expect(!report.contains("(no logs)"))
    }

    @Test
    func unicodeByteBoundaryRemainsValid() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let result = try await collector.collect(timeout: 1, outputLimit: 180) {
            AnySequence([Self.entry("UNICODE " + String(repeating: "🙂é", count: 80))])
        }
        #expect(result.output.utf8.count <= 180)
        #expect(result.output.contains("UNICODE 🙂é")) // Cap reaches beyond the formatted prefix.
        #expect(!result.output.contains("�"))
        #expect(result.truncated)
    }

    @Test
    func candidateScanIsBounded() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        let result = try await collector.collect(timeout: 1, outputLimit: 1024) {
            AnySequence {
                var remaining = 20_000
                return AnyIterator<DiagnosticsExport.LogEntry> {
                    guard remaining > 0 else { return nil }
                    remaining -= 1
                    probe.recordCandidate()
                    return Self.entry("rejected candidate", pid: -1)
                }
            }
        }
        #expect(probe.candidateCount == 10_000)
        #expect(result.output.isEmpty)
        #expect(result.truncated)
        let report = try await Self.report { result }
        #expect(report.contains("may be incomplete"))
        #expect(!report.contains("Log excerpt limited to 1 MiB."))
    }

    @Test
    func blockedProviderDoesNotBlockDeadline() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        defer { probe.unblock() }
        let start = ContinuousClock.now
        let waiter = Task {
            try await collector.collect(timeout: 0.2, outputLimit: 1024) {
                probe.block()
                return AnySequence([Self.entry("late provider result")])
            }
        }
        try #require(try await probe.waitForStart())
        let result = try await waiter.value
        #expect(result.timedOut)
        #expect(start.duration(to: .now) < .seconds(1))
        #expect(probe.exitCount == 0)
        let report = try await Self.report { result }
        #expect(report.contains("App Version:"))
        #expect(report.contains("deadline reached"))
        #expect(!report.contains("after 10 seconds"))
        #expect(!report.contains("No matching retained entries"))
        probe.unblock()
        let next = try await Self.collectAfterWorkerExit(collector)
        #expect(next.output.contains("collection after exit"))
        #expect(!next.output.contains("late provider result"))
    }

    @Test
    func timedOutWorkerRetainsExclusiveOwnership() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        defer { probe.unblock() }
        let waiter = Task {
            try await collector.collect(timeout: 0.2, outputLimit: 1024) {
                probe.block()
                return AnySequence([])
            }
        }
        try #require(try await probe.waitForStart())
        #expect(try await waiter.value.timedOut)
        await #expect(throws: DiagnosticsExport.CollectionError.alreadyCollecting) {
            try await collector.collect(timeout: 1, outputLimit: 1024) {
                probe.recordStart()
                return AnySequence([])
            }
        }
        #expect(probe.startCount == 1)
        #expect(probe.exitCount == 0)
        let report = try await Self.report {
            try await collector.collect(timeout: 1, outputLimit: 1024) { AnySequence([]) }
        }
        #expect(report.contains("collection is still in progress"))
        #expect(report.contains("App Version:"))
        probe.unblock()
        #expect(try await Self.collectAfterWorkerExit(collector).output.contains("collection after exit"))
    }

    @Test
    func blockedIteratorDoesNotBlockDeadline() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        defer { probe.unblock() }
        let waiter = Task {
            try await collector.collect(timeout: 0.2, outputLimit: 1024) {
                AnySequence {
                    AnyIterator<DiagnosticsExport.LogEntry> {
                        probe.block()
                        return Self.entry("late iterator result")
                    }
                }
            }
        }
        try #require(try await probe.waitForStart())
        let start = ContinuousClock.now
        #expect(try await waiter.value.timedOut)
        #expect(start.duration(to: .now) < .seconds(1))
        #expect(probe.exitCount == 0)
        probe.unblock()
        let next = try await Self.collectAfterWorkerExit(collector)
        #expect(next.output.contains("collection after exit"))
        #expect(!next.output.contains("late iterator result"))
    }

    @Test
    func cancellationBeforeStartDoesNotRead() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await collector.collect(timeout: 1, outputLimit: 1024) {
                probe.recordStart()
                return AnySequence([])
            }
        }
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(probe.startCount == 0)
        #expect(try await Self.collectAfterWorkerExit(collector).output.contains("collection after exit"))
    }

    @Test
    func cancellationDuringReadRetainsOwnership() async throws {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        defer { probe.unblock() }
        let waiter = Task {
            try await collector.collect(timeout: 5, outputLimit: 1024) {
                probe.block()
                return AnySequence([Self.entry("late canceled result")])
            }
        }
        try #require(try await probe.waitForStart())
        let start = ContinuousClock.now
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(start.duration(to: .now) < .seconds(1))
        await #expect(throws: DiagnosticsExport.CollectionError.alreadyCollecting) {
            try await collector.collect(timeout: 1, outputLimit: 1024) {
                probe.recordStart()
                return AnySequence([])
            }
        }
        #expect(probe.startCount == 1)
        #expect(probe.exitCount == 0)
        probe.unblock()
        let next = try await Self.collectAfterWorkerExit(collector)
        #expect(next.output.contains("collection after exit"))
        #expect(!next.output.contains("late canceled result"))
    }

    private enum FixtureFailure: Error { case unavailable }

    @Test
    func providerFailureReleasesOwnership() async throws {
        let collector = DiagnosticsExport.LogCollector()
        await #expect(throws: FixtureFailure.unavailable) {
            try await collector.collect(timeout: 1, outputLimit: 1024) { throw FixtureFailure.unavailable }
        }
        let report = try await Self.report {
            try await collector.collect(timeout: 1, outputLimit: 1024) { throw FixtureFailure.unavailable }
        }
        #expect(report.contains("Log collection failed:"))
        #expect(report.contains("App Version:"))
        #expect(try await Self.collectAfterWorkerExit(collector).output.contains("collection after exit"))
    }

    @Test
    func invalidLimitsDoNotStartReader() async {
        let collector = DiagnosticsExport.LogCollector()
        let probe = ReaderProbe()
        let limits: [(TimeInterval, Int)] = [
            (0, 1024), (-1, 1024), (.nan, 1024), (.infinity, 1024),
            (-.infinity, 1024), (60.1, 1024), (1, 0), (1, -1), (1, 1_048_577)
        ]
        for (timeout, outputLimit) in limits {
            await #expect(throws: DiagnosticsExport.CollectionError.invalidLimits) {
                try await collector.collect(timeout: timeout, outputLimit: outputLimit) {
                    probe.recordStart()
                    return AnySequence([])
                }
            }
        }
        #expect(probe.startCount == 0)
    }
}
