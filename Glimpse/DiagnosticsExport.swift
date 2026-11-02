import AppKit
import Darwin
import Foundation
import GlimpseCore

enum DiagnosticsExport {
    struct LogResult: Sendable {
        var output: String
        var exitStatus: Int32
        var timedOut: Bool
        var truncated: Bool
    }

    /// Collect a bounded log excerpt without blocking the main actor.
    static func collectLogs(
        executableURL: URL, arguments: [String],
        timeout: TimeInterval = 10, outputLimit: Int = 1_048_576
    ) async throws -> LogResult {
        guard timeout.isFinite, timeout > 0, outputLimit > 0, outputLimit < Int.max else {
            throw POSIXError(.EINVAL)
        }
        return try await Task.detached(priority: .utility) {
            // A regular file avoids pipe backpressure even when log output is
            // larger than a pipe's buffer. Only a bounded excerpt enters memory.
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Glimpse-Logs-\(UUID().uuidString)")
            guard FileManager.default.createFile(
                atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600]
            ) else { throw CocoaError(.fileWriteUnknown) }
            defer {
                do { try FileManager.default.removeItem(at: fileURL) }
                catch { AppLogger.general.error("Could not remove temporary diagnostic log") }
            }
            let output = try FileHandle(forWritingTo: fileURL)
            defer {
                do { try output.close() }
                catch { AppLogger.general.error("Could not close diagnostic log output") }
            }
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let deadline = ContinuousClock.now + .seconds(timeout)
            var timedOut = false
            while process.isRunning {
                if ContinuousClock.now >= deadline {
                    timedOut = true
                    // SIGKILL gives the diagnostic collector a hard deadline even
                    // if it ignores SIGTERM. This is only the child we launched.
                    kill(process.processIdentifier, SIGKILL)
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            process.waitUntilExit()
            let input = try FileHandle(forReadingFrom: fileURL)
            defer {
                do { try input.close() }
                catch { AppLogger.general.error("Could not close diagnostic log input") }
            }
            let data = try input.read(upToCount: outputLimit + 1) ?? Data()
            return LogResult(
                output: String(decoding: data.prefix(outputLimit), as: UTF8.self),
                exitStatus: process.terminationStatus,
                timedOut: timedOut, truncated: data.count > outputLimit
            )
        }.value
    }

    static func export(
        to fileURL: URL,
        collect: @Sendable () async throws -> LogResult = {
            try await collectLogs(
                executableURL: URL(fileURLWithPath: "/usr/bin/log"),
                arguments: ["show", "--predicate", "process == \"Glimpse\"",
                            "--last", "5m", "--style", "compact"]
            )
        }
    ) async throws -> URL {
        var lines: [String] = []

        // Header
        lines.append("=== Glimpse Diagnostics ===")
        lines.append("Date: \(Date())")
        lines.append("App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
        lines.append("Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Application path: \(Bundle.main.bundleURL.path)")
        lines.append("Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        lines.append("Launch at login: \(LaunchAtLoginClient.liveValue.status().rawValue)")
        lines.append("")

        // Preferences
        lines.append("=== Preferences ===")
        let prefs = PreferencesClient.liveValue
        lines.append("Start of weekday: \(prefs.loadStartOfWeekday())")
        lines.append("Workdays: \(prefs.loadWorkdays().sorted())")
        lines.append("Display options: \(prefs.loadDisplayOptions())")
        lines.append("AI search enabled: \(prefs.loadShowAISearch())")
        lines.append("AI provider: \(prefs.loadAIProvider().rawValue)")
        let hotkeyEnabled = UserDefaults.standard.object(forKey: "hotkeyEnabled") == nil
            || UserDefaults.standard.bool(forKey: "hotkeyEnabled")
        lines.append("Hotkey enabled: \(hotkeyEnabled)")
        lines.append("Hotkey combo: \(HotkeyCombo.load().displayString)")
        lines.append("")

        // AI Provider
        lines.append("=== AI Provider ===")
        lines.append("Active provider: \(AIDateHelper.providerName())")
        lines.append("")

        // Entitlements
        lines.append("=== Calendar Access ===")
        let status = EventKitClient.liveValue.authorizationStatus()
        lines.append("EventKit authorization: \(status.rawValue)")
        lines.append("")

        // System logs (last 5 minutes)
        lines.append("=== Recent Logs (last 5 min) ===")
        do {
            let result = try await collect()
            if result.timedOut { lines.append("Log collection timed out after 10 seconds.") }
            if result.exitStatus != 0 {
                lines.append("Log collector exit status: \(result.exitStatus)")
            }
            if result.truncated { lines.append("Log excerpt limited to 1 MiB.") }
            lines.append(result.output.isEmpty ? "(no logs)" : result.output)
        } catch {
            AppLogger.general.error("Diagnostic log collection failed: \(error.localizedDescription, privacy: .private)")
            lines.append("Log collection failed: \(error.localizedDescription)")
        }

        let content = lines.joined(separator: "\n")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }

}
