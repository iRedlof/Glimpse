import SwiftUI

/// Version text for the Settings About section.
enum AppVersionText {
    static let missing = "—"

    /// e.g. "Glimpse 1.5.1 (52)"; missing Info.plist values read as "—".
    static func productLine(infoDictionary: [String: Any]?) -> String {
        "Glimpse \(marketing(infoDictionary)) (\(build(infoDictionary)))"
    }

    static func marketing(_ infoDictionary: [String: Any]?) -> String {
        value(infoDictionary, key: "CFBundleShortVersionString")
    }

    static func build(_ infoDictionary: [String: Any]?) -> String {
        value(infoDictionary, key: "CFBundleVersion")
    }

    private static func value(_ infoDictionary: [String: Any]?, key: String) -> String {
        guard let text = infoDictionary?[key] as? String,
              !text.trimmingCharacters(in: .whitespaces).isEmpty else { return missing }
        return text
    }
}

/// Official Glimpse destinations shown in Settings.
enum GlimpseLinks {
    static let website = URL(string: "https://github.com/iRedlof/Glimpse")
    static let support = URL(string: "https://github.com/iRedlof/Glimpse/issues")
    static let releases = URL(string: "https://github.com/iRedlof/Glimpse/releases/latest")
}

/// Settings "About:" row: version, then Diagnostics…, Website and Support links.
@MainActor
struct SettingsAboutSection: View {
    let diagnostics: DiagnosticsExportModel
    var infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Settings.statusSpacing) {
            SettingsFlowLayout(
                spacing: AppDesign.Settings.rowSpacing, lineSpacing: AppDesign.Settings.statusSpacing
            ) {
                Text(AppVersionText.productLine(infoDictionary: infoDictionary))
                    .font(.system(size: AppDesign.Settings.supportingFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minHeight: AppDesign.Settings.minimumRowHeight)
                SettingsLinkButton("Diagnostics…", accessibilityLabel: "Export diagnostics") {
                    diagnostics.begin()
                }
                .disabled(!diagnostics.canBegin)
                .help("Save logs and settings to a file you choose")
                urlButton("Website", accessibilityLabel: "Glimpse website", url: GlimpseLinks.website)
                urlButton("Support", accessibilityLabel: "Glimpse support", url: GlimpseLinks.support)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            diagnosticsStatus
        }
    }

    @ViewBuilder
    private func urlButton(_ title: String, accessibilityLabel: String, url: URL?) -> some View {
        if let url {
            SettingsLinkButton(title, accessibilityLabel: accessibilityLabel) { openURL(url) }
                .help(url.absoluteString)
        }
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch diagnostics.state {
        case .idle, .choosingDestination:
            EmptyView()
        case .exporting:
            HStack(spacing: AppDesign.Settings.statusSpacing) {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                SettingsStatusText("Exporting diagnostics…")
            }
        case .exported:
            HStack(alignment: .firstTextBaseline, spacing: AppDesign.Settings.rowSpacing) {
                SettingsStatusText("Diagnostics saved.")
                SettingsLinkButton("Show in Finder", accessibilityLabel: "Show diagnostics in Finder") {
                    diagnostics.revealExport()
                }
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: AppDesign.Settings.statusSpacing) {
                SettingsStatusText("Couldn’t export diagnostics: \(message)")
                SettingsLinkButton("Try Again", accessibilityLabel: "Try exporting diagnostics again") {
                    diagnostics.begin()
                }
            }
        }
    }
}

/// Native link-style button that keeps its visible title as a Voice Control name.
struct SettingsLinkButton: View {
    private let title: String
    private let accessibilityLabel: String
    private let action: () -> Void

    init(_ title: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            // A full-row-height label keeps the target comfortable at the small link font.
            Text(title)
                .frame(minHeight: AppDesign.Settings.minimumRowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.link)
        // Keep the system link color even while Settings is not the key window.
        .foregroundStyle(Color(nsColor: .linkColor))
        .font(.system(size: AppDesign.Settings.supportingFontSize))
        .fixedSize()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityInputLabels([Text(title), Text(accessibilityLabel)])
    }
}

/// Supporting status copy under a Settings control.
struct SettingsStatusText: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: AppDesign.Settings.supportingFontSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
