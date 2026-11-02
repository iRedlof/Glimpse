import AppKit
import Observation
import SwiftUI
import Testing

@testable import Glimpse

@Suite(.serialized) @MainActor
struct CalendarIconTargetTests {
    @Test(arguments: [false, true], [false, true])
    func headerAndFooterTargetsHaveSingleEdgeActions(
        pinned: Bool, preferences: Bool
    ) async throws {
        let fixture = CalendarControlFixture()
        fixture.isPinned = pinned
        fixture.showingPreferences = preferences
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
                expectIconTarget(node.frame)
                let before = fixture.receipts
                try await host.click(atScreenPoint: position.point(in: node.frame))
                var expected = before
                expected[action, default: 0] += 1
                #expect(fixture.receipts == expected, "Only \(action) at \(position) should act")
            }
        }
        #expect(fixture.isPinned == !pinned)
        #expect(fixture.showingPreferences == !preferences)
        #expect(try host.control(named: fixture.name(for: .pin)).role == .button)
        #expect(try host.control(named: fixture.name(for: .preferences)).role == .button)
    }

    @Test
    func neighborGapsAndDisabledTodayDoNothing() async throws {
        let fixture = CalendarControlFixture()
        fixture.todayIsDisabled = true
        fixture.isShowingCurrentMonth = true
        let host = AccessibilityTestHost(width: 268, height: 120) {
            CalendarControlFixtureRows(fixture: fixture)
        }
        defer { host.close() }
        try await host.settle()
        for row in [CalendarControlAction.header, CalendarControlAction.footer] {
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
        _ = today.press()
        try await host.settle()
        for position in IconClickPosition.allCases {
            try await host.click(atScreenPoint: position.point(in: today.frame))
        }
        #expect(fixture.receipts.isEmpty)
    }
}

@MainActor
private struct CalendarControlFixtureRows: View {
    let fixture: CalendarControlFixture
    var body: some View {
        VStack(spacing: 12) { fixture.header; fixture.footer }
    }
}

enum CalendarControlAction: String, CaseIterable {
    case previous, today, next, quit, about, pin, calendar, preferences
    static let header: [Self] = [.previous, .today, .next]
    static let footer: [Self] = [.quit, .about, .pin, .calendar, .preferences]
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
func expectIconTarget(_ frame: NSRect) {
    #expect(abs(frame.width - 28) < 0.5, "Measured target \(frame)")
    #expect(abs(frame.height - 28) < 0.5, "Measured target \(frame)")
}

@MainActor
func expectDisjointIconRow(_ frames: [NSRect]) {
    for (index, frame) in frames.enumerated() {
        for other in frames.dropFirst(index + 1) {
            #expect(!frame.intersects(other))
        }
    }
    for pair in zip(frames, frames.dropFirst()) {
        #expect(pair.1.minX - pair.0.maxX >= 7.5)
    }
}

/// Production rows with fixture-owned callbacks, including every external action.
@MainActor @Observable
final class CalendarControlFixture {
    var isPinned = false
    var showingPreferences = false
    var isShowingCurrentMonth = false
    var todayIsDisabled = false
    private(set) var receipts: [CalendarControlAction: Int] = [:]
    private let togglePresentationOnAction: Bool

    init(togglePresentationOnAction: Bool = true) {
        self.togglePresentationOnAction = togglePresentationOnAction
    }

    var header: some View {
        CalendarHeaderControls(
            monthYearString: "November 2026",
            isShowingCurrentMonth: isShowingCurrentMonth,
            todayIsDisabled: todayIsDisabled,
            previous: { self.record(.previous) },
            today: { self.record(.today) },
            next: { self.record(.next) }
        )
    }

    var footer: some View {
        CalendarFooterControls(
            isPinned: isPinned, showingPreferences: showingPreferences,
            quit: { self.record(.quit) }, about: { self.record(.about) },
            togglePin: { self.record(.pin) }, openCalendar: { self.record(.calendar) },
            togglePreferences: { self.record(.preferences) }
        )
    }

    func name(for action: CalendarControlAction) -> String {
        switch action {
        case .previous: "Previous month"
        case .today: "Go to today"
        case .next: "Next month"
        case .quit: "Quit Glimpse"
        case .about: "About Glimpse"
        case .pin: isPinned ? "Unpin window" : "Pin window"
        case .calendar: "Open Calendar app"
        case .preferences: showingPreferences ? "Close preferences" : "Open preferences"
        }
    }

    private func record(_ action: CalendarControlAction) {
        receipts[action, default: 0] += 1
        guard togglePresentationOnAction else { return }
        if action == .pin { isPinned.toggle() }
        if action == .preferences { showingPreferences.toggle() }
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
            isProcessing: fixture.isProcessing, error: $fixture.error,
            focused: $focused,
            onSubmit: { fixture.submissions += 1 },
            onEditorAppear: { fixture.editorAppearances += 1 }
        )
    }
}
