import SwiftUI

/// Copy for the time of the last update check.
enum UpdateCheckTimeText {
    /// "9:41 AM" for today; "Nov 17" for an earlier day (locale formatted).
    static func checkedTime(
        _ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        var calendar = calendar
        calendar.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .hour().minute())
        }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day())
    }

    /// A check this session reported the latest version.
    static func upToDate(
        checkedAt date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        "Up to date · checked \(checkedTime(date, now: now, calendar: calendar, locale: locale))"
    }

    /// Sparkle's persisted last check, whose outcome this session didn't see.
    static func lastChecked(
        _ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        "Last checked \(checkedTime(date, now: now, calendar: calendar, locale: locale))"
    }
}

/// Copy for update phases that outlive the offered version's status case.
enum UpdateStatusText {
    /// "1.5.4 is ready" when the offered version is known, else "Ready to install".
    static func ready(version: String?) -> String {
        version.map { "\($0) is ready" } ?? "Ready to install"
    }
}

/// Settings "Updates:" row: automatic checks, Check Now and the inline Sparkle status.
/// Every `UpdateStatus` case has its own presentation (pre-production review A4).
@MainActor
struct SettingsUpdatesSection: View {
    let updater: SparkleUpdater
    var now: @MainActor () -> Date = { Date() }

    private var driver: InlineUpdateDriver { updater.userDriver }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Settings.statusSpacing) {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticallyChecksForUpdates($0) }
            ))
            .toggleStyle(.checkbox)
            .disabled(!updater.canChangeAutomaticChecks)
            statusRow
                .frame(minHeight: AppDesign.Settings.minimumRowHeight)
            details
        }
    }

    // MARK: - Status row

    @ViewBuilder
    private var statusRow: some View {
        HStack(alignment: .center, spacing: AppDesign.Settings.rowSpacing) {
            switch driver.status {
            case .idle:
                checkNowButton
                if let line = idleLine { statusLabel(line, symbol: idleSymbol) }
            case .initializationFailed:
                statusLabel("Updates are unavailable.", symbol: .failure)
                releasesLink
            case .checking:
                checkNowButton
                progressLabel("Checking…")
            case .latest:
                checkNowButton
                statusLabel(UpdateCheckTimeText.upToDate(
                    checkedAt: driver.lastUpToDateDate ?? now(), now: now()
                ), symbol: .success)
            // Guidance and failures keep both actions on one line; the reason follows below.
            case .noUpdate:
                checkNowButton
                releasesLink
            case .error:
                actionButton("Try Again", accessibilityLabel: "Try checking for updates again") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                releasesLink
            case let .available(version):
                availableRow(version: version)
            case .downloading:
                downloadRow
            case .extracting:
                progressLabel("Installing…")
            case .readyToInstall:
                let id = driver.installChoiceID
                actionButton("Install and Relaunch", accessibilityLabel: "Install update and relaunch Glimpse",
                             prominent: true) {
                    if let id { driver.chooseInstallAndRelaunch(id: id) }
                }
                .disabled(id == nil)
                statusLabel(UpdateStatusText.ready(version: driver.updateVersion), symbol: nil)
            }
        }
    }

    private var checkNowButton: some View {
        actionButton("Check Now", accessibilityLabel: "Check for updates now") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }

    private var idleLine: String? {
        if let date = driver.lastUpToDateDate {
            return UpdateCheckTimeText.upToDate(checkedAt: date, now: now())
        }
        return updater.lastUpdateCheckDate.map { UpdateCheckTimeText.lastChecked($0, now: now()) }
    }

    private var idleSymbol: StatusSymbol? {
        driver.lastUpToDateDate == nil ? nil : .success
    }

    @ViewBuilder
    private func availableRow(version: String) -> some View {
        let id = driver.updateChoiceID
        actionButton("Update", accessibilityLabel: "Update to version \(version)", prominent: true) {
            if let id { driver.chooseUpdate(.install, id: id) }
        }
        .disabled(id == nil)
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Settings.statusSpacing) {
            statusLabel("Version \(version) available", symbol: .available, emphasized: true)
            Text("·")
                .font(.system(size: AppDesign.Settings.supportingFontSize))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            SettingsLinkButton("Skip", accessibilityLabel: "Skip version \(version)") {
                if let id { driver.chooseUpdate(.skip, id: id) }
            }
            .disabled(id == nil)
        }
    }

    @ViewBuilder
    private var downloadRow: some View {
        let percent = driver.downloadProgress.map { Int(($0 * 100).rounded(.down)) }
        Group {
            if let progress = driver.downloadProgress {
                ProgressView(value: progress)
            } else {
                ProgressView()
            }
        }
        .progressViewStyle(.linear)
        .frame(width: AppDesign.Settings.downloadProgressWidth)
        // The text below carries the same percentage, so VoiceOver reads it once.
        .accessibilityHidden(true)
        SettingsStatusText(percent.map { "Downloading… \($0)%" } ?? "Downloading…")
    }

    // MARK: - Details

    @ViewBuilder
    private var details: some View {
        switch driver.status {
        case .initializationFailed:
            SettingsStatusText("Get the latest Glimpse release from GitHub.")
        case let .noUpdate(guidance):
            statusLabel(Self.headline(for: guidance.reason), symbol: .information)
            ForEach(Self.details(for: guidance), id: \.self) { SettingsStatusText($0) }
            if !updater.canCheckForUpdates {
                SettingsStatusText("Checking is temporarily unavailable.")
            }
        case let .error(failure):
            statusLabel(failure == .check
                        ? "Couldn’t check for updates."
                        : "The update couldn’t be completed.", symbol: .failure)
            if !updater.canCheckForUpdates {
                SettingsStatusText("Trying again is temporarily unavailable.")
            }
        case .idle, .checking, .latest, .available, .downloading, .extracting, .readyToInstall:
            EmptyView()
        }
    }

    @ViewBuilder
    private var releasesLink: some View {
        if let url = GlimpseLinks.releases {
            SettingsReleasesLink(url: url)
        }
    }

    static func headline(for reason: UpdateNoUpdateReason) -> String {
        switch reason {
        case .unknown: "No installable update was found."
        case .newerThanFeed: "You’re running a newer version."
        case .systemTooOld: "This update needs a newer macOS version."
        case .systemTooNew: "Your macOS version is newer than this update supports."
        case .requiresAppleSilicon: "This update requires Apple silicon."
        }
    }

    static func details(for guidance: UpdateNoUpdateGuidance) -> [String] {
        switch guidance.reason {
        case .unknown:
            // Check Now and View Releases sit right above; no extra copy is needed.
            []
        case .newerThanFeed:
            ["Your installed version is newer than the version in the update feed. You can keep using this version."]
        case .systemTooOld:
            (guidance.requirementVersion.map { ["Requires macOS \($0) or later."] } ?? [])
                + ["Check Software Update in System Settings, then check again."]
        case .systemTooNew:
            (guidance.requirementVersion.map { ["This update supports up to macOS \($0)."] } ?? [])
                + ["View releases for compatibility details, or check again later."]
        case .requiresAppleSilicon:
            ["It can’t be installed on this Intel Mac. View releases for compatibility details."]
        }
    }

    // MARK: - Building blocks

    enum StatusSymbol {
        case success, available, failure, information

        var name: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .available: "arrow.up.circle.fill"
            case .failure: "xmark.circle.fill"
            case .information: "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: .green
            case .available: .accentColor
            case .failure: .red
            case .information: .secondary
            }
        }
    }

    private func statusLabel(_ text: String, symbol: StatusSymbol?, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Settings.statusSpacing) {
            if let symbol {
                Image(systemName: symbol.name)
                    .foregroundStyle(symbol.color)
                    .accessibilityHidden(true)
            }
            Text(text)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(emphasized ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: AppDesign.Settings.supportingFontSize))
    }

    private func progressLabel(_ text: String) -> some View {
        HStack(spacing: AppDesign.Settings.statusSpacing) {
            // The spinner is decorative; the text names the phase for VoiceOver.
            ProgressView().controlSize(.small).accessibilityHidden(true)
            SettingsStatusText(text)
        }
    }

    private func actionButton(
        _ title: String, accessibilityLabel: String, prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(SettingsActionButtonStyle(prominent: prominent))
            .fixedSize()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityInputLabels([Text(title), Text(accessibilityLabel)])
    }
}

/// Native bordered button; the prominent variant marks the one next step.
private struct SettingsActionButtonStyle: PrimitiveButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if prominent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

/// Official release page fallback when Sparkle cannot help.
private struct SettingsReleasesLink: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsLinkButton("View Releases", accessibilityLabel: "View Glimpse releases on GitHub") {
            openURL(url)
        }
        .help(url.absoluteString)
    }
}
