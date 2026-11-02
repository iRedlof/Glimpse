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

struct AboutView: View {
    @State private var updater: SparkleUpdater
    @State private var diagnosticState: DiagnosticState = .idle

    init(updater: SparkleUpdater = .shared) {
        _updater = State(initialValue: updater)
    }

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

            AboutUpdateSection(updater: updater, appVersion: appVersion)

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

@MainActor
struct AboutUpdateSection: View {
    let updater: SparkleUpdater
    let appVersion: String
    private static let releasesURL = URL(string: "https://github.com/iRedlof/Glimpse/releases/latest")

    // MARK: - Update Section

    @ViewBuilder
    var body: some View {
        switch updater.userDriver.status {
        case .idle:
            checkButton("Check for Updates", accessibilityLabel: "Check for updates")

        case .initializationFailed:
            VStack(spacing: AppDesign.Spacing.sm) {
                statusText("Updates are unavailable.")
                statusText("Get the latest Glimpse release from GitHub.")
                    .foregroundStyle(.secondary)
                releasesLink
            }

        case .checking:
            HStack(spacing: AppDesign.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Checking for updates…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .latest:
            HStack(spacing: AppDesign.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("No newer update was found")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case let .noUpdate(guidance):
            VStack(spacing: AppDesign.Spacing.sm) {
                guidanceText(guidance)
                HStack(spacing: AppDesign.Spacing.sm) {
                    checkButton("Check for Updates", accessibilityLabel: "Check for updates")
                    releasesLink
                }
                if !updater.canCheckForUpdates {
                    statusText("Checking is temporarily unavailable.")
                        .foregroundStyle(.secondary)
                }
            }

        case let .error(failure):
            VStack(spacing: AppDesign.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.xs) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    statusText(failure == .check
                               ? "Couldn’t check for updates."
                               : "The update couldn’t be completed.")
                }
                if failure == .update {
                    statusText("Check again for available updates.")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: AppDesign.Spacing.sm) {
                    if failure == .check {
                        checkButton("Retry", accessibilityLabel: "Retry checking for updates")
                    } else {
                        checkButton("Check for Updates", accessibilityLabel: "Check for updates")
                    }
                    releasesLink
                }
                if failure == .check, !updater.canCheckForUpdates {
                    statusText("Retry is temporarily unavailable.")
                        .foregroundStyle(.secondary)
                }
            }

        case let .available(newVersion):
            let id = updater.userDriver.updateChoiceID
            VStack(spacing: AppDesign.Spacing.sm) {
                HStack(spacing: AppDesign.Spacing.xs) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("\(appVersion) → \(newVersion)")
                        .font(.caption.weight(.medium))
                }
                HStack(spacing: AppDesign.Spacing.md) {
                    Button {
                        if let id { updater.userDriver.chooseUpdate(.install, id: id) }
                    } label: {
                        actionLabel("Install")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Install update")
                    .disabled(id == nil)

                    Button {
                        if let id { updater.userDriver.chooseUpdate(.skip, id: id) }
                    } label: {
                        actionLabel("Skip")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip this update")
                    .disabled(id == nil)
                }
            }

        case .downloading:
            HStack(spacing: AppDesign.Spacing.sm) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Downloading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .extracting:
            HStack(spacing: AppDesign.Spacing.sm) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Installing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .readyToInstall:
            let id = updater.userDriver.installChoiceID
            Button {
                if let id { updater.userDriver.chooseInstallAndRelaunch(id: id) }
            } label: {
                actionLabel("Install & Relaunch")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
            .accessibilityLabel("Install update and relaunch Glimpse")
            .disabled(id == nil)
        }
    }

    @ViewBuilder
    private func guidanceText(_ guidance: UpdateNoUpdateGuidance) -> some View {
        switch guidance.reason {
        case .unknown:
            statusText("No installable update was found.")
            statusText("Check again or view Glimpse releases on GitHub.")
                .foregroundStyle(.secondary)
        case .newerThanFeed:
            statusText("You’re running a newer version.")
            statusText("Your installed version is newer than the version in the update feed. You can keep using this version.")
                .foregroundStyle(.secondary)
        case .systemTooOld:
            statusText("This update needs a newer macOS version.")
            if let version = guidance.requirementVersion {
                statusText("Requires macOS \(version) or later.")
                    .foregroundStyle(.secondary)
            }
            statusText("Check Software Update in System Settings, then check again.")
                .foregroundStyle(.secondary)
        case .systemTooNew:
            statusText("Your macOS version is newer than this update supports.")
            if let version = guidance.requirementVersion {
                statusText("This update supports up to macOS \(version).")
                    .foregroundStyle(.secondary)
            }
            statusText("View releases for compatibility details, or check again later.")
                .foregroundStyle(.secondary)
        case .requiresAppleSilicon:
            statusText("This update requires Apple silicon.")
            statusText("It can’t be installed on this Intel Mac. View releases for compatibility details.")
                .foregroundStyle(.secondary)
        }
    }

    private func checkButton(_ title: String, accessibilityLabel: String) -> some View {
        Button {
            updater.checkForUpdates()
        } label: {
            actionLabel(title)
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(accessibilityLabel)
        .disabled(!updater.canCheckForUpdates)
    }

    @ViewBuilder
    private var releasesLink: some View {
        if let destination = Self.releasesURL {
            Link(destination: destination) {
                actionLabel("View Releases")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("View Glimpse releases on GitHub")
        }
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, AppDesign.Spacing.sm)
            .padding(.vertical, AppDesign.Spacing.xs)
            .contentShape(Rectangle())
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
