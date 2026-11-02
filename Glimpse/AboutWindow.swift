import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = AboutView()
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "About Glimpse"
        w.contentView = NSHostingView(rootView: view)
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

private struct AboutView: View {
    @State private var updater = SparkleUpdater.shared
    @State private var diagnosticState: DiagnosticState = .idle

    enum DiagnosticState: Equatable {
        case idle, exporting, exported(String), failed(String)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 56, height: 56)
            }

            VStack(spacing: 4) {
                Text("Glimpse")
                    .font(.title3.weight(.semibold))
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("A lightweight macOS menu bar calendar")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            updateSection

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Diagnostics")
                        .font(.subheadline)
                    Text("Save logs and settings to a file")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                switch diagnosticState {
                case .idle:
                    Button("Export") { exportDiagnostics() }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                case .exporting:
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                case let .exported(path):
                    VStack(alignment: .trailing, spacing: AppDesign.Spacing.xs) {
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .font(.caption)
                        .foregroundStyle(.green)
                        Button("Export again") { exportDiagnostics() }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                case let .failed(msg):
                    VStack(alignment: .trailing, spacing: AppDesign.Spacing.xs) {
                        Text(msg).font(.caption2).foregroundStyle(.red)
                        Button("Retry") { exportDiagnostics() }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Retry exporting diagnostics")
                    }
                }
            }

            VStack(spacing: 4) {
                Link("github.com/iRedlof/Glimpse",
                     destination: URL(string: "https://github.com/iRedlof/Glimpse")!)
                    .font(.caption)
                    .focusable(false)
                Text("MIT License")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    // MARK: - Update Section

    @ViewBuilder
    private var updateSection: some View {
        switch updater.userDriver.status {
        case .idle:
            Button("Check for Updates") {
                updater.checkForUpdates()
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .disabled(!updater.canCheckForUpdates)

        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Checking for updates…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .latest:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("You're on the latest version")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case let .error(msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        case let .available(newVersion):
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                    Text("\(appVersion) → \(newVersion)")
                        .font(.caption.weight(.medium))
                }
                HStack(spacing: AppDesign.Spacing.md) {
                    Button("Install") {
                        updater.userDriver.pendingReply?(.install)
                        updater.userDriver.pendingReply = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .focusable(false)

                    Button("Skip") {
                        updater.userDriver.pendingReply?(.skip)
                        updater.userDriver.pendingReply = nil
                        updater.userDriver.status = .idle
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }

        case .downloading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Downloading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .extracting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Installing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .readyToInstall:
            Button("Install & Relaunch") {
                updater.userDriver.pendingInstallReply?(.install)
                updater.userDriver.pendingInstallReply = nil
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

    // MARK: - Diagnostics

    private func exportDiagnostics() {
        diagnosticState = .exporting
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.directoryURL = FileManager.default.urls(
            for: .desktopDirectory, in: .userDomainMask
        ).first
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        savePanel.nameFieldStringValue = "Glimpse-Diagnostics-\(timestamp).txt"
        savePanel.begin { response in
            guard response == .OK, let destination = savePanel.url else {
                diagnosticState = .idle
                return
            }
            Task { @MainActor in
                do {
                    let url = try await DiagnosticsExport.export(to: destination)
                    diagnosticState = .exported(url.path)
                } catch {
                    diagnosticState = .failed(error.localizedDescription)
                }
            }
        }
    }
}
