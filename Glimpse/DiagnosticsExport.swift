import AppKit
import Foundation
import GlimpseCore
import OSLog

enum DiagnosticsExport {
    struct LogResult: Sendable {
        var output: String
        var timedOut: Bool
        var truncated: Bool
        var outputLimit: Int? = nil
        var candidateLimit: Int? = nil
    }

    struct LogEntry: Sendable {
        var date: Date
        var processIdentifier: Int32
        var subsystem: String
        var category: String
        var level: String
        var message: String
    }

    enum CollectionError: Error, Equatable, Sendable {
        case invalidLimits
        case alreadyCollecting
    }

    /// Locks protect only ownership and waiter state, never provider/iterator work.
    final class LogCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var active: Request?
        private static let candidateLimit = 10_000
        private let submitWorker: @Sendable (@escaping @Sendable () -> Void) -> Void
        private let awaitDeadline: @Sendable (TimeInterval) async throws -> Void

        /// Scheduling seams keep the same timeout origin and synchronous worker.
        init(
            submitWorker: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = {
                DispatchQueue.global(qos: .utility).async(execute: $0)
            },
            awaitDeadline: @escaping @Sendable (TimeInterval) async throws -> Void = {
                try await Task.sleep(for: .seconds($0))
            }
        ) {
            self.submitWorker = submitWorker
            self.awaitDeadline = awaitDeadline
        }

        private final class Request: @unchecked Sendable {
            private let lock = NSLock()
            private var outcome: Result<LogResult, any Error>?
            private var continuation: CheckedContinuation<LogResult, any Error>?
            private var timer: Task<Void, Never>?

            var shouldStop: Bool { lock.withLock { outcome != nil } }

            func install(_ continuation: CheckedContinuation<LogResult, any Error>) {
                let completed = lock.withLock { () -> Result<LogResult, any Error>? in
                    if let outcome { return outcome }
                    self.continuation = continuation
                    return nil
                }
                if let completed { continuation.resume(with: completed) }
            }

            func installTimer(_ timer: Task<Void, Never>) {
                let completed = lock.withLock {
                    if outcome != nil { return true }
                    self.timer = timer
                    return false
                }
                if completed { timer.cancel() }
            }

            func deliver(_ result: Result<LogResult, any Error>) {
                let delivery = lock.withLock { () -> (CheckedContinuation<LogResult, any Error>?, Task<Void, Never>?) in
                    guard outcome == nil else { return (nil, nil) }
                    outcome = result
                    let delivery = (continuation, timer)
                    continuation = nil
                    timer = nil
                    return delivery
                }
                delivery.1?.cancel()
                delivery.0?.resume(with: result)
            }
        }

        func collect(
            timeout: TimeInterval, outputLimit: Int,
            read: @escaping @Sendable () throws -> AnySequence<LogEntry>
        ) async throws -> LogResult {
            try Task.checkCancellation()
            guard timeout.isFinite, timeout > 0, timeout <= 60,
                  outputLimit > 0, outputLimit <= 1_048_576 else {
                throw CollectionError.invalidLimits
            }
            let request = Request()
            let reserved = lock.withLock {
                guard active == nil else { return false }
                active = request
                return true
            }
            guard reserved else { throw CollectionError.alreadyCollecting }

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    request.install(continuation)
                    // A detached timer owns no SDK state and never joins the
                    // synchronous worker. Cancellation/deadline can deliver first.
                    let timer = Task.detached(priority: .utility) { [awaitDeadline] in
                        do { try await awaitDeadline(timeout) }
                        catch { return }
                        request.deliver(.success(LogResult(
                            output: "", timedOut: true, truncated: false,
                            outputLimit: outputLimit, candidateLimit: Self.candidateLimit
                        )))
                    }
                    request.installTimer(timer)
                    submitWorker {
                        let result: Result<LogResult, any Error> = autoreleasepool {
                            Result {
                                try Self.readEntries(request: request, outputLimit: outputLimit, read: read)
                            }
                        }
                        // All native/sequence state is gone before freeing this
                        // worker's reservation. Late delivery cannot free a newer one.
                        self.lock.withLock {
                            if self.active === request { self.active = nil }
                        }
                        request.deliver(result)
                    }
                }
            } onCancel: {
                request.deliver(.failure(CancellationError()))
            }
        }

        private static func readEntries(
            request: Request, outputLimit: Int,
            read: @Sendable () throws -> AnySequence<LogEntry>
        ) throws -> LogResult {
            guard !request.shouldStop else { throw CancellationError() }
            let cutoff = Date().addingTimeInterval(-300)
            let pid = ProcessInfo.processInfo.processIdentifier
            let entries = try read()
            let iterator = entries.makeIterator()
            let formatter = ISO8601DateFormatter()
            var output: [UInt8] = []
            var scanned = 0
            var truncated = false
            while scanned < candidateLimit, !request.shouldStop {
                guard let entry = iterator.next() else { break }
                scanned += 1
                guard !request.shouldStop else { break }
                guard entry.processIdentifier == pid,
                      entry.subsystem == "com.rohit.Glimpse", entry.date >= cutoff else { continue }
                let line = "\(formatter.string(from: entry.date)) [\(entry.level)] \(entry.subsystem)/\(entry.category): \(entry.message)\n"
                let remaining = outputLimit - output.count
                let bytes = Array(line.utf8.prefix(remaining + 1))
                if bytes.count > remaining {
                    var prefix = Array(bytes.prefix(remaining))
                    // At most three trailing bytes need removal to restore a
                    // scalar boundary. Never substitute a privacy/message byte.
                    while String(bytes: prefix, encoding: .utf8) == nil { prefix.removeLast() }
                    output.append(contentsOf: prefix)
                    truncated = true
                    break
                }
                output.append(contentsOf: bytes)
                if output.count == outputLimit {
                    truncated = true
                    break
                }
            }
            // No lookahead: candidate 10,001 could block, even if rejected.
            if scanned == candidateLimit { truncated = true }
            return LogResult(
                output: String(decoding: output, as: UTF8.self), timedOut: false,
                truncated: truncated, outputLimit: outputLimit, candidateLimit: candidateLimit
            )
        }
    }

    private static let logCollector = LogCollector()

    /// SDK objects and the lazy iterator are constructed/consumed only on the worker.
    static func collectLogs(
        timeout: TimeInterval = 10, outputLimit: Int = 1_048_576
    ) async throws -> LogResult {
        try await logCollector.collect(timeout: timeout, outputLimit: outputLimit) {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(at: store.position(date: Date().addingTimeInterval(-300)))
            return AnySequence {
                let iterator = entries.makeIterator()
                return AnyIterator<LogEntry> {
                    withExtendedLifetime(store) {
                        guard let entry = iterator.next() else { return nil }
                        guard let log = entry as? OSLogEntryLog else {
                            // Count every native candidate, including non-log
                            // entries; skipping them inside next() evades the cap.
                            return LogEntry(date: entry.date, processIdentifier: -1,
                                            subsystem: "", category: "", level: "", message: "")
                        }
                        return LogEntry(
                            date: log.date, processIdentifier: log.processIdentifier,
                            subsystem: log.subsystem, category: log.category,
                            level: String(describing: log.level), message: log.composedMessage
                        )
                    }
                }
            }
        }
    }

    static func export(
        to fileURL: URL,
        hotkey: HotkeyDiagnosticSnapshot? = nil,
        collect: @Sendable () async throws -> LogResult = { try await collectLogs() }
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
        let hotkeySnapshot: HotkeyDiagnosticSnapshot
        if let hotkey {
            hotkeySnapshot = hotkey
        } else {
            hotkeySnapshot = await MainActor.run { GlobalHotkey.shared.snapshot() }
        }
        lines.append("Hotkey requested: \(hotkeySnapshot.requested)")
        lines.append("Hotkey registered: \(hotkeySnapshot.registered)")
        lines.append("Hotkey saved combo: \(hotkeySnapshot.savedCombo.displayString)")
        lines.append("Hotkey active combo: \(hotkeySnapshot.activeCombo?.displayString ?? "(none)")")
        lines.append("Hotkey registration error: \(hotkeySnapshot.error.map { String(describing: $0) } ?? "(none)")")
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

        // Retention is best effort and excludes earlier launches.
        lines.append("=== Recent Logs (current launch, last 5 min) ===")
        lines.append("Scope: this process only, subsystem com.rohit.Glimpse.")
        do {
            let result = try await collect()
            if let bytes = result.outputLimit, let candidates = result.candidateLimit {
                lines.append("Collection limits: \(bytes) UTF-8 bytes; \(candidates) candidate entries.")
            }
            if result.timedOut {
                lines.append("Log collection deadline reached. The native read may still be in progress.")
            }
            if result.truncated {
                lines.append("Log excerpt reached a collection limit and may be incomplete.")
            }
            if !result.output.isEmpty {
                lines.append(result.output)
            } else if !result.timedOut, !result.truncated {
                lines.append("No matching retained entries were returned for this process during the last five minutes.")
            } else {
                lines.append("No log excerpt available within the collection limits.")
            }
        } catch CollectionError.alreadyCollecting {
            lines.append("Log collection is still in progress from an earlier request; no additional read was started.")
        } catch {
            AppLogger.general.error("Diagnostic log collection failed: \(error.localizedDescription, privacy: .private)")
            lines.append("Log collection failed: \(error.localizedDescription)")
        }

        let content = lines.joined(separator: "\n")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }

}
