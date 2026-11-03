import AppKit
import GlimpseCore
import SwiftUI
import Testing

@testable import Glimpse

@Suite(.serialized) @MainActor
struct AccessibilityViewportTests {
    @Test(arguments: [CGFloat(812), 312], [
        (false, NSScroller.Style.legacy), (false, .overlay),
        (true, .legacy), (true, .overlay)
    ])
    func dateSearchTargetsRemainReachableAndCollapseInPersistentViewport(
        maximumHeight: CGFloat, presentation: (Bool, NSScroller.Style)
    ) async throws {
        let (processing, style) = presentation
        var state = PreferencesFeature.State()
        state.startOfWeekday = 2
        state.aiProvider = .proxy
        let preferences = PreferencesAccessibilityFixture(state: state)
        let controls = CalendarControlFixture(togglePresentationOnAction: false)
        controls.showingPreferences = true
        let search = DateSearchFixture()
        let query = String(repeating: "synthetic next Friday ", count: 20)
        let error = String(repeating: "Synthetic date search error. ", count: 12)
        search.query = query
        search.error = error
        search.isProcessing = processing
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 158)
        let host = AccessibilityTestHost(width: 316, height: maximumHeight) {
            AccessibilityViewportContent(
                layout: layout, controls: controls,
                preferences: preferences, dateSearch: search
            )
        }
        defer { host.close(); preferences.close() }
        try await host.settle()
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        let scroll = try #require(accessibilityScrollView(in: host.hosting))
        let document = try #require(scroll.documentView)
        try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
        if processing {
            #expect(host.controls(named: "Close date search").isEmpty)
            #expect(search.query == query && search.error == error && search.isActive)
            #expect(search.submissions == 0)
            search.isProcessing = false
            try await host.settle()
        }
        for position in IconClickPosition.allCases {
            search.query = query
            search.error = error
            search.isActive = true
            try await host.settle()
            try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
            let beforeScroll = try host.control(named: "Close date search")
            _ = document.scrollToVisible(host.rect(beforeScroll.frame, in: document)
                .insetBy(dx: -16, dy: -16))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await host.settle()
            let dismiss = try host.control(named: "Close date search")
            let editor = try #require(host.elements().first { $0.role == .textField })
            expectDateSearchTarget(dismiss.frame)
            let body = viewportBodyScreenRect(host: host, scroll: scroll, layout: layout)
            let clip = host.window.convertToScreen(
                scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            )
            #expect(body.contains(dismiss.frame) && clip.contains(dismiss.frame))
            #expect(!editor.frame.intersects(dismiss.frame))
            if style == .legacy, let scroller = scroll.verticalScroller, !scroller.isHidden {
                let scrollerFrame = host.window.convertToScreen(
                    scroller.convert(scroller.bounds, to: nil)
                )
                #expect(!dismiss.frame.intersects(scrollerFrame))
            }
            try await host.click(atScreenPoint: position.point(in: dismiss.frame))
            #expect(search.query.isEmpty && search.error == nil && !search.isActive)
            #expect(!search.isProcessing && search.submissions == 0)
            #expect(host.window.isVisible)
            #expect(controls.receipts.isEmpty && !controls.isPinned)
            #expect(controls.showingPreferences)
            #expect(preferences.store.startOfWeekday == 2)
            #expect(preferences.store.aiProvider == .proxy)
            #expect(preferences.receipts.value.forbidden == 0)
            #expect(preferences.hotkey.backend.operations.isEmpty)
            #expect(preferences.receipts.value.displaySaves.isEmpty)
            #expect(preferences.receipts.value.weekdaySaves.isEmpty)
            #expect(preferences.receipts.value.providerSaves.isEmpty)
            try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
            #expect(scroll.documentView === document)
            let height = layout.naturalContentHeight
            let size = host.hosting.intrinsicContentSize
            for _ in 0..<4 {
                try await host.settle()
                #expect(layout.naturalContentHeight == height)
                #expect(host.hosting.intrinsicContentSize == size)
            }
            #expect(abs(size.width - 316) < 0.5)
            #expect(size.height <= maximumHeight + 0.5)
            #expect(abs(host.hosting.fittingSize.width - 316) < 0.5)
            #expect(host.hosting.fittingSize.height <= maximumHeight + 0.5)
            #expect(scroll.scrollerStyle == style)
            #expect(scroll.contentView.bounds.width >= 300)
        }
    }

    @Test(arguments: [CGFloat(812), 312], [
        (false, NSScroller.Style.legacy), (false, .overlay),
        (true, .legacy), (true, .overlay)
    ])
    func targetsFitAndRemainReachableInPersistentViewport(
        maximumHeight: CGFloat, presentation: (Bool, NSScroller.Style)
    ) async throws {
        let (preferencesOpen, style) = presentation
        var state = PreferencesFeature.State()
        state.startOfWeekday = 2
        state.aiProvider = .proxy
        let preferences = PreferencesAccessibilityFixture(state: state)
        let controls = CalendarControlFixture(togglePresentationOnAction: false)
        controls.showingPreferences = preferencesOpen
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 158)
        let host = AccessibilityTestHost(width: 316, height: maximumHeight) {
            AccessibilityViewportContent(
                layout: layout, controls: controls, preferences: preferences
            )
        }
        defer { host.close(); preferences.close() }
        try await host.settle()
        let scroll = try #require(accessibilityScrollView(in: host.hosting))
        let document = try #require(scroll.documentView)
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
        var documentFrames: [CalendarControlAction: NSRect] = [:]
        for row in [CalendarControlAction.header, CalendarControlAction.footer] {
            let first = try host.control(named: controls.name(for: row[0]))
            let firstInDocument = host.rect(first.frame, in: document)
            _ = document.scrollToVisible(firstInDocument.insetBy(dx: -16, dy: -16))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await host.settle()
            #expect(scroll.scrollerStyle == style)
            #expect(scroll.contentView.bounds.width >= 300)
            let body = viewportBodyScreenRect(host: host, scroll: scroll, layout: layout)
            let clip = host.window.convertToScreen(
                scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            )
            let rowFrames = try row.map { try host.control(named: controls.name(for: $0)).frame }
            expectDisjointIconRow(rowFrames)
            for action in row {
                let node = try host.control(named: controls.name(for: action))
                expectCalendarControlTarget(node.frame, action: action)
                #expect(body.contains(node.frame), "Target \(action) outside body \(body)")
                #expect(clip.contains(node.frame), "Target \(action) clipped by \(clip)")
                if style == .legacy, let scroller = scroll.verticalScroller, !scroller.isHidden {
                    let scrollerFrame = host.window.convertToScreen(
                        scroller.convert(scroller.bounds, to: nil)
                    )
                    #expect(!node.frame.intersects(scrollerFrame),
                            "Target \(action) \(node.frame) overlaps scrollbar \(scrollerFrame)")
                }
                let inDocument = host.rect(node.frame, in: document)
                documentFrames[action] = inDocument
                #expect(inDocument.minX >= 15.5)
                #expect(inDocument.maxX <= 284.5)
                for position in IconClickPosition.allCases {
                    let before = controls.receipts
                    try await host.click(atScreenPoint: position.point(in: node.frame))
                    var expected = before
                    expected[action, default: 0] += 1
                    #expect(controls.receipts == expected,
                            "\(action) \(position), frame \(node.frame), clip \(clip), actual style \(scroll.scrollerStyle.rawValue)")
                }
            }
        }
        #expect(documentFrames.count == 8)
        let allocations = Array(documentFrames.values)
        for (index, frame) in allocations.enumerated() {
            for other in allocations.dropFirst(index + 1) {
                #expect(!frame.intersects(other))
            }
        }
        #expect(controls.showingPreferences == preferencesOpen)
        #expect(!controls.isPinned)
        #expect(preferences.store.startOfWeekday == 2)
        #expect(preferences.store.aiProvider == .proxy)
        #expect(preferences.receipts.value.forbidden == 0)
        #expect(preferences.hotkey.backend.operations.isEmpty)
        #expect(preferences.receipts.value.displaySaves.isEmpty)
        #expect(preferences.receipts.value.weekdaySaves.isEmpty)
        #expect(preferences.receipts.value.providerSaves.isEmpty)
        for open in [!preferencesOpen, preferencesOpen] {
            controls.showingPreferences = open
            try await host.settle()
            try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
            #expect(scroll.documentView === document)
            #expect(preferences.store.startOfWeekday == 2)
            #expect(preferences.store.aiProvider == .proxy)
        }
        let height = layout.naturalContentHeight
        let size = host.hosting.intrinsicContentSize
        for _ in 0..<4 {
            try await host.settle()
            #expect(layout.naturalContentHeight == height)
            #expect(host.hosting.intrinsicContentSize == size)
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
        }
        #expect(abs(size.width - 316) < 0.5)
        #expect(size.height <= maximumHeight + 0.5)
        #expect(abs(host.hosting.fittingSize.width - 316) < 0.5)
        #expect(host.hosting.fittingSize.height <= maximumHeight + 0.5)
        #expect(scroll.scrollerStyle == style)
        #expect(scroll.contentView.bounds.width >= 300)
    }
}

@MainActor
private func applyFixtureScrollerStyle(
    _ style: NSScroller.Style, scroll: NSScrollView, host: AccessibilityTestHost
) async throws {
    scroll.scrollerStyle = style
    scroll.tile()
    try await host.settle()
    #expect(scroll.scrollerStyle == style)
}

@MainActor
struct AccessibilityViewportContent: View {
    let layout: PanelLayoutState
    let controls: CalendarControlFixture
    let preferences: PreferencesAccessibilityFixture
    var dateSearch: DateSearchFixture? = nil

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: CalendarPanel.caretHeight)
            PanelViewport(layout: layout) {
                VStack(spacing: 12) {
                    if controls.showingPreferences {
                        PreferencesView(
                            store: preferences.store,
                            hotkeyPreferences: preferences.hotkeyModel,
                            notificationCenter: preferences.notifications
                        )
                    }
                    controls.header
                    if let dateSearch {
                        DateSearchFixtureRow(fixture: dateSearch)
                    }
                    Color.clear.frame(height: 300)
                    Divider()
                    controls.footer
                }
                .padding(AppDesign.Spacing.md)
            }
            .background(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg)
                    .fill(.regularMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.CornerRadius.lg))
        }
        .frame(width: PanelGeometry.panelWidth)
    }
}

@MainActor
func accessibilityScrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    for child in view.subviews {
        if let scroll = accessibilityScrollView(in: child) { return scroll }
    }
    return nil
}

@MainActor
func viewportBodyScreenRect(
    host: AccessibilityTestHost, scroll: NSScrollView, layout: PanelLayoutState
) -> NSRect {
    var body = scroll.convert(scroll.bounds, to: host.hosting)
    body.size = NSSize(width: PanelGeometry.contentWidth, height: layout.viewportHeight)
    return host.window.convertToScreen(host.hosting.convert(body, to: nil))
}
