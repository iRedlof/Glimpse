import AppKit
import Observation
import UniformTypeIdentifiers

/// The Settings "Diagnostics…" flow: choose a destination, export, then offer Finder.
@Observable
@MainActor
final class DiagnosticsExportModel {
    enum State: Equatable {
        case idle
        case choosingDestination
        case exporting
        case exported(URL)
        case failed(String)
    }

    /// Native seams; tests replace the save panel, writer and Finder.
    struct Environment {
        var chooseDestination: @MainActor (
            _ suggestedName: String, _ completion: @escaping @MainActor (URL?) -> Void
        ) -> Void
        var export: @MainActor (URL) async throws -> URL
        var reveal: @MainActor (URL) -> Void
        var now: @MainActor () -> Date
    }

    private(set) var state: State = .idle
    private let environment: Environment
    private var generation = 0

    init(environment: Environment = .live) {
        self.environment = environment
    }

    /// Re-entry is refused while a destination is being chosen or written.
    var canBegin: Bool {
        switch state {
        case .choosingDestination, .exporting: false
        case .idle, .exported, .failed: true
        }
    }

    func begin() {
        guard canBegin else { return }
        generation += 1
        let current = generation
        state = .choosingDestination
        environment.chooseDestination(Self.suggestedFileName(at: environment.now())) { [weak self] url in
            self?.destinationChosen(url, generation: current)
        }
    }

    func revealExport() {
        guard case let .exported(url) = state else { return }
        environment.reveal(url)
    }

    private func destinationChosen(_ url: URL?, generation current: Int) {
        guard current == generation, state == .choosingDestination else { return }
        guard let url else {
            state = .idle
            return
        }
        state = .exporting
        let export = environment.export
        Task { @MainActor [weak self] in
            do {
                let written = try await export(url)
                guard let self, self.generation == current else { return }
                self.state = .exported(written)
            } catch {
                AppLogger.general.error("Diagnostics export failed: \(error.localizedDescription, privacy: .private)")
                guard let self, self.generation == current else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    /// e.g. "Glimpse-Diagnostics-2026-11-18T01-41-00-0800.txt" in the given time zone.
    static func suggestedFileName(at date: Date, timeZone: TimeZone = .current) -> String {
        let timestamp = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone))
            .replacingOccurrences(of: ":", with: "-")
        return "Glimpse-Diagnostics-\(timestamp).txt"
    }
}

extension DiagnosticsExportModel.Environment {
    static var live: Self { Self(
        chooseDestination: { suggestedName, completion in
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.canCreateDirectories = true
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            panel.nameFieldStringValue = suggestedName
            panel.begin { response in
                completion(response == .OK ? panel.url : nil)
            }
        },
        export: { try await DiagnosticsExport.export(to: $0) },
        reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        now: { Date() }
    ) }
}
