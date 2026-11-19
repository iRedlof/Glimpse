import AppKit
import Sparkle
import SwiftUI
import Testing
@testable import Glimpse

/// The Settings "Updates:" row hosted at the minimum control-column width.
@MainActor
@Suite(.serialized)
struct SettingsUpdatesSectionTests {
    private static let check = "Check for updates now"
    private static let retry = "Try checking for updates again"
    private static let releases = "View Glimpse releases on GitHub"
    private static let automatic = "Check for updates automatically"

    @Test(arguments: [
        "unknown-enabled", "unknown-disabled", "newer-enabled", "newer-disabled",
        "old-none-enabled", "old-none-disabled", "old-standard-enabled", "old-standard-disabled",
        "old-long-enabled", "old-long-disabled", "new-none-enabled", "new-none-disabled",
        "new-standard-enabled", "new-standard-disabled", "new-long-enabled", "new-long-disabled",
        "silicon-enabled", "silicon-disabled"
    ], ["light", "dark"])
    func guidanceFitsTheControlColumnAndRemainsAccessible(configuration: String, appearance: String) async throws {
        let reason = String(try #require(configuration.split(separator: "-").first))
        let enabled = configuration.hasSuffix("-enabled")
        let expected = updateGuidanceExpectation(reason)
        let detail: String?
        if configuration.contains("-long-") {
            detail = "12345678901234567890123456789012"
        } else if configuration.contains("-standard-") {
            detail = reason == "old" ? "14.0" : "27.0.1"
        } else {
            detail = nil
        }
        let fixture = UpdaterFixture()
        fixture.backend.publishEligibility(enabled)
        let item = try noUpdateTestItem(
            minimum: reason == "old" ? detail : nil,
            maximum: reason == "new" ? detail : nil
        )
        var acknowledgements = 0
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: expected.sdkReason, item: item)) {
            acknowledgements += 1
        }
        let host = UpdateSectionHost(
            updater: fixture.updater,
            appearance: NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        )
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let fitting = host.fittingSize
        #expect(fitting.width.isFinite && fitting.height.isFinite)
        #expect(abs(fitting.width - UpdateSectionHost.width) < 0.5)
        #expect(host.contentBounds.height >= fitting.height - 0.5)

        var text = [expected.headline] + (expected.recovery.map { [$0] } ?? [])
        if let detail {
            text.append(reason == "old" ? "Requires macOS \(detail) or later."
                        : "This update supports up to macOS \(detail).")
        }
        if !enabled { text.append("Checking is temporarily unavailable.") }
        var measured: [UpdateAccessibilityNode] = []
        for value in text {
            let node = try #require(host.text(value), "Missing \(value)")
            measured.append(node)
        }
        let check = try #require(host.control(Self.check))
        let releases = try #require(host.control(Self.releases))
        #expect(check.accessibilityRole() == .button)
        #expect(check.isAccessibilityEnabled() == enabled)
        #expect(releases.accessibilityRole() == .link, "Link-style actions keep the native link role")
        #expect(releases.isAccessibilityEnabled())
        let automatic = try #require(host.checkbox(Self.automatic))
        #expect(automatic.isAccessibilityEnabled())
        #expect(host.controlLabels() == [Self.check, Self.releases].sorted())
        measured.append(contentsOf: [check, releases, automatic])
        let bounds = host.screenBounds.insetBy(dx: -0.5, dy: -0.5)
        for node in measured {
            let rect = node.accessibilityFrame()
            #expect(rect.origin.x.isFinite && rect.origin.y.isFinite)
            #expect(rect.width > 0 && rect.height > 0)
            #expect(bounds.contains(rect), "\(node.accessibilityLabel() ?? "") \(rect) outside \(bounds)")
        }
        for (index, node) in measured.enumerated() {
            for other in measured.dropFirst(index + 1) {
                let overlap = node.accessibilityFrame().intersection(other.accessibilityFrame())
                #expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5)
            }
        }
        #expect(acknowledgements == 1)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
        #expect(fixture.delay.requests.isEmpty)
        try host.saveRender(named: "guidance-\(configuration)-\(appearance)")
    }

    @Test(arguments: ["unknown", "newer", "old", "new", "silicon"], [false, true])
    func noUpdateGuidanceHasExactCopyAndActions(reason: String, hasDetail: Bool) async throws {
        let expected = updateGuidanceExpectation(reason)
        let fixture = UpdaterFixture()
        let item = hasDetail ? try noUpdateTestItem(minimum: "14.0", maximum: "27.0.1") : nil
        var acknowledgements = 0
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: expected.sdkReason, item: item)) {
            acknowledgements += 1
        }
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()

        #expect(host.containsText(expected.headline))
        if let recovery = expected.recovery { #expect(host.containsText(recovery)) }
        #expect(!host.containsText("Check again or view Glimpse releases on GitHub."))
        #expect(host.containsText("Requires macOS 14.0 or later.") == (hasDetail && reason == "old"))
        #expect(host.containsText("This update supports up to macOS 27.0.1.") == (hasDetail && reason == "new"))
        #expect(!host.elements().contains { ($0.accessibilityValue() as? String)?.hasPrefix("Up to date") == true })
        #expect(host.controlLabels() == [Self.check, Self.releases].sorted())
        #expect(host.control(Self.check)?.isAccessibilityEnabled() == true)
        #expect(host.control(Self.releases)?.isAccessibilityEnabled() == true)
        #expect(acknowledgements == 1)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
        #expect(fixture.delay.requests.isEmpty)
    }

    @Test
    func latestShowsUpToDateTimeAndKeepsItAfterDismissal() async throws {
        let fixture = UpdaterFixture()
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: .onLatestVersion), acknowledgement: {})
        let request = await fixture.delay.waitForRequest(0)
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let upToDate = UpdateCheckTimeText.upToDate(checkedAt: updateFixtureNow, now: updateFixtureNow)
        #expect(host.containsText(upToDate))
        #expect(host.control(Self.check)?.isAccessibilityEnabled() == true, "Check Now stays available")
        #expect(host.control(Self.releases) == nil)
        #expect(request.duration == .seconds(5))
        fixture.delay.resumeSuccessfully(request.id)
        _ = await fixture.delay.waitForReturn(request.id)
        await host.settle()
        #expect(fixture.driver.status == .idle)
        #expect(host.containsText(upToDate), "The idle row keeps this session's result")
        #expect(host.control(Self.check)?.isAccessibilityEnabled() == true)
        #expect(fixture.backend.checkCount == 0)
    }

    @Test(arguments: [false, true])
    func idleShowsSparklesLastCheckWithoutClaimingUpToDate(hasDate: Bool) async throws {
        let earlier = updateFixtureNow.addingTimeInterval(-3 * 86_400)
        let fixture = UpdaterFixture(lastCheckDate: hasDate ? earlier : nil)
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let lastChecked = UpdateCheckTimeText.lastChecked(earlier, now: updateFixtureNow)
        #expect(host.containsText(lastChecked) == hasDate)
        #expect(!host.elements().contains { ($0.accessibilityValue() as? String)?.hasPrefix("Up to date") == true })
        #expect(host.controlLabels() == [Self.check])
    }

    @Test
    func guidanceEligibilityRefreshesAndPressRevalidates() async throws {
        let fixture = UpdaterFixture()
        fixture.backend.publishEligibility(false)
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: .unknown), acknowledgement: {})
        let guidance = fixture.driver.status
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let disabled = try #require(host.control(Self.check))
        #expect(!disabled.isAccessibilityEnabled())
        #expect(host.containsText("Checking is temporarily unavailable."))
        #expect(host.control(Self.releases)?.isAccessibilityEnabled() == true)
        _ = disabled.accessibilityPerformPress()
        #expect(fixture.backend.checkCount == 0)

        fixture.backend.publishEligibility(true)
        await host.settle()
        let stale = try #require(host.control(Self.check))
        #expect(stale.isAccessibilityEnabled())
        #expect(!host.containsText("Checking is temporarily unavailable."))
        fixture.backend.canCheck = false
        #expect(stale.accessibilityPerformPress())
        await host.settle()
        #expect(fixture.backend.checkCount == 0)
        #expect(fixture.driver.status == guidance)
        #expect(host.containsText("Checking is temporarily unavailable."))

        fixture.backend.publishEligibility(true)
        await host.settle()
        let admitted = try #require(host.control(Self.check))
        #expect(admitted.accessibilityPerformPress())
        _ = admitted.accessibilityPerformPress()
        await host.settle()
        #expect(fixture.backend.checkCount == 1)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.driver.status == .checking)
        #expect(!host.containsText("No installable update was found."))
        #expect(host.containsText("Checking…"))
        #expect(host.control(Self.check)?.isAccessibilityEnabled() == false, "Check Now is disabled while checking")
    }

    @Test(arguments: ["offer", "ready", "none"])
    func guidanceReopenAndReleaseLinkPreserveDriverOwnership(pending: String) async throws {
        let fixture = UpdaterFixture()
        var replies: [SPUUserUpdateChoice] = []
        if pending == "offer" { fixture.driver.presentUpdate(version: "new") { replies.append($0) } }
        if pending == "ready" { fixture.driver.showReady { replies.append($0) } }
        let offerID = fixture.driver.updateChoiceID
        let installID = fixture.driver.installChoiceID
        var acknowledgements = 0
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: .systemIsTooOld)) {
            acknowledgements += 1
        }
        let guidance = fixture.driver.status
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        host.reopen()
        await host.settle()
        #expect(host.containsText("This update needs a newer macOS version."))
        #expect(host.control(Self.check)?.isAccessibilityEnabled() == (pending == "none"))
        let link = try #require(host.control(Self.releases))
        #expect(link.isAccessibilityEnabled())
        #expect(link.accessibilityPerformPress())
        await host.settle()
        #expect(host.links.urls.map(\.absoluteString) == ["https://github.com/iRedlof/Glimpse/releases/latest"])
        #expect(fixture.driver.status == guidance)
        #expect(fixture.driver.updateChoiceID == offerID)
        #expect(fixture.driver.installChoiceID == installID)
        #expect(replies.isEmpty)
        #expect(acknowledgements == 1)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
        #expect(fixture.delay.requests.isEmpty)
    }

    @Test
    func checkNowStartsTheInjectedCheck() async throws {
        let fixture = UpdaterFixture()
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let control = try #require(host.control(Self.check))
        #expect(control.isAccessibilityEnabled())
        #expect(control.accessibilityPerformPress())
        await host.settle()
        #expect(fixture.backend.checkCount == 1)
        #expect(fixture.driver.status == .checking)
        #expect(host.containsText("Checking…"))
    }

    @Test(arguments: [false, true])
    func automaticCheckboxReflectsAndWritesSparkle(initial: Bool) async throws {
        let fixture = UpdaterFixture(automaticChecks: initial)
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let checkbox = try #require(host.checkbox(Self.automatic))
        #expect(checkbox.isAccessibilityEnabled())
        #expect((checkbox.accessibilityValue() as? NSNumber)?.boolValue == initial)
        #expect(checkbox.accessibilityPerformPress())
        await host.settle()
        #expect(fixture.backend.automaticCheckWrites == [!initial])
        #expect((host.checkbox(Self.automatic)?.accessibilityValue() as? NSNumber)?.boolValue == !initial)
        #expect(fixture.backend.checkCount == 0, "Changing the preference never starts a check")
    }

    @Test
    func failureReopenRetainsFallbackWithoutStartingAgain() async throws {
        let fixture = UpdaterFixture(startError: updateTestError)
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        #expect(host.containsText("Updates are unavailable."))
        #expect(host.control(Self.releases) != nil)
        host.reopen()
        await host.settle()
        #expect(host.containsText("Updates are unavailable."))
        #expect(host.containsText("Get the latest Glimpse release from GitHub."))
        #expect(host.controlLabels() == [Self.releases])
        let checkbox = try #require(host.checkbox(Self.automatic))
        #expect(!checkbox.isAccessibilityEnabled(), "Sparkle owns the preference; it can't change without it")
        _ = checkbox.accessibilityPerformPress()
        await host.settle()
        #expect(fixture.backend.automaticCheckWrites.isEmpty)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
    }

    @Test
    func retryBindingRefreshesInPlace() async throws {
        let fixture = UpdaterFixture()
        fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        fixture.backend.publishEligibility(false)
        fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        #expect(host.containsText("Couldn’t check for updates."))
        let disabledRetry = try #require(host.control(Self.retry))
        #expect(disabledRetry.accessibilityRole() == .button)
        #expect(!disabledRetry.isAccessibilityEnabled())
        #expect(host.containsText("Trying again is temporarily unavailable."))
        _ = disabledRetry.accessibilityPerformPress()
        await host.settle()
        #expect(fixture.backend.checkCount == 0)
        fixture.backend.publishEligibility(true)
        await host.settle()
        let retry = try #require(host.control(Self.retry))
        #expect(retry.isAccessibilityEnabled())
        #expect(!host.containsText("Trying again is temporarily unavailable."))
        #expect(retry.accessibilityPerformPress())
        _ = retry.accessibilityPerformPress()
        await host.settle()
        #expect(fixture.backend.checkCount == 1)
        #expect(fixture.driver.status == .checking)
    }

    @Test(arguments: ["install", "skip", "relaunch"])
    func sectionChoiceInvokesMatchingDriverAction(choice: String) async throws {
        let fixture = UpdaterFixture()
        var received: [SPUUserUpdateChoice] = []
        var replacement: [SPUUserUpdateChoice] = []
        if choice == "relaunch" {
            fixture.driver.showReady { received.append($0) }
        } else {
            fixture.driver.presentUpdate(version: "A") {
                received.append($0)
                if choice == "install" {
                    fixture.driver.presentUpdate(version: "B") { replacement.append($0) }
                }
            }
        }
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        host.reopen()
        await host.settle()
        #expect(received.isEmpty)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
        let label = choice == "relaunch" ? "Install update and relaunch Glimpse"
            : choice == "skip" ? "Skip version A" : "Update to version A"
        let action = try #require(host.control(label))
        #expect(action.accessibilityRole() == (choice == "skip" ? .link : .button))
        #expect(action.isAccessibilityEnabled())
        #expect(action.accessibilityPerformPress())
        await host.settle()
        #expect(received == (choice == "skip" ? [.skip] : [.install]))
        if choice == "install" {
            let newAction = try #require(host.control("Update to version B"))
            #expect(fixture.driver.updateChoiceID != nil)
            #expect(newAction.accessibilityPerformPress())
            await host.settle()
            #expect(replacement == [.install])
            #expect(fixture.driver.updateChoiceID == nil)
        } else {
            #expect(fixture.driver.updateChoiceID == nil)
            #expect(fixture.driver.installChoiceID == nil)
        }
    }

    @Test(arguments: ["initialization", "check", "update"])
    func releaseLinkUsesOfficialDestination(failure: String) async throws {
        let fixture = UpdaterFixture(startError: failure == "initialization" ? updateTestError : nil)
        if failure == "check" { fixture.driver.showUserInitiatedUpdateCheck(cancellation: {}) }
        if failure != "initialization" {
            fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        }
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let link = try #require(host.control(Self.releases))
        #expect(link.accessibilityPerformPress())
        await host.settle()
        #expect(host.links.urls.map(\.absoluteString) == [
            "https://github.com/iRedlof/Glimpse/releases/latest"
        ])
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
    }

    /// Every `UpdateStatus` case has visible copy and exactly its valid actions.
    @Test(arguments: [
        "idle", "initialization", "checking", "latest", "no-update", "check-error", "update-error",
        "available", "downloading", "downloading-unknown", "extracting", "ready",
        "offer-consumed", "ready-consumed", "ready-unknown-version"
    ])
    func statusRenderingHasItsCopyAndOnlyItsValidActions(state: String) async throws {
        let fixture = UpdaterFixture(startError: state == "initialization" ? updateTestError : nil)
        defer { fixture.delay.drain() }
        try await prepare(state, on: fixture)
        let host = UpdateSectionHost(updater: fixture.updater)
        defer { host.close() }
        await host.settle()
        let expected = Self.expectation(for: state)
        #expect(host.controlLabels() == expected.actions.sorted(), "\(state): \(host.controlLabels())")
        let actions = host.elements().filter {
            ($0.accessibilityRole() == .button || $0.accessibilityRole() == .link)
                && expected.actions.contains($0.accessibilityLabel() ?? "")
        }
        for action in actions {
            let label = action.accessibilityLabel() ?? ""
            #expect(action.isAccessibilityEnabled() == expected.enabled.contains(label), "\(state): \(label)")
        }
        for text in expected.text {
            #expect(host.containsText(text), "\(state) must show \(text)")
        }
        #expect(host.checkbox(Self.automatic)?.isAccessibilityEnabled() == (state != "initialization"))
    }

    @Test(arguments: [
        "idle", "initialization", "checking", "latest", "no-update", "check-error", "update-error",
        "available", "downloading", "extracting", "ready"
    ], ["light", "dark"])
    func statusFitsTheControlColumn(state: String, appearance: String) async throws {
        let fixture = UpdaterFixture(startError: state == "initialization" ? updateTestError : nil)
        defer { fixture.delay.drain() }
        try await prepare(state, on: fixture)
        let host = UpdateSectionHost(
            updater: fixture.updater, appearance: NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        )
        defer { host.close() }
        await host.settle()
        #expect(abs(host.fittingSize.width - UpdateSectionHost.width) < 0.5)
        let bounds = host.screenBounds.insetBy(dx: -0.5, dy: -0.5)
        let visible = host.elements().filter {
            [.button, .link, .checkBox, .staticText].contains($0.accessibilityRole())
        }
        #expect(!visible.isEmpty)
        for node in visible {
            let rect = node.accessibilityFrame()
            #expect(rect.width > 0 && rect.height > 0 && bounds.contains(rect),
                    "\(state): \(node.accessibilityLabel() ?? (node.accessibilityValue() as? String) ?? "") at \(rect)")
        }
        try host.saveRender(named: "status-\(state)-\(appearance)")
    }

    private struct StatusExpectation {
        var actions: [String]
        var enabled: Set<String>
        var text: [String]
    }

    private static func expectation(for state: String) -> StatusExpectation {
        let upToDate = UpdateCheckTimeText.upToDate(checkedAt: updateFixtureNow, now: updateFixtureNow)
        switch state {
        case "idle": return .init(actions: [check], enabled: [check], text: [])
        case "initialization":
            return .init(actions: [releases], enabled: [releases],
                         text: ["Updates are unavailable.", "Get the latest Glimpse release from GitHub."])
        case "checking": return .init(actions: [check], enabled: [], text: ["Checking…"])
        case "latest": return .init(actions: [check], enabled: [check], text: [upToDate])
        case "no-update":
            return .init(actions: [check, releases], enabled: [check, releases],
                         text: ["No installable update was found."])
        case "check-error":
            return .init(actions: [retry, releases], enabled: [retry, releases], text: ["Couldn’t check for updates."])
        case "update-error":
            return .init(actions: [retry, releases], enabled: [retry, releases],
                         text: ["The update couldn’t be completed."])
        case "available":
            return .init(actions: ["Update to version 1.5.4", "Skip version 1.5.4"],
                         enabled: ["Update to version 1.5.4", "Skip version 1.5.4"], text: ["Version 1.5.4 available"])
        case "offer-consumed":
            return .init(actions: ["Update to version 1.5.4", "Skip version 1.5.4"], enabled: [],
                         text: ["Version 1.5.4 available"])
        case "downloading": return .init(actions: [], enabled: [], text: ["Downloading… 40%"])
        case "downloading-unknown": return .init(actions: [], enabled: [], text: ["Downloading…"])
        case "extracting": return .init(actions: [], enabled: [], text: ["Installing…"])
        case "ready":
            return .init(actions: ["Install update and relaunch Glimpse"],
                         enabled: ["Install update and relaunch Glimpse"], text: ["1.5.4 is ready"])
        case "ready-consumed":
            return .init(actions: ["Install update and relaunch Glimpse"], enabled: [], text: ["1.5.4 is ready"])
        case "ready-unknown-version":
            return .init(actions: ["Install update and relaunch Glimpse"],
                         enabled: ["Install update and relaunch Glimpse"], text: ["Ready to install"])
        default:
            Issue.record("Unknown state \(state)")
            return .init(actions: [], enabled: [], text: [])
        }
    }
}

/// Drives the production driver into a named state through its Sparkle callbacks.
@MainActor
func prepare(_ state: String, on fixture: UpdaterFixture) async throws {
    switch state {
    case "idle", "initialization": break
    case "checking": fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
    case "latest":
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: .onLatestVersion), acknowledgement: {})
        _ = await fixture.delay.waitForRequest(0)
    case "no-update":
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: .unknown), acknowledgement: {})
    case "check-error":
        fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
    case "update-error": fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
    case "available", "offer-consumed":
        fixture.driver.presentUpdate(version: updateFixtureVersion) { _ in }
        if state == "offer-consumed", let id = fixture.driver.updateChoiceID {
            fixture.driver.chooseUpdate(.install, id: id)
        }
    case "downloading":
        fixture.driver.showDownloadInitiated(cancellation: {})
        fixture.driver.showDownloadDidReceiveExpectedContentLength(1_000)
        fixture.driver.showDownloadDidReceiveData(ofLength: 400)
    case "downloading-unknown": fixture.driver.showDownloadInitiated(cancellation: {})
    case "ready-unknown-version": fixture.driver.showReady { _ in }
    case "extracting": fixture.driver.showDownloadDidStartExtractingUpdate()
    case "ready", "ready-consumed":
        // The real flow: accept the offer, download, then Sparkle asks to install.
        fixture.driver.presentUpdate(version: updateFixtureVersion) { _ in }
        if let id = fixture.driver.updateChoiceID { fixture.driver.chooseUpdate(.install, id: id) }
        fixture.driver.showDownloadInitiated(cancellation: {})
        fixture.driver.showReady { _ in }
        if state == "ready-consumed", let id = fixture.driver.installChoiceID {
            fixture.driver.chooseInstallAndRelaunch(id: id)
        }
    default:
        throw NSError(domain: "GlimpseTests.UpdateState", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Unknown update state \(state)"])
    }
}

@Suite
struct UpdateCheckTimeTextTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private static let locale = Locale(identifier: "en_US")

    @Test
    func sameDayShowsTheTime() {
        let text = UpdateCheckTimeText.upToDate(
            checkedAt: updateFixtureNow, now: updateFixtureNow.addingTimeInterval(3_600),
            calendar: Self.utc, locale: Self.locale
        )
        #expect(text == "Up to date · checked 9:41\u{202F}AM" || text == "Up to date · checked 9:41 AM")
    }

    @Test
    func earlierDayShowsTheDate() {
        let text = UpdateCheckTimeText.lastChecked(
            updateFixtureNow.addingTimeInterval(-86_400), now: updateFixtureNow,
            calendar: Self.utc, locale: Self.locale
        )
        #expect(text == "Last checked Nov 17")
    }

    @Test
    func midnightBoundaryUsesTheCalendarDay() {
        // 23:59 the previous day is not "today", even one minute earlier.
        let midnight = Self.utc.startOfDay(for: updateFixtureNow)
        let text = UpdateCheckTimeText.checkedTime(
            midnight.addingTimeInterval(-60), now: midnight, calendar: Self.utc, locale: Self.locale
        )
        #expect(text == "Nov 17")
    }
}

private struct UpdateGuidanceExpectation {
    let sdkReason: SPUNoUpdateFoundReason
    let headline: String
    /// nil when the actions beside the headline are the whole recovery.
    let recovery: String?
}

private func updateGuidanceExpectation(_ reason: String) -> UpdateGuidanceExpectation {
    switch reason {
    case "newer":
        .init(sdkReason: .onNewerThanLatestVersion,
              headline: "You’re running a newer version.",
              recovery: "Your installed version is newer than the version in the update feed. You can keep using this version.")
    case "old":
        .init(sdkReason: .systemIsTooOld,
              headline: "This update needs a newer macOS version.",
              recovery: "Check Software Update in System Settings, then check again.")
    case "new":
        .init(sdkReason: .systemIsTooNew,
              headline: "Your macOS version is newer than this update supports.",
              recovery: "View releases for compatibility details, or check again later.")
    case "silicon":
        .init(sdkReason: .hardwareDoesNotSupportARM64,
              headline: "This update requires Apple silicon.",
              recovery: "It can’t be installed on this Intel Mac. View releases for compatibility details.")
    default:
        .init(sdkReason: .unknown,
              headline: "No installable update was found.",
              recovery: nil)
    }
}

@MainActor
final class UpdateLinkReceipt {
    var urls: [URL] = []
}

/// SwiftUI nodes can expose public accessibility methods without protocol conformance.
@MainActor
struct UpdateAccessibilityNode {
    let object: AnyObject

    func accessibilityRole() -> NSAccessibility.Role? { object.accessibilityRole?() }
    func accessibilityLabel() -> String? { object.accessibilityLabel?() }
    func accessibilityValue() -> Any? { object.accessibilityValue?() }
    func accessibilityChildren() -> [Any] { object.accessibilityChildren?() ?? [] }
    func accessibilityFrame() -> NSRect { object.accessibilityFrame?() ?? .zero }
    func isAccessibilityEnabled() -> Bool { object.isAccessibilityEnabled?() ?? false }
    func accessibilityPerformPress() -> Bool { object.accessibilityPerformPress?() ?? false }
}

/// Public in-process accessibility only; this window never becomes frontmost.
@MainActor
final class UpdateSectionHost: CustomTestStringConvertible {
    nonisolated var testDescription: String { "Owned Settings update section host" }
    let window: NSWindow
    let links: UpdateLinkReceipt
    private let updater: SparkleUpdater
    private let hosting: NSHostingView<AnyView>

    init(updater: SparkleUpdater, appearance: NSAppearance? = nil) {
        self.updater = updater
        let links = UpdateLinkReceipt()
        self.links = links
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 260),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        hosting = NSHostingView(rootView: Self.content(updater: updater, links: links))
        window.contentView = hosting
        let screenBounds = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        window.setFrameOrigin(NSPoint(
            x: screenBounds.minX - window.frame.width - 100,
            y: screenBounds.minY - window.frame.height - 100
        ))
        window.orderBack(nil)
    }

    func reopen() {
        hosting.rootView = Self.content(updater: updater, links: links)
    }

    func close() {
        window.contentView = nil
        window.close()
    }

    func settle(ownsKey: Bool = false) async {
        for _ in 0..<8 {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            pumpAppKitRunLoop()
            await Task.yield()
        }
        #expect(window.isKeyWindow == ownsKey)
        if ownsKey {
            #expect(NSApp.keyWindow === window && window.isVisible)
        } else {
            #expect(!window.isMainWindow)
        }
    }

    private func pumpAppKitRunLoop() {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }

    func elements() -> [UpdateAccessibilityNode] {
        var queue: [Any] = [hosting]
        var visited: Set<ObjectIdentifier> = []
        var result: [UpdateAccessibilityNode] = []
        while !queue.isEmpty {
            let object = queue.removeFirst() as AnyObject
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true
            else { continue }
            let id = ObjectIdentifier(object)
            guard visited.insert(id).inserted else { continue }
            let element = UpdateAccessibilityNode(object: object)
            result.append(element)
            queue.append(contentsOf: element.accessibilityChildren())
        }
        return result
    }

    func control(_ label: String) -> UpdateAccessibilityNode? {
        elements().first {
            $0.accessibilityLabel() == label &&
            ($0.accessibilityRole() == .button || $0.accessibilityRole() == .link)
        }
    }

    func checkbox(_ label: String) -> UpdateAccessibilityNode? {
        elements().first { $0.accessibilityLabel() == label && $0.accessibilityRole() == .checkBox }
    }

    /// Sorted labels of every button and link (the checkbox is not an action).
    func controlLabels() -> [String] {
        elements().filter {
            $0.accessibilityRole() == .button || $0.accessibilityRole() == .link
        }.compactMap { $0.accessibilityLabel() }.sorted()
    }

    func containsText(_ value: String) -> Bool {
        elements().contains {
            $0.accessibilityLabel() == value || ($0.accessibilityValue() as? String) == value
        }
    }

    func text(_ value: String) -> UpdateAccessibilityNode? {
        elements().first {
            $0.accessibilityRole() == .staticText &&
            ($0.accessibilityLabel() == value || ($0.accessibilityValue() as? String) == value)
        }
    }

    var fittingSize: NSSize { hosting.fittingSize }
    var contentBounds: NSRect { hosting.bounds }
    var screenBounds: NSRect {
        window.convertToScreen(hosting.convert(hosting.bounds, to: nil))
    }

    func saveRender(named name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["GLIMPSE_UPDATES_ARTIFACT_DIR"] else { return }
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        print("UPDATES_RENDER_DIRECTORY \(destination.path)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: destination.appendingPathComponent("\(name).png"), options: .atomic)
        let measurements: [[String: Any]] = elements().map {
            let frame = $0.accessibilityFrame()
            return [
                "role": $0.accessibilityRole()?.rawValue ?? "",
                "label": $0.accessibilityLabel() ?? "",
                "value": ($0.accessibilityValue() as? String) ?? "",
                "enabled": $0.isAccessibilityEnabled(),
                "focused": $0.object.isAccessibilityFocused?() == true,
                "frame": [frame.minX, frame.minY, frame.width, frame.height]
            ]
        }
        let receipt: [String: Any] = [
            "fitting": [fittingSize.width, fittingSize.height],
            "content": [contentBounds.width, contentBounds.height],
            "appearance": window.effectiveAppearance.name.rawValue,
            "keyWindow": window.isKeyWindow,
            "qualification": "Production Settings update section in owned hosting fixture; not an installed-app or compositor capture",
            "elements": measurements
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent("\(name).json"), options: .atomic)
        print("UPDATES_RENDER \(name) fitting=\(fittingSize) content=\(contentBounds.size)")
    }

    /// The Settings control column at the minimum window width.
    static let width = AppDesign.Settings.minimumContentSize.width - 2 * AppDesign.Settings.contentInset
        - AppDesign.Settings.labelColumnWidth - AppDesign.Settings.columnSpacing

    private static func content(updater: SparkleUpdater, links: UpdateLinkReceipt) -> AnyView {
        AnyView(
            SettingsUpdatesSection(updater: updater, now: { updateFixtureNow })
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.accessibilityEnabled, true)
                .environment(\.openURL, OpenURLAction {
                    links.urls.append($0)
                    return .handled
                })
        )
    }
}
