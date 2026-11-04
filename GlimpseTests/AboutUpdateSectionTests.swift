import AppKit
import Sparkle
import SwiftUI
import Testing
@testable import Glimpse

@MainActor
@Suite(.serialized)
struct AboutUpdateSectionTests {
    @Test(arguments: [
        "unknown-enabled", "unknown-disabled", "newer-enabled", "newer-disabled",
        "old-none-enabled", "old-none-disabled", "old-standard-enabled", "old-standard-disabled",
        "old-long-enabled", "old-long-disabled", "new-none-enabled", "new-none-disabled",
        "new-standard-enabled", "new-standard-disabled", "new-long-enabled", "new-long-disabled",
        "silicon-enabled", "silicon-disabled"
    ], ["light", "dark"])
    func fullAboutGuidanceFitsAndRemainsAccessible(configuration: String, appearance: String) async throws {
        let reason = String(try #require(configuration.split(separator: "-").first))
        let enabled = configuration.hasSuffix("-enabled")
        let expected = aboutGuidanceExpectation(reason)
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
        let host = AboutUpdateHost(
            updater: fixture.updater, fullAbout: true,
            appearance: NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        )
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let fitting = host.fittingSize
        #expect(fitting.width.isFinite && fitting.height.isFinite)
        #expect(abs(fitting.width - 300) < 0.5)
        #expect(fitting.height > 300)
        #expect(host.contentBounds.width >= fitting.width - 0.5)
        #expect(host.contentBounds.height >= fitting.height - 0.5)

        var text = [
            "Glimpse", "A lightweight macOS menu bar calendar", "Export Diagnostics",
            "Save logs and settings to a file", "MIT License", expected.headline, expected.recovery
        ]
        if let detail {
            text.append(reason == "old" ? "Requires macOS \(detail) or later."
                        : "This update supports up to macOS \(detail).")
        }
        if !enabled { text.append("Checking is temporarily unavailable.") }
        var measured: [AboutAccessibilityNode] = []
        for value in text {
            let node = try #require(host.text(value))
            #expect(node.accessibilityRole() == .staticText)
            measured.append(node)
        }
        let version = try #require(host.elements().first {
            $0.accessibilityRole() == .staticText &&
            (($0.accessibilityValue() as? String)?.hasPrefix("Version ") == true ||
             $0.accessibilityLabel()?.hasPrefix("Version ") == true)
        })
        measured.append(version)
        let check = try #require(host.control("Check for updates"))
        let releases = try #require(host.control("View Glimpse releases on GitHub"))
        #expect(check.accessibilityRole() == .button)
        #expect(check.isAccessibilityEnabled() == enabled)
        #expect(releases.accessibilityRole() == .link)
        #expect(releases.isAccessibilityEnabled())
        let controls = host.elements().filter {
            $0.accessibilityRole() == .button || $0.accessibilityRole() == .link
        }
        #expect(controls.compactMap { $0.accessibilityLabel() }.sorted() == [
            "Check for updates", "Export", "View Glimpse releases on GitHub", "github.com/iRedlof/Glimpse"
        ])
        measured.append(contentsOf: controls)
        let bounds = host.screenBounds.insetBy(dx: -0.5, dy: -0.5)
        for node in measured {
            let rect = node.accessibilityFrame()
            #expect(rect.origin.x.isFinite && rect.origin.y.isFinite)
            #expect(rect.width.isFinite && rect.height.isFinite)
            #expect(rect.width > 0 && rect.height > 0)
            #expect(bounds.contains(rect))
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
        try host.saveRender(named: "\(configuration)-\(appearance)")
    }

    @Test(arguments: ["unknown", "newer", "old", "new", "silicon"], [false, true])
    func noUpdateGuidanceHasExactCopyAndActions(reason: String, hasDetail: Bool) async throws {
        let expected = aboutGuidanceExpectation(reason)
        let fixture = UpdaterFixture()
        let item = hasDetail ? try noUpdateTestItem(minimum: "14.0", maximum: "27.0.1") : nil
        var acknowledgements = 0
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: expected.sdkReason, item: item)) {
            acknowledgements += 1
        }
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()

        #expect(host.containsText(expected.headline))
        #expect(host.containsText(expected.recovery))
        #expect(host.containsText("Requires macOS 14.0 or later.") == (hasDetail && reason == "old"))
        #expect(host.containsText("This update supports up to macOS 27.0.1.") == (hasDetail && reason == "new"))
        #expect(!host.containsText("You're on the latest version"))
        #expect(!host.containsText("No newer update was found"))
        let controls = host.elements().filter {
            $0.accessibilityRole() == .button || $0.accessibilityRole() == .link
        }
        #expect(controls.compactMap { $0.accessibilityLabel() }.sorted() == [
            "Check for updates", "View Glimpse releases on GitHub"
        ])
        let check = try #require(host.control("Check for updates"))
        let link = try #require(host.control("View Glimpse releases on GitHub"))
        #expect(check.accessibilityRole() == .button)
        #expect(link.accessibilityRole() == .link)
        #expect(check.isAccessibilityEnabled())
        #expect(link.isAccessibilityEnabled())
        #expect(acknowledgements == 1)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
        #expect(fixture.delay.requests.isEmpty)
    }

    @Test
    func latestCopyReportsCheckOutcome() async throws {
        let fixture = UpdaterFixture()
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: .onLatestVersion), acknowledgement: {})
        let request = await fixture.delay.waitForRequest(0)
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        #expect(host.containsText("No newer update was found"))
        #expect(!host.containsText("You're on the latest version"))
        #expect(host.control("Check for updates") == nil)
        #expect(host.control("View Glimpse releases on GitHub") == nil)
        #expect(request.duration == .seconds(5))
        fixture.delay.resumeSuccessfully(request.id)
        _ = await fixture.delay.waitForReturn(request.id)
        await host.settle()
        #expect(!host.containsText("No newer update was found"))
        #expect(host.control("Check for updates")?.isAccessibilityEnabled() == true)
        #expect(fixture.backend.checkCount == 0)
    }

    @Test
    func guidanceEligibilityRefreshesAndPressRevalidates() async throws {
        let fixture = UpdaterFixture()
        fixture.backend.publishEligibility(false)
        fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: .unknown), acknowledgement: {})
        let guidance = fixture.driver.status
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let disabled = try #require(host.control("Check for updates"))
        #expect(!disabled.isAccessibilityEnabled())
        #expect(host.containsText("Checking is temporarily unavailable."))
        #expect(host.control("View Glimpse releases on GitHub")?.isAccessibilityEnabled() == true)
        _ = disabled.accessibilityPerformPress()
        #expect(fixture.backend.checkCount == 0)

        fixture.backend.publishEligibility(true)
        await host.settle()
        let stale = try #require(host.control("Check for updates"))
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
        let admitted = try #require(host.control("Check for updates"))
        #expect(admitted.accessibilityPerformPress())
        _ = admitted.accessibilityPerformPress()
        await host.settle()
        #expect(fixture.backend.checkCount == 1)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.driver.status == .checking)
        #expect(!host.containsText("No installable update was found."))
        #expect(host.control("Check for updates") == nil)
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
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        host.reopen()
        await host.settle()
        #expect(host.containsText("This update needs a newer macOS version."))
        #expect(host.control("Check for updates")?.isAccessibilityEnabled() == (pending == "none"))
        let link = try #require(host.control("View Glimpse releases on GitHub"))
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
    func idleControlStartsTheInjectedCheck() async throws {
        let fixture = UpdaterFixture()
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let control = try #require(host.elements().first { $0.accessibilityRole() == .button })
        #expect(control.isAccessibilityEnabled())
        #expect(control.accessibilityPerformPress())
        await host.settle()
        #expect(fixture.backend.checkCount == 1)
        #expect(fixture.driver.status == .checking)
    }

    @Test
    func failureReopenRetainsFallbackWithoutStartingAgain() async throws {
        let fixture = UpdaterFixture(startError: updateTestError)
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        #expect(host.containsText("Updates are unavailable."))
        #expect(host.control("View Glimpse releases on GitHub") != nil)
        host.reopen()
        await host.settle()
        #expect(host.containsText("Updates are unavailable."))
        #expect(host.containsText("Get the latest Glimpse release from GitHub."))
        let link = try #require(host.control("View Glimpse releases on GitHub"))
        #expect(link.accessibilityRole() == .link)
        #expect(host.control("Check for updates") == nil)
        #expect(host.control("Retry checking for updates") == nil)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
    }

    @Test
    func retryBindingRefreshesInPlace() async throws {
        let fixture = UpdaterFixture()
        fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        fixture.backend.publishEligibility(false)
        fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let disabledRetry = try #require(host.control("Retry checking for updates"))
        #expect(disabledRetry.accessibilityRole() == .button)
        #expect(!disabledRetry.isAccessibilityEnabled())
        #expect(host.containsText("Retry is temporarily unavailable."))
        _ = disabledRetry.accessibilityPerformPress()
        await host.settle()
        #expect(fixture.backend.checkCount == 0)
        fixture.backend.publishEligibility(true)
        await host.settle()
        let retry = try #require(host.control("Retry checking for updates"))
        #expect(retry.isAccessibilityEnabled())
        #expect(!host.containsText("Retry is temporarily unavailable."))
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
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        host.reopen()
        await host.settle()
        #expect(received.isEmpty)
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
        let label = choice == "relaunch" ? "Install update and relaunch Glimpse"
            : choice == "skip" ? "Skip this update" : "Install update"
        let action = try #require(host.control(label))
        #expect(action.accessibilityRole() == .button)
        #expect(action.isAccessibilityEnabled())
        #expect(action.accessibilityPerformPress())
        await host.settle()
        #expect(received == (choice == "skip" ? [.skip] : [.install]))
        if choice == "install" {
            let newAction = try #require(host.control("Install update"))
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
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close(); fixture.delay.drain() }
        await host.settle()
        let link = try #require(host.control("View Glimpse releases on GitHub"))
        #expect(link.accessibilityRole() == .link)
        #expect(link.accessibilityPerformPress())
        await host.settle()
        #expect(host.links.urls.map(\.absoluteString) == [
            "https://github.com/iRedlof/Glimpse/releases/latest"
        ])
        #expect(fixture.backend.startCount == 1)
        #expect(fixture.backend.checkCount == 0)
    }

    @Test(arguments: [
        "idle", "initialization", "checking", "latest", "check-error", "update-error",
        "available", "downloading", "extracting", "ready", "offer-consumed", "ready-consumed"
    ])
    func statusRenderingHasOnlyItsValidActions(state: String) async {
        let fixture = UpdaterFixture(startError: state == "initialization" ? updateTestError : nil)
        defer { fixture.delay.drain() }
        switch state {
        case "checking": fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
        case "latest":
            fixture.driver.showUpdateNotFoundWithError(noUpdateTestError(reason: .onLatestVersion), acknowledgement: {})
            _ = await fixture.delay.waitForRequest(0)
        case "check-error":
            fixture.driver.showUserInitiatedUpdateCheck(cancellation: {})
            fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        case "update-error": fixture.driver.showUpdaterError(updateTestError, acknowledgement: {})
        case "available", "offer-consumed":
            fixture.driver.presentUpdate(version: "B") { _ in }
            if state == "offer-consumed", let id = fixture.driver.updateChoiceID {
                fixture.driver.chooseUpdate(.install, id: id)
            }
        case "downloading": fixture.driver.showDownloadInitiated(cancellation: {})
        case "extracting": fixture.driver.showDownloadDidStartExtractingUpdate()
        case "ready", "ready-consumed":
            fixture.driver.showReady { _ in }
            if state == "ready-consumed", let id = fixture.driver.installChoiceID {
                fixture.driver.chooseInstallAndRelaunch(id: id)
            }
        default: break
        }
        let host = AboutUpdateHost(updater: fixture.updater)
        defer { host.close() }
        await host.settle()
        let expected: [String]
        switch state {
        case "idle": expected = ["Check for updates"]
        case "initialization": expected = ["View Glimpse releases on GitHub"]
        case "check-error": expected = ["Retry checking for updates", "View Glimpse releases on GitHub"]
        case "update-error": expected = ["Check for updates", "View Glimpse releases on GitHub"]
        case "available", "offer-consumed": expected = ["Install update", "Skip this update"]
        case "ready", "ready-consumed": expected = ["Install update and relaunch Glimpse"]
        default: expected = []
        }
        let actual = host.elements().filter {
            $0.accessibilityRole() == .button || $0.accessibilityRole() == .link
        }
        #expect(actual.compactMap { $0.accessibilityLabel() }.sorted() == expected.sorted())
        let enabled = state != "offer-consumed" && state != "ready-consumed"
        #expect(actual.allSatisfy { $0.isAccessibilityEnabled() == enabled })
    }
}

private struct AboutGuidanceExpectation {
    let sdkReason: SPUNoUpdateFoundReason
    let headline: String
    let recovery: String
}

private func aboutGuidanceExpectation(_ reason: String) -> AboutGuidanceExpectation {
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
              recovery: "Check again or view Glimpse releases on GitHub.")
    }
}

@MainActor
final class AboutLinkReceipt {
    var urls: [URL] = []
}

/// SwiftUI nodes can expose public accessibility methods without protocol conformance.
@MainActor
struct AboutAccessibilityNode {
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
final class AboutUpdateHost: CustomTestStringConvertible {
    nonisolated var testDescription: String { "Owned About update host" }
    let window: NSWindow
    let links: AboutLinkReceipt
    private let updater: SparkleUpdater
    private let hosting: NSHostingView<AnyView>
    private let fullAbout: Bool

    init(updater: SparkleUpdater, fullAbout: Bool = false, appearance: NSAppearance? = nil) {
        self.updater = updater
        self.fullAbout = fullAbout
        let links = AboutLinkReceipt()
        self.links = links
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        hosting = NSHostingView(rootView: Self.content(updater: updater, links: links, fullAbout: fullAbout))
        window.contentView = hosting
        let screenBounds = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        window.setFrameOrigin(NSPoint(
            x: screenBounds.minX - window.frame.width - 100,
            y: screenBounds.minY - window.frame.height - 100
        ))
        window.orderBack(nil)
    }

    func reopen() {
        hosting.rootView = Self.content(updater: updater, links: links, fullAbout: fullAbout)
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

    func elements() -> [AboutAccessibilityNode] {
        var queue: [Any] = [hosting]
        var visited: Set<ObjectIdentifier> = []
        var result: [AboutAccessibilityNode] = []
        while !queue.isEmpty {
            let object = queue.removeFirst() as AnyObject
            guard object.responds?(to: #selector(NSAccessibilityProtocol.accessibilityRole)) == true
            else { continue }
            let id = ObjectIdentifier(object)
            guard visited.insert(id).inserted else { continue }
            let element = AboutAccessibilityNode(object: object)
            result.append(element)
            queue.append(contentsOf: element.accessibilityChildren())
        }
        return result
    }

    func control(_ label: String) -> AboutAccessibilityNode? {
        elements().first {
            $0.accessibilityLabel() == label &&
            ($0.accessibilityRole() == .button || $0.accessibilityRole() == .link)
        }
    }

    func containsText(_ value: String) -> Bool {
        elements().contains {
            $0.accessibilityLabel() == value || ($0.accessibilityValue() as? String) == value
        }
    }

    func text(_ value: String) -> AboutAccessibilityNode? {
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
        let environment = ProcessInfo.processInfo.environment
        let destination: URL
        if let path = environment["GLIMPSE_ABOUT_ARTIFACT_DIR"] {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        } else if let token = environment["GLIMPSE_UPD03_RENDER_TOKEN"] {
            destination = FileManager.default.temporaryDirectory.appendingPathComponent(token, isDirectory: true)
        } else {
            return
        }
        print("UPD03_RENDER_DIRECTORY \(destination.path)")
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
            "qualification": "Production About view in owned hosting fixture; not an installed-app or compositor capture",
            "elements": measurements
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent("\(name).json"), options: .atomic)
        print("UPD03_RENDER \(name) fitting=\(fittingSize) content=\(contentBounds.size)")
    }

    private static func content(updater: SparkleUpdater, links: AboutLinkReceipt, fullAbout: Bool) -> AnyView {
        let view: AnyView = fullAbout
            ? AnyView(AboutView(updater: updater))
            : AnyView(AboutUpdateSection(updater: updater, appVersion: "fixture").frame(width: 260))
        return AnyView(
            view
                .environment(\.accessibilityEnabled, true)
                .environment(\.openURL, OpenURLAction {
                    links.urls.append($0)
                    return .handled
                })
        )
    }
}
