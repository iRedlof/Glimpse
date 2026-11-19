import Foundation
import Testing
@testable import Glimpse

/// Native seams for the Diagnostics… flow; no save panel, file or Finder is touched.
@MainActor
final class DiagnosticsExportFixture {
    var suggestedNames: [String] = []
    var completions: [@MainActor (URL?) -> Void] = []
    var exportRequests: [URL] = []
    var revealed: [URL] = []
    var exportError: Error?
    private var pendingExport: CheckedContinuation<Void, Never>?
    private var exportWaiters: [CheckedContinuation<Void, Never>] = []
    let model: DiagnosticsExportModel

    init() {
        weak var weakSelf: DiagnosticsExportFixture?
        model = DiagnosticsExportModel(environment: .init(
            chooseDestination: { name, completion in
                weakSelf?.suggestedNames.append(name)
                weakSelf?.completions.append(completion)
            },
            export: { url in
                guard let fixture = weakSelf else { return url }
                fixture.exportRequests.append(url)
                fixture.exportWaiters.forEach { $0.resume() }
                fixture.exportWaiters.removeAll()
                await withCheckedContinuation { fixture.pendingExport = $0 }
                if let error = fixture.exportError { throw error }
                return url
            },
            reveal: { weakSelf?.revealed.append($0) },
            now: { updateFixtureNow }
        ))
        weakSelf = self
    }

    func waitForExportRequest() async {
        guard exportRequests.isEmpty else { return }
        await withCheckedContinuation { exportWaiters.append($0) }
    }

    func finishExport() async {
        pendingExport?.resume()
        pendingExport = nil
        for _ in 0..<5 { await Task.yield() }
    }
}

@MainActor
struct DiagnosticsExportModelTests {
    private let destination = URL(fileURLWithPath: "/tmp/Glimpse-Diagnostics-test.txt")

    @Test
    func cancelledDestinationReturnsToIdleWithoutExporting() async {
        let fixture = DiagnosticsExportFixture()
        fixture.model.begin()
        #expect(fixture.model.state == .choosingDestination)
        #expect(fixture.suggestedNames == [DiagnosticsExportModel.suggestedFileName(at: updateFixtureNow)])
        fixture.completions.first?(nil)
        #expect(fixture.model.state == .idle)
        #expect(fixture.exportRequests.isEmpty)
    }

    @Test
    func chosenDestinationExportsThenRevealsInFinder() async {
        let fixture = DiagnosticsExportFixture()
        fixture.model.begin()
        fixture.completions.first?(destination)
        #expect(fixture.model.state == .exporting)
        await fixture.waitForExportRequest()
        #expect(fixture.exportRequests == [destination])
        await fixture.finishExport()
        #expect(fixture.model.state == .exported(destination))
        fixture.model.revealExport()
        #expect(fixture.revealed == [destination])
    }

    @Test
    func failureShowsTheMessageAndAllowsTryAgain() async {
        let fixture = DiagnosticsExportFixture()
        fixture.exportError = NSError(domain: "GlimpseTests.Diagnostics", code: 7,
                                      userInfo: [NSLocalizedDescriptionKey: "Disk full"])
        fixture.model.begin()
        fixture.completions.first?(destination)
        await fixture.waitForExportRequest()
        await fixture.finishExport()
        #expect(fixture.model.state == .failed("Disk full"))
        #expect(fixture.model.canBegin)
        fixture.model.revealExport()
        #expect(fixture.revealed.isEmpty, "Nothing to reveal after a failure")
        fixture.model.begin()
        #expect(fixture.model.state == .choosingDestination)
        #expect(fixture.completions.count == 2)
    }

    @Test
    func reentryIsRefusedWhileChoosingOrExporting() async {
        let fixture = DiagnosticsExportFixture()
        fixture.model.begin()
        fixture.model.begin()
        #expect(fixture.completions.count == 1)
        #expect(!fixture.model.canBegin)
        fixture.completions.first?(destination)
        fixture.model.begin()
        #expect(fixture.completions.count == 1)
        await fixture.waitForExportRequest()
        await fixture.finishExport()
        #expect(fixture.model.canBegin)
    }

    @Test
    func aRepeatedPanelCompletionCannotStartASecondExport() async {
        let fixture = DiagnosticsExportFixture()
        fixture.model.begin()
        let completion = fixture.completions.first
        completion?(destination)
        completion?(URL(fileURLWithPath: "/tmp/other.txt"))
        completion?(nil)
        #expect(fixture.model.state == .exporting)
        await fixture.waitForExportRequest()
        await fixture.finishExport()
        #expect(fixture.exportRequests == [destination])
        #expect(fixture.model.state == .exported(destination))
    }

    @Test
    func suggestedNameUsesTheLocalTimeWithoutColons() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(DiagnosticsExportModel.suggestedFileName(at: updateFixtureNow, timeZone: utc)
                == "Glimpse-Diagnostics-2026-11-18T09-41-00Z.txt")
        let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(DiagnosticsExportModel.suggestedFileName(at: updateFixtureNow, timeZone: pacific)
                == "Glimpse-Diagnostics-2026-11-18T01-41-00-0800.txt")
    }
}

@Suite
struct GlimpseLinksTests {
    @Test
    func settingsLinksUseOfficialDestinations() {
        #expect(GlimpseLinks.website?.absoluteString == "https://github.com/iRedlof/Glimpse")
        #expect(GlimpseLinks.support?.absoluteString == "https://github.com/iRedlof/Glimpse/issues")
        #expect(GlimpseLinks.releases?.absoluteString == "https://github.com/iRedlof/Glimpse/releases/latest")
    }
}
