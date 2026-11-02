import AppKit
import Sparkle
import SwiftUI
import Testing
@testable import Glimpse

@MainActor
struct AboutUpdateSectionTests {
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
            fixture.driver.showUpdateNotFoundWithError(updateTestError, acknowledgement: {})
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

    init(updater: SparkleUpdater) {
        self.updater = updater
        let links = AboutLinkReceipt()
        self.links = links
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
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
        window.close()
    }

    func settle() async {
        for _ in 0..<8 {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            pumpAppKitRunLoop()
            await Task.yield()
        }
        #expect(!window.isKeyWindow)
        #expect(!window.isMainWindow)
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

    private static func content(updater: SparkleUpdater, links: AboutLinkReceipt) -> AnyView {
        AnyView(
            AboutUpdateSection(updater: updater, appVersion: "fixture")
                .frame(width: 260)
                .environment(\.accessibilityEnabled, true)
                .environment(\.openURL, OpenURLAction {
                    links.urls.append($0)
                    return .handled
                })
        )
    }
}
