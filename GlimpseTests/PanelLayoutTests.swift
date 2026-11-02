import AppKit
import GlimpseCore
import SwiftUI
import Testing

@testable import Glimpse

@Suite(.serialized) @MainActor
struct PanelLayoutTests {
    @Test func fittingContentUsesNaturalHeight() {
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: 812, caretXOffset: 158)
        layout.updateContentHeight(300)
        #expect(layout.viewportHeight == 300)
        #expect(layout.totalHeight == 312)
        #expect(!layout.isOverflowing)
    }

    @Test func overflowingContentReservesCaretSpace() {
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: 812, caretXOffset: 158)
        layout.updateContentHeight(900)
        #expect(layout.naturalContentHeight == 900)
        #expect(layout.viewportHeight == 800)
        #expect(layout.totalHeight == 812)
        #expect(layout.isOverflowing)
    }

    @Test func growthAndShrinkRecomputeViewport() {
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: 312, caretXOffset: 40)
        layout.updateContentHeight(200)
        #expect(layout.totalHeight == 212)
        layout.updateContentHeight(700)
        #expect(layout.totalHeight == 312)
        #expect(layout.isOverflowing)
        layout.updateContentHeight(120)
        #expect(layout.totalHeight == 132)
        #expect(!layout.isOverflowing)
        layout.updatePlacement(maximumHeight: 13, caretXOffset: 300)
        #expect(layout.viewportHeight == 1)
    }

    @Test func invalidAndSubToleranceMeasurementsPreserveState() {
        let layout = PanelLayoutState()
        layout.updateContentHeight(300)
        layout.updatePlacement(maximumHeight: 812, caretXOffset: 80)
        for invalid: CGFloat in [.nan, .infinity, -.infinity, 0, -1] {
            layout.updateContentHeight(invalid)
        }
        for invalid: CGFloat in [.nan, .infinity, -.infinity, 0, 12.99] {
            layout.updatePlacement(maximumHeight: invalid, caretXOffset: 90)
        }
        for invalid: CGFloat in [.nan, .infinity, -.infinity, 15, 301] {
            layout.updatePlacement(maximumHeight: 600, caretXOffset: invalid)
        }
        layout.updateContentHeight(300.49)
        layout.updatePlacement(maximumHeight: 812.49, caretXOffset: 80.49)
        #expect(layout.naturalContentHeight == 300)
        #expect(layout.maximumHeight == 812)
        #expect(layout.caretXOffset == 80)
        layout.updateContentHeight(300.5)
        layout.updatePlacement(maximumHeight: 812.5, caretXOffset: 80.5)
        #expect(layout.naturalContentHeight == 300.5)
        #expect(layout.maximumHeight == 812.5)
        #expect(layout.caretXOffset == 80.5)
        layout.updatePlacement(maximumHeight: 900, caretXOffset: 80.7)
        #expect(layout.maximumHeight == 900)
        #expect(layout.caretXOffset == 80.5)
        layout.updatePlacement(maximumHeight: 900.1, caretXOffset: 100)
        #expect(layout.maximumHeight == 900)
        #expect(layout.caretXOffset == 100)
    }

    @Test func hiddenHostingMeasuresNaturalHeightAndCapsRoot() async throws {
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: 812, caretXOffset: 158)
        let fixture = HostingFixture(layout: layout) {
            Color.clear.frame(height: 900)
        }
        defer { fixture.close() }
        try await fixture.settle()
        #expect(abs(layout.naturalContentHeight - 900) < 0.5)
        #expect(layout.viewportHeight == 800)
        #expect(fixture.host.intrinsicContentSize.height <= 812.5)
        #expect(fixture.host.fittingSize.height <= 812.5)
        #expect(fixture.host.intrinsicContentSize.width == 316)
        let scrollView = try #require(firstScrollView(in: fixture.host))
        // Change only the owned fixture's native style; never a user preference.
        scrollView.scrollerStyle = .legacy
        scrollView.tile()
        try await fixture.settle()
        #expect(scrollView.contentView.bounds.width >= 300)
        print("FIXTURE legacy-scroller style=\(scrollView.scrollerStyle.rawValue) clip=\(scrollView.contentView.bounds) hasVertical=\(scrollView.hasVerticalScroller) scroller=\(scrollView.verticalScroller?.frame ?? .zero) hidden=\(scrollView.verticalScroller?.isHidden ?? true)")
        let settled = fixture.host.intrinsicContentSize
        for _ in 0..<4 {
            try await fixture.settle()
            #expect(fixture.host.intrinsicContentSize == settled)
            #expect(layout.naturalContentHeight == 900)
        }
        fixture.record("fixed-900", passes: 5)
    }

    @Test(arguments: [NSScroller.Style.legacy, .overlay])
    func normalScrollerKnobRemainsInsideRoundedViewport(style: NSScroller.Style) async throws {
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: 812, caretXOffset: 158)
        let fixture = HostingFixture(layout: layout) {
            Color.clear.frame(height: 900)
        }
        defer { fixture.close() }
        try await fixture.settle()
        let scroll = try #require(firstScrollView(in: fixture.host))
        scroll.scrollerStyle = style
        scroll.tile()
        scroll.flashScrollers()
        try await fixture.settle()
        let scroller = try #require(scroll.verticalScroller)
        // Literal production composition:316-point root,300-point centered body,
        // caret12 above viewport800. Its rounded mask stays stationary.
        let body = NSRect(x: 8, y: 12, width: 300, height: 800)
        let roundedBody = NSBezierPath(
            roundedRect: body, xRadius: AppDesign.CornerRadius.lg,
            yRadius: AppDesign.CornerRadius.lg
        )
        let document = try #require(scroll.documentView)
        for targetY: CGFloat in [0, 100] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scroll.reflectScrolledClipView(scroll.contentView)
            scroll.flashScrollers()
            try await fixture.settle()
            let knob = scroller.rect(for: .knob)
            let knobInRoot = scroller.convert(knob, to: fixture.host)
            let center = NSPoint(x: knobInRoot.midX, y: knobInRoot.midY)
            let hit = fixture.host.hitTest(center)
            let documentInRoot = document.convert(document.bounds, to: fixture.host)
            print("SCROLLER-CONTAINMENT style=\(style.rawValue) actualStyle=\(scroll.scrollerStyle.rawValue) scrollFrame=\(scroll.frame) clip=\(scroll.contentView.bounds) documentRoot=\(documentInRoot) scroller=\(scroller.frame) visible=\(scroller.visibleRect) knobRoot=\(knobInRoot) intersection=\(knobInRoot.intersection(body)) targetY=\(targetY) floatValue=\(scroller.floatValue) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
            #expect(!knob.isEmpty)
            #expect(body.contains(knobInRoot))
            #expect(roundedBody.contains(center))
            for point in [
                NSPoint(x: knobInRoot.minX, y: knobInRoot.minY),
                NSPoint(x: knobInRoot.maxX, y: knobInRoot.minY),
                NSPoint(x: knobInRoot.minX, y: knobInRoot.maxY),
                NSPoint(x: knobInRoot.maxX, y: knobInRoot.maxY)
            ] {
                #expect(roundedBody.contains(point))
            }
            #expect(hit === scroller || hit?.isDescendant(of: scroller) == true)
            #expect(abs(scroll.contentView.bounds.minY - targetY) < 0.5)
            #expect(abs(scroller.floatValue - Float(targetY / 100)) < 0.005)
            #expect(documentInRoot.minX >= body.minX)
            #expect(documentInRoot.maxX <= body.maxX)
        }
        #expect(scroll.contentView.bounds.width >= 300)
        #expect(scroll.documentView?.frame.size.width == 300)
        #expect(fixture.host.intrinsicContentSize == NSSize(width: 316, height: 812))
        #expect(fixture.host.fittingSize == NSSize(width: 316, height: 812))
        #expect(layout.naturalContentHeight == 900)
        #expect(layout.viewportHeight == 800)
    }

    @Test func wrappedContentGrowthShrinkAndPersistentChild() async throws {
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: 312, caretXOffset: 158)
        let model = TextFixtureModel()
        let fixture = HostingFixture(layout: layout) {
            WrappedFixtureContent(model: model)
        }
        defer { fixture.close() }
        try await fixture.settle()
        let shortHeight = layout.naturalContentHeight
        #expect(shortHeight < 300)
        model.text = String(repeating: "Generic wrapped fixture content grows over several lines. ", count: 80)
        try await fixture.settle()
        #expect(layout.naturalContentHeight > 300)
        #expect(layout.isOverflowing)
        #expect(fixture.host.intrinsicContentSize.height <= 312.5)
        #expect(fixture.host.fittingSize.height <= 312.5)
        #expect(model.draft == "Retained editor draft")
        #expect(model.appearances == 1)
        fixture.record("wrapped-long", passes: 1)
        model.text = "Short fixture"
        try await fixture.settle()
        #expect(abs(layout.naturalContentHeight - shortHeight) < 0.5)
        #expect(!layout.isOverflowing)
        #expect(model.draft == "Retained editor draft")
        #expect(model.appearances == 1)
        fixture.record("wrapped-short", passes: 1)
    }

    @Test func panelRefreshReanchorsWithoutReopeningAndRejectsInvalidGeometry() async throws {
        let selected = Date(timeIntervalSince1970: 1_700_000_000)
        var initial = CalendarFeature.State(displayedMonth: selected)
        initial.selectedDate = selected
        initial.showingPreferences = true
        let store = Store(initialState: initial) { CalendarFeature() } withDependencies: {
            $0.date = .constant(selected)
            $0.calendarClient = .liveValue
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { true }
            $0.eventKitClient.authorizationStatus = { .notDetermined }
        }
        let content = HeightFixtureModel()
        let panel = CalendarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 316, height: 432),
            caretOffset: 158, calendarStore: store
        ) { layout in
            AnyView(VStack(spacing: 0) {
                Color.clear.frame(height: 12)
                PanelViewport(layout: layout) { HeightFixtureContent(model: content) }
            }.frame(width: 316))
        }
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let anchor = NSRect(x: 1000, y: 876, width: 100, height: 24)
        let visible = NSRect(x: 0, y: 48, width: 1440, height: 828)
        panel.updatePlacement(statusItemFrame: anchor, visibleFrame: visible)
        try await settleHostingLayout(panel.contentView)
        #expect(panel.frame == NSRect(x: 892, y: 58, width: 316, height: 812))
        #expect(panel.layoutState.naturalContentHeight == 900)
        #expect(store.showingPreferences)
        #expect(store.selectedDate == selected)
        let shifted = NSRect(x: 1200, y: 876, width: 100, height: 24)
        panel.updatePlacement(statusItemFrame: shifted, visibleFrame: visible)
        #expect(panel.frame.origin.x == 1092)
        #expect(store.showingPreferences)
        #expect(store.selectedDate == selected)
        panel.updatePlacement(
            statusItemFrame: shifted,
            visibleFrame: NSRect(x: 0, y: 548, width: 1440, height: 328)
        )
        #expect(panel.frame == NSRect(x: 1092, y: 558, width: 316, height: 312))
        panel.updatePlacement(statusItemFrame: shifted, visibleFrame: visible)
        #expect(panel.frame == NSRect(x: 1092, y: 58, width: 316, height: 812))
        let accepted = panel.frame
        panel.updatePlacement(statusItemFrame: shifted, visibleFrame: .zero)
        #expect(panel.frame == accepted)
        #expect(panel.layoutState.maximumHeight == 812)
        content.height = 300
        try await settleHostingLayout(panel.contentView)
        #expect(panel.layoutState.naturalContentHeight == 300)
        #expect(panel.frame == NSRect(x: 1092, y: 558, width: 316, height: 312))
        content.height = 900
        try await settleHostingLayout(panel.contentView)
        #expect(panel.frame == accepted)
        for _ in 0..<4 {
            panel.resizeToFitContent()
            #expect(panel.frame == accepted)
        }
        #expect(!panel.isVisible)
        print("FIXTURE panel-refresh natural=\(panel.layoutState.naturalContentHeight) viewport=\(panel.layoutState.viewportHeight) frame=\(panel.frame) intrinsic=\(panel.contentView?.intrinsicContentSize ?? .zero) fitting=\(panel.contentView?.fittingSize ?? .zero) repeated=4 hidden=true")
        let receipt = LifecycleReceipt()
        let showObserver = NotificationCenter.default.addObserver(
            forName: .calendarPanelDidShow, object: panel, queue: nil
        ) { _ in MainActor.assumeIsolated { receipt.shows += 1 } }
        let hideObserver = NotificationCenter.default.addObserver(
            forName: .calendarPanelWillHide, object: panel, queue: nil
        ) { _ in MainActor.assumeIsolated { receipt.hides += 1 } }
        defer {
            NotificationCenter.default.removeObserver(showObserver)
            NotificationCenter.default.removeObserver(hideObserver)
        }
        panel.updatePlacement(statusItemFrame: anchor, visibleFrame: visible)
        #expect(receipt.shows == 0)
        panel.prepareForReopen()
        #expect(receipt.shows == 1)
        #expect(!store.showingPreferences)
        #expect(store.selectedDate == selected)
        panel.orderOut(nil)
        #expect(receipt.hides == 1)
    }
}

@MainActor
private final class LifecycleReceipt {
    var shows = 0
    var hides = 0
}

@MainActor @Observable
private final class HeightFixtureModel {
    var height: CGFloat = 900
}

private struct HeightFixtureContent: View {
    let model: HeightFixtureModel
    var body: some View { Color.clear.frame(height: model.height) }
}

@MainActor @Observable
private final class TextFixtureModel {
    var text = "Short fixture"
    var draft = "Retained editor draft"
    var appearances = 0
}

private struct WrappedFixtureContent: View {
    @Bindable var model: TextFixtureModel

    var body: some View {
        VStack {
            Text(model.text).font(.body)
            TextField("Fixture editor", text: $model.draft)
        }
        .onAppear { model.appearances += 1 }
    }
}

@MainActor
private final class HostingFixture {
    let layout: PanelLayoutState
    let host: NSHostingView<AnyView>
    let window: NSWindow

    init<Content: View>(
        layout: PanelLayoutState,
        @ViewBuilder content: () -> Content
    ) {
        self.layout = layout
        host = NSHostingView(rootView: AnyView(VStack(spacing: 0) {
            Color.clear.frame(height: 12)
            PanelViewport(layout: layout, content: content)
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg)
                        .fill(.regularMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg))
        }.frame(width: 316)))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 316, height: 812),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
    }

    func settle() async throws { try await settleHostingLayout(host) }
    func close() { window.close() }
    func record(_ name: String, passes: Int) {
        print("FIXTURE \(name) natural=\(layout.naturalContentHeight) viewport=\(layout.viewportHeight) intrinsic=\(host.intrinsicContentSize) fitting=\(host.fittingSize) passes=\(passes) hidden=\(!window.isVisible)")
    }
}

@MainActor
private func settleHostingLayout(_ view: NSView?) async throws {
    // Let the real hosting layout and deferred geometry callbacks complete.
    for _ in 0..<6 {
        _ = view?.fittingSize
        view?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
private func firstScrollView(in view: NSView) -> NSScrollView? {
    if let scrollView = view as? NSScrollView { return scrollView }
    for child in view.subviews {
        if let scrollView = firstScrollView(in: child) { return scrollView }
    }
    return nil
}
