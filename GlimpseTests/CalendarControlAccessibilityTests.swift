import AppKit
import Observation
import SwiftUI
import Testing

@testable import Glimpse

@Suite(.serialized) @MainActor
struct CalendarIconTargetTests {
    @Test(arguments: [CGFloat(316), 300, 264, 248], [false, true])
    func footerExposesOneRowAtBothFitWidths(width: CGFloat, pinned: Bool) async throws {
        let fixture = CalendarControlFixture(togglePinOnAction: false)
        fixture.isPinned = pinned
        let host = AccessibilityTestHost(
            width: width, height: 44
        ) { fixture.footer }
        defer { host.close() }
        try await host.settle()
        let buttons = host.elements().filter { $0.role == .button }
        #expect(buttons.compactMap(\.label) == CalendarControlAction.footer.map { fixture.name(for: $0) })
        #expect(buttons.count == 5)
        let frames = try CalendarControlAction.footer.map {
            try host.control(named: fixture.name(for: $0)).frame
        }
        for (action, frame) in zip(CalendarControlAction.footer, frames) {
            expectCalendarControlTarget(frame, action: action)
            #expect(host.hosting.bounds.contains(host.rect(frame, in: host.hosting)))
            #expect(abs(frame.width - width / 5) < 0.5)
        }
        let first = try #require(frames.first)
        let last = try #require(frames.last)
        #expect(abs(host.rect(first, in: host.hosting).minX) < 0.5)
        #expect(abs(host.rect(last, in: host.hosting).maxX - width) < 0.5)
        for pair in zip(frames, frames.dropFirst()) {
            #expect(abs(pair.1.minX - pair.0.maxX) < 0.5)
            #expect(abs(pair.1.minY - pair.0.minY) < 0.5)
        }
        let pin = try host.control(named: fixture.name(for: .pin))
        #expect(pin.value as? String == (pinned ? "Pinned" : "Not pinned"))
        #expect(pin.help == (pinned ? "Unpin calendar window" : "Pin calendar window to keep it open"))
        #expect(try host.control(named: "Open Glimpse Settings").help == "Open Glimpse Settings (⌘,)")
        for dark in [false, true] {
            host.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            try await host.settle()
            try saveFooterControlRender(
                host, name: "footer-\(Int(width))-\(pinned ? "pinned" : "unpinned")-\(dark ? "dark" : "light")"
            )
        }
    }

    @Test(arguments: [false, true])
    func headerAndFooterTargetsHaveSingleEdgeActions(pinned: Bool) async throws {
        let fixture = CalendarControlFixture()
        fixture.isPinned = pinned
        let host = AccessibilityTestHost(width: 268, height: 120) {
            CalendarControlFixtureRows(fixture: fixture)
        }
        defer { host.close() }
        try await host.settle()
        let names = CalendarControlAction.allCases.map { fixture.name(for: $0) }
        #expect(host.elements().filter { $0.role == .button }.compactMap(\.label) == names)
        for action in CalendarControlAction.allCases {
            for position in IconClickPosition.allCases {
                let node = try host.control(named: fixture.name(for: action))
                #expect(node.role == .button)
                #expect(node.enabled)
                expectCalendarControlTarget(node.frame, action: action)
                if action == .today {
                    #expect(node.help == "Go to today")
                }
                let before = fixture.receipts
                try await host.click(atScreenPoint: position.point(in: node.frame))
                var expected = before
                expected[action, default: 0] += 1
                #expect(fixture.receipts == expected, "Only \(action) at \(position) should act")
            }
        }
        #expect(fixture.isPinned == !pinned)
        #expect(try host.control(named: fixture.name(for: .pin)).role == .button)
        #expect(try host.control(named: "Open Glimpse Settings").role == .button)

        if !pinned {
            let calendar = Calendar(identifier: .gregorian)
            let artifactDirectory = ProcessInfo.processInfo.environment["GLIMPSE_HEADER_ARTIFACT_DIR"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
            if let artifactDirectory {
                try FileManager.default.createDirectory(
                    at: artifactDirectory, withIntermediateDirectories: true
                )
            }
            for locale in ["en_US", "de_DE", "fr_FR", "fi_FI"] {
                for year in [2026, 9999] {
                    for month in 1...12 {
                        let date = try #require(calendar.date(from: DateComponents(
                            year: year, month: month, day: 15, hour: 12
                        )))
                        let title = date.formatted(
                            .dateTime.month(.wide).year().locale(Locale(identifier: locale))
                        )
                        fixture.monthYearString = title
                        try await host.settle()
                        if let artifactDirectory {
                            let bounds = host.hosting.bounds
                            let bitmap = try #require(host.hosting.bitmapImageRepForCachingDisplay(in: bounds))
                            host.hosting.cacheDisplay(in: bounds, to: bitmap)
                            let data = try #require(bitmap.representation(using: .png, properties: [:]))
                            let filename = "header-\(locale)-\(year)-\(month).png"
                            try data.write(to: artifactDirectory.appendingPathComponent(filename))
                        }
                        let titles = host.elements().filter {
                            $0.role?.rawValue == "AXHeading" &&
                                ($0.label == title || $0.value as? String == title)
                        }
                        #expect(titles.count == 1, "Native title: \(title)\n\(host.treeDescription)")
                        let heading = try #require(titles.first)
                        let headingFrame = host.rect(heading.frame, in: host.hosting)
                        #expect(host.hosting.bounds.contains(headingFrame), "Clipped title: \(title)")
                        #expect(headingFrame.height <= 24, "Wrapped title: \(title)")
                        let frames = try CalendarControlAction.header.map {
                            try host.control(named: fixture.name(for: $0)).frame
                        }
                        expectDisjointIconRow(frames)
                        for (action, frame) in zip(CalendarControlAction.header, frames) {
                            expectCalendarControlTarget(frame, action: action)
                            #expect(!heading.frame.intersects(frame), "Overlapping title: \(title)")
                        }
                        print("GLIMPSE_HEADER_TITLE locale=\(locale) year=\(year) month=\(month) title=\(title)")
                    }
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func settingsPressDispatchesOnceWithoutChangingCalendarControls(pinned: Bool) async throws {
        let fixture = CalendarControlFixture()
        fixture.isPinned = pinned
        let host = AccessibilityTestHost(width: 268, height: 120) {
            CalendarControlFixtureRows(fixture: fixture)
        }
        defer { host.close() }
        try await host.settle()
        let names = CalendarControlAction.allCases.map { fixture.name(for: $0) }
        let frames = try names.map { try host.control(named: $0).frame }
        let settings = try host.control(named: "Open Glimpse Settings")
        #expect(settings.role == .button && settings.enabled)
        #expect(settings.press())
        try await host.settle()
        #expect(fixture.receipts == [.settings: 1])
        #expect(fixture.isPinned == pinned)
        #expect(fixture.monthYearString == "September 9999")
        #expect(try names.map { try host.control(named: $0).frame } == frames)
        #expect(try host.control(named: "Open Glimpse Settings").press())
        try await host.settle()
        #expect(fixture.receipts == [.settings: 2])
        #expect(fixture.isPinned == pinned)
        #expect(try names.map { try host.control(named: $0).frame } == frames)
    }

    @Test
    func neighborGapsAndDisabledTodayDoNothing() async throws {
        let fixture = CalendarControlFixture()
        fixture.todayIsDisabled = true
        let host = AccessibilityTestHost(width: 268, height: 120) {
            CalendarControlFixtureRows(fixture: fixture)
        }
        defer { host.close() }
        try await host.settle()
        for row in [CalendarControlAction.header] {
            let frames = try row.map { try host.control(named: fixture.name(for: $0)).frame }
            expectDisjointIconRow(frames)
            for pair in zip(frames, frames.dropFirst()) {
                try await host.click(atScreenPoint: NSPoint(
                    x: (pair.0.maxX + pair.1.minX) / 2, y: pair.0.midY
                ))
            }
        }
        let today = try host.control(named: "Go to today")
        #expect(!today.enabled)
        #expect(today.help == "Go to today")
        expectCalendarControlTarget(today.frame, action: .today)
        _ = today.press()
        try await host.settle()
        for position in IconClickPosition.allCases {
            try await host.click(atScreenPoint: position.point(in: today.frame))
        }
        #expect(fixture.receipts.isEmpty)
    }
}

@MainActor
private func saveFooterControlRender(_ host: AccessibilityTestHost, name: String) throws {
    guard let path = ProcessInfo.processInfo.environment["GLIMPSE_FOOTER_ARTIFACT_DIR"] else { return }
    let destination = URL(fileURLWithPath: path, isDirectory: true)
    let bounds = host.hosting.bounds
    let bitmap = try #require(host.hosting.bitmapImageRepForCachingDisplay(in: bounds))
    host.hosting.cacheDisplay(in: bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: destination.appendingPathComponent(name + ".png"), options: .atomic)
    let nodes = host.elements().filter { $0.role == .button }
    let receipt: [String: Any] = [
        "source": "Glimpse/CalendarPopoverView.swift", "testSource": #filePath,
        "qualification": "Production footer in owned offscreen hosting view; not an installed-app or compositor capture",
        "appearance": host.hosting.effectiveAppearance.name.rawValue,
        "hostingBounds": NSStringFromRect(bounds),
        "keyWindow": host.window.isKeyWindow,
        "buttons": nodes.map { [
            "label": $0.label ?? "", "frame": NSStringFromRect(host.rect($0.frame, in: host.hosting)),
            "enabled": $0.enabled
        ] as [String: Any] }
    ]
    try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
        .write(to: destination.appendingPathComponent(name + ".json"), options: .atomic)
    print("GLIMPSE_FOOTER_RENDER \(destination.appendingPathComponent(name + ".png").path)")
}

@MainActor
private struct CalendarControlFixtureRows: View {
    let fixture: CalendarControlFixture
    var body: some View {
        VStack(spacing: 12) { fixture.header; fixture.footer }
    }
}

enum CalendarControlAction: String, CaseIterable {
    case previous, today, next, quit, about, pin, calendar, settings
    static let header: [Self] = [.previous, .today, .next]
    static let footer: [Self] = [.quit, .about, .pin, .calendar, .settings]
}

enum IconClickPosition: CaseIterable {
    case center, bottomLeft, bottomRight, topLeft, topRight

    func point(in frame: NSRect) -> NSPoint {
        switch self {
        case .center: NSPoint(x: frame.midX, y: frame.midY)
        case .bottomLeft: NSPoint(x: frame.minX + 1, y: frame.minY + 1)
        case .bottomRight: NSPoint(x: frame.maxX - 1, y: frame.minY + 1)
        case .topLeft: NSPoint(x: frame.minX + 1, y: frame.maxY - 1)
        case .topRight: NSPoint(x: frame.maxX - 1, y: frame.maxY - 1)
        }
    }
}

@MainActor
func expectCalendarControlTarget(_ frame: NSRect, action: CalendarControlAction) {
    if action == .today {
        #expect(frame.width >= 47.5, "Measured Today target \(frame)")
    } else if CalendarControlAction.footer.contains(action) {
        #expect(frame.width >= 44, "The whole footer cell must remain a usable target \(frame)")
    } else {
        #expect(abs(frame.width - 28) < 0.5, "Measured header target \(frame)")
    }
    let height: CGFloat = CalendarControlAction.footer.contains(action) ? 44 : 28
    #expect(abs(frame.height - height) < 0.5, "Measured target \(frame)")
}

@MainActor
func expectDisjointIconRow(_ frames: [NSRect], minimumGap: CGFloat = 8) {
    for (index, frame) in frames.enumerated() {
        for other in frames.dropFirst(index + 1) {
            #expect(!frame.intersects(other))
        }
    }
    for pair in zip(frames, frames.dropFirst()) {
        #expect(pair.1.minX - pair.0.maxX >= minimumGap - 0.5)
    }
}

/// Production rows with fixture-owned callbacks, including every external action.
@MainActor @Observable
final class CalendarControlFixture {
    var isPinned = false
    var monthYearString = "September 9999"
    var todayIsDisabled = false
    private(set) var receipts: [CalendarControlAction: Int] = [:]
    private let togglePinOnAction: Bool

    init(togglePinOnAction: Bool = true) {
        self.togglePinOnAction = togglePinOnAction
    }

    var header: some View {
        CalendarHeaderControls(
            monthYearString: monthYearString,
            todayIsDisabled: todayIsDisabled,
            previous: { self.record(.previous) },
            today: { self.record(.today) },
            next: { self.record(.next) }
        )
    }

    var footer: some View {
        footer(trailingInset: 0)
    }

    func footer(trailingInset: CGFloat) -> some View {
        CalendarFooterControls(
            isPinned: isPinned,
            quit: { self.record(.quit) }, about: { self.record(.about) },
            togglePin: { self.record(.pin) }, openCalendar: { self.record(.calendar) },
            openSettings: { self.record(.settings) }, trailingInset: trailingInset
        )
    }

    func name(for action: CalendarControlAction) -> String {
        switch action {
        case .previous: "Previous month"
        case .today: "Go to today"
        case .next: "Next month"
        case .quit: "Quit Glimpse"
        case .about: "About Glimpse"
        case .pin: isPinned ? "Unpin calendar window" : "Pin calendar window"
        case .calendar: "Open Calendar app"
        case .settings: "Open Glimpse Settings"
        }
    }

    private func record(_ action: CalendarControlAction) {
        receipts[action, default: 0] += 1
        if action == .pin && togglePinOnAction { isPinned.toggle() }
    }
}

@Suite(.serialized) @MainActor
struct DateSearchAccessibilityTests {
    @Test(arguments: DateSearchActivation.allCases, [false, true])
    func dateSearchDismissClearsWithoutSubmitting(
        activation: DateSearchActivation, hasError: Bool
    ) async throws {
        let fixture = DateSearchFixture()
        fixture.error = hasError ? "fixture error" : nil
        let host = AccessibilityTestHost(width: 268, height: 120) {
            DateSearchFixtureRow(fixture: fixture)
        }
        defer { host.close() }
        try await host.settle()
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        let buttons = host.elements().filter { $0.role == .button }
        #expect(buttons.count == 1)
        let dismiss = try #require(buttons.first)
        #expect(dismiss.label == "Close date search")
        #expect(dismiss.help == "Clears the query and closes date search.")
        expectDateSearchTarget(dismiss.frame)
        #expect(dismiss.enabled)
        if let point = activation.point(in: dismiss.frame) {
            try await host.click(atScreenPoint: point)
        } else {
            #expect(dismiss.press())
            try await host.settle()
        }
        #expect(fixture.query.isEmpty)
        #expect(fixture.error == nil)
        #expect(!fixture.isActive)
        #expect(!fixture.isProcessing)
        #expect(fixture.submissions == 0)
        #expect(fixture.editorAppearances == 1)
        #expect(host.window.isVisible)
        #expect(host.elements().filter { $0.role == .textField }.isEmpty)
        #expect(host.elements().filter { $0.role == .button }.count == 1)
    }

    @Test
    func processingHasNoDismissOrImplicitSubmit() async throws {
        let fixture = DateSearchFixture()
        fixture.isProcessing = true
        let host = AccessibilityTestHost(width: 268, height: 120) {
            DateSearchFixtureRow(fixture: fixture)
        }
        defer { host.close() }
        try await host.settle()
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        #expect(host.controls(named: "Close date search").isEmpty)
        #expect(host.elements().filter { $0.role == .button }.isEmpty)
        #expect(host.elements().filter { $0.role == .textField }.count == 1)
        #expect(fixture.query == "fixture draft")
        #expect(fixture.isActive && fixture.isProcessing)
        #expect(fixture.submissions == 0)
        #expect(fixture.editorAppearances == 1)
    }

    @Test(arguments: [false, true])
    func activeEditorAndDismissAreSeparateControls(hasError: Bool) async throws {
        let fixture = DateSearchFixture()
        fixture.error = hasError ? "fixture error" : nil
        let host = AccessibilityTestHost(width: 268, height: 120) {
            DateSearchFixtureRow(fixture: fixture)
        }
        defer { host.close() }
        try await host.settle()
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        let editors = host.elements().filter { $0.role == .textField }
        let buttons = host.elements().filter { $0.role == .button }
        #expect(editors.count == 1, "\(host.treeDescription)")
        #expect(buttons.count == 1, "\(host.treeDescription)")
        let editor = try #require(editors.first)
        let dismiss = try #require(buttons.first)
        #expect(editor.enabled && dismiss.enabled)
        #expect(editor.label == "Go to date using AI")
        #expect(editor.value as? String == "fixture draft")
        #expect(!editor.frame.intersects(dismiss.frame))
        #expect(dismiss.label == "Close date search")
        #expect(fixture.submissions == 0)
    }

    @Test
    func collapsedPromptOpensSearchWithoutSubmitting() async throws {
        let fixture = DateSearchFixture()
        fixture.isActive = false
        let host = AccessibilityTestHost(width: 268, height: 120) {
            DateSearchFixtureRow(fixture: fixture)
        }
        defer { host.close() }
        try await host.settle()
        try host.loadAccessibilityWindowTree()
        try await host.settle()
        #expect(host.elements().filter { $0.role == .textField }.isEmpty)
        let buttons = host.elements().filter { $0.role == .button }
        #expect(buttons.count == 1)
        let prompt = try #require(buttons.first)
        #expect(prompt.label == "Go to date using AI")
        #expect(prompt.press())
        try await host.settle()
        #expect(fixture.isActive)
        #expect(fixture.query == "fixture draft")
        #expect(fixture.submissions == 0)
        #expect(fixture.editorAppearances == 1)
        #expect(host.elements().filter { $0.role == .textField }.count == 1)
    }
}

enum DateSearchActivation: CaseIterable {
    case nativePress, center, bottomLeft, bottomRight, topLeft, topRight

    func point(in frame: NSRect) -> NSPoint? {
        switch self {
        case .nativePress: nil
        case .center: IconClickPosition.center.point(in: frame)
        case .bottomLeft: IconClickPosition.bottomLeft.point(in: frame)
        case .bottomRight: IconClickPosition.bottomRight.point(in: frame)
        case .topLeft: IconClickPosition.topLeft.point(in: frame)
        case .topRight: IconClickPosition.topRight.point(in: frame)
        }
    }
}

@MainActor
func expectDateSearchTarget(_ frame: NSRect) {
    #expect(abs(frame.width - 24) < 0.5, "Measured dismiss target \(frame)")
    #expect(abs(frame.height - 24) < 0.5, "Measured dismiss target \(frame)")
}

@MainActor @Observable
final class DateSearchFixture {
    var query = "fixture draft"
    var isActive = true
    var isProcessing = false
    var error: String?
    var submissions = 0
    var editorAppearances = 0
}

@MainActor
struct DateSearchFixtureRow: View {
    @Bindable var fixture: DateSearchFixture
    @FocusState private var focused: Bool

    var body: some View {
        CalendarDateSearchRow(
            query: $fixture.query, isActive: $fixture.isActive,
            isProcessing: fixture.isProcessing, error: fixture.error,
            focused: $focused,
            onSubmit: { fixture.submissions += 1 },
            onDismiss: {
                fixture.isActive = false
                fixture.query = ""
                fixture.error = nil
            },
            onEditorAppear: { fixture.editorAppearances += 1 }
        )
    }
}
