import AppKit
import ComposableArchitecture
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
        let controls = CalendarControlFixture(togglePinOnAction: false)
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
                layout: layout, controls: controls, dateSearch: search
            )
        }
        defer { host.close() }
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
        let (pinned, style) = presentation
        let controls = CalendarControlFixture(togglePinOnAction: false)
        controls.isPinned = pinned
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 158)
        let host = AccessibilityTestHost(width: 316, height: maximumHeight) {
            AccessibilityViewportContent(layout: layout, controls: controls)
        }
        defer { host.close() }
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
        #expect(controls.isPinned == pinned)
        for pinState in [!pinned, pinned] {
            controls.isPinned = pinState
            try await host.settle()
            try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
            #expect(scroll.documentView === document)
            #expect(try host.control(named: "Open Settings").role == .button)
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

    @Test(arguments: [CGFloat(812), 312], [NSScroller.Style.legacy, .overlay])
    func completeCalendarDatesAndFooterRemainReachable(
        maximumHeight: CGFloat, style: NSScroller.Style
    ) async throws {
        let layout = PanelLayoutState()
        layout.updatePlacement(maximumHeight: maximumHeight, caretXOffset: 158)
        let fixture = try CalendarViewportFixture(layout: layout, maximumHeight: maximumHeight)
        let host = fixture.host
        defer { fixture.close() }
        try await host.settle()
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        let scroll = try #require(accessibilityScrollView(in: host.hosting))
        let document = try #require(scroll.documentView)
        try await applyFixtureScrollerStyle(style, scroll: scroll, host: host)
        let dates = host.elements().filter { $0.role == .button && $0.label?.contains("2030") == true }
        #expect(dates.count == 42, "The real calendar must expose every date\n\(host.treeDescription)")
        let dateNames = dates.compactMap(\.label)
        #expect(Set(dateNames).count == 42)
        let controls = [
            "Previous month", "Go to today", "Next month",
            "Quit Glimpse", "About Glimpse", "Pin window",
            "Open Calendar app", "Open Settings",
        ]
        var dateFrames: [NSRect] = []
        for name in dateNames + controls {
            let beforeScroll = try host.control(named: name)
            _ = document.scrollToVisible(host.rect(beforeScroll.frame, in: document)
                .insetBy(dx: -4, dy: -4))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await host.settle()
            let node = try host.control(named: name)
            let body = viewportBodyScreenRect(host: host, scroll: scroll, layout: layout)
            let clip = host.window.convertToScreen(
                scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            )
            #expect(body.contains(node.frame), "\(name) outside calendar body \(body)")
            #expect(clip.contains(node.frame), "\(name) clipped by calendar viewport \(clip)")
            if style == .legacy, let scroller = scroll.verticalScroller, !scroller.isHidden {
                let scrollerFrame = host.window.convertToScreen(
                    scroller.convert(scroller.bounds, to: nil)
                )
                #expect(!node.frame.intersects(scrollerFrame), "\(name) overlaps the scrollbar")
            }
            if dateNames.contains(name) {
                #expect(node.enabled)
                #expect(abs(node.frame.height - 30) < 0.5)
                #expect(node.frame.width > 28)
                dateFrames.append(host.rect(node.frame, in: document))
            }
            #expect(accessibilityScrollView(in: host.hosting) === scroll)
            #expect(scroll.documentView === document)
        }
        for (index, frame) in dateFrames.enumerated() {
            for other in dateFrames.dropFirst(index + 1) {
                #expect(!frame.intersects(other))
            }
        }
        #expect(fixture.store.displayedMonth == fixture.month)
        #expect(fixture.store.selectedDate == nil)
        #expect(fixture.protectedEffects.value == 0)
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
    var dateSearch: DateSearchFixture? = nil

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: CalendarPanel.caretHeight)
            PanelViewport(layout: layout) {
                VStack(spacing: 12) {
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

/// The complete production calendar; protected services and status-item rendering are isolated.
@MainActor
private final class CalendarViewportFixture {
    let month: Date
    let store: StoreOf<CalendarFeature>
    let host: AccessibilityTestHost
    let protectedEffects = LockIsolated(0)

    init(layout: PanelLayoutState, maximumHeight: CGFloat) throws {
        month = try #require(Calendar.current.date(from: DateComponents(
            year: 2030, month: 11, day: 15, hour: 12
        )))
        let effects = protectedEffects
        let today = month
        store = Store(initialState: CalendarFeature.State(displayedMonth: month)) {
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(today)
            $0.calendarClient = .liveValue // Pure grid/date generation; no service I/O.
            $0.calendarClient.menuBarDateString = { _, _ in
                effects.withValue { $0 += 1 }
                Issue.record("Viewport fixture must not render a production status item")
                return ""
            }
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { false }
            $0.eventKitClient = EventKitClient(
                requestAccess: {
                    effects.withValue { $0 += 1 }
                    Issue.record("Viewport fixture must not request calendar access")
                    return false
                },
                fetchEvents: { _ in
                    effects.withValue { $0 += 1 }
                    Issue.record("Viewport fixture must not read private events")
                    return []
                },
                authorizationStatus: { .notDetermined }
            )
        }
        let calendarStore = store
        let model = AIDateQueryModel(
            client: AIDateQueryClient(
                resolveProvider: { _ in
                    effects.withValue { $0 += 1 }
                    Issue.record("Viewport fixture must not resolve an AI provider")
                    return .none
                },
                parseDate: { _, _ in
                    effects.withValue { $0 += 1 }
                    Issue.record("Viewport fixture must not request an AI date")
                    return nil
                }
            ),
            enabled: false, preference: .auto,
            onDate: { _ in Issue.record("Viewport fixture must not receive an AI date") }
        )
        host = AccessibilityTestHost(width: 316, height: maximumHeight) {
            CalendarPopoverView(
                store: calendarStore, layout: layout,
                aiQueryModel: model, loadAISettings: { (false, .auto) }
            )
        }
    }

    func close() {
        host.hosting.rootView = AnyView(EmptyView())
        host.close()
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
