import Foundation
import Testing

@testable import Glimpse

struct DiagnosticsExportTests {
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
        let result = try await DiagnosticsExport.export(to: destination) {
            .init(output: "fixture log excerpt", exitStatus: 0, timedOut: false, truncated: false)
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
        _ = try await DiagnosticsExport.export(to: destination) {
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
            _ = try await DiagnosticsExport.export(to: directory) {
                .init(output: "", exitStatus: 0, timedOut: false, truncated: false)
            }
        }
    }

    @Test
    func largeOutputCompletesAndReportIsBounded() async throws {
        let result = try await DiagnosticsExport.collectLogs(
            executableURL: URL(fileURLWithPath: "/usr/bin/head"),
            arguments: ["-c", "2097152", "/dev/zero"],
            timeout: 5, outputLimit: 1024
        )
        #expect(result.output.utf8.count == 1024)
        #expect(result.truncated)
        #expect(!result.timedOut)
        #expect(result.exitStatus == 0)
    }

    @Test
    func stalledCollectorHitsDeadline() async throws {
        let start = ContinuousClock.now
        let result = try await DiagnosticsExport.collectLogs(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"], timeout: 0.1
        )
        #expect(result.timedOut)
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test
    func nonzeroExitIsPreserved() async throws {
        let result = try await DiagnosticsExport.collectLogs(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"), arguments: []
        )
        #expect(result.exitStatus == 1)
        #expect(!result.timedOut)
    }

    @Test
    func unavailableCollectorThrowsInsteadOfHanging() async {
        await #expect(throws: (any Error).self) {
            try await DiagnosticsExport.collectLogs(
                executableURL: URL(fileURLWithPath: "/nonexistent/glimpse-log"), arguments: []
            )
        }
    }
}
