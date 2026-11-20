import AppKit
import ComposableArchitecture
import GlimpseCore
import SwiftUI
import Testing

@testable import Glimpse

/// Agenda rows open their event in Calendar. These run inside the owned key-window suite
/// (same opt-in, same serialization) because they drive real Tab/Return/Space/Escape and clicks.
extension CalendarKeyboardOwnershipTests {
    @Test(arguments: [CalendarOwnedKey.returnKey, .space])
    func agendaRowsJoinTabOrderAndOpenTheFocusedEvent(key: CalendarOwnedKey) async throws {
        let calendar = try AgendaFixture.make()
        defer { calendar.close() }
        try await AgendaFixture.openWithEvents(calendar)
        try await calendar.focusOwner(.agendaEvent0)
        #expect(calendar.inputModality.modality == .keyboard)
        // Native traversal in document order: grid, then rows, then the footer.
        try calendar.send(.tab)
        await calendar.settleRendering()
        #expect(calendar.lastPublishedOwner == .agendaEvent1)
        try calendar.send(.tab)
        await calendar.settleRendering()
        #expect(calendar.lastPublishedOwner == .footerPin)
        try calendar.send(.backTab)
        await calendar.settleRendering()
        #expect(calendar.lastPublishedOwner == .agendaEvent1)

        let before = calendar.callbackRows.count
        try calendar.send(key)
        await calendar.settleRendering()
        calendar.expectInvocation(after: before, owner: .agendaEvent1, key: key == .space ? .space : .returnKey,
                                  route: "activate")
        #expect(calendar.actions.value == ["openEvent:Haircut"])
        #expect(calendar.actionCurrentEvents.value == [true])
        #expect(calendar.calendarAppOpens.value.map(\.absoluteString)
            == ["ical://ekevent/ITEM-HAIRCUT?method=show&options=more"])
        // Pinned: the calendar keeps its frame and focus; the handoff never restores a previous app.
        #expect(calendar.panel.isVisible)
        #expect(calendar.previousAppRestorations == 0)
    }

    @Test
    func heldAgendaReturnOpensOnceAndArrowsNeverBrowseUnderARow() async throws {
        let calendar = try AgendaFixture.make()
        defer { calendar.close() }
        try await AgendaFixture.openWithEvents(calendar)
        try await calendar.focusOwner(.agendaEvent0)
        let month = calendar.monthNumber
        for arrow in [CalendarOwnedKey.left, .right, .up, .down] { try calendar.send(arrow) }
        await calendar.settleRendering()
        #expect(calendar.monthNumber == month)
        #expect(calendar.actions.value.isEmpty)
        #expect(calendar.lastPublishedOwner == .agendaEvent0)

        try calendar.sendPhase(.returnKey, phase: .down)
        try calendar.sendPhase(.returnKey, phase: .repeatPress)
        try calendar.sendPhase(.returnKey, phase: .repeatPress)
        try calendar.sendPhase(.returnKey, phase: .up)
        await calendar.settleRendering()
        #expect(calendar.actions.value == ["openEvent:Design review"])
        // A repeating event names its occurrence by its UTC start.
        let standup = try #require(calendar.store.events.first)
        let expected = try #require(CalendarEventLink.url(for: standup))
        #expect(expected.absoluteString.hasPrefix("ical://ekevent/20301115T"))
        #expect(expected.absoluteString.hasSuffix("Z/ITEM-STANDUP?method=show&options=more"))
        #expect(calendar.calendarAppOpens.value == [expected])
    }

    @Test(arguments: [CalendarOwnedKey.returnKey, .space])
    func joinButtonFollowsItsRowInTabOrderAndOpensTheMeetingLink(key: CalendarOwnedKey) async throws {
        let calendar = try AgendaFixture.make(meetingLink: true)
        defer { calendar.close() }
        try await AgendaFixture.openWithEvents(calendar)
        // At 12:00 the next meeting is Haircut (14:00), which has the Zoom link.
        #expect(calendar.store.joinableEventID == "haircut")
        try await calendar.focusOwner(.agendaEvent1)
        try calendar.send(.tab)
        await calendar.settleRendering()
        #expect(calendar.lastPublishedOwner == .agendaJoin)
        let before = calendar.callbackRows.count
        try calendar.send(key)
        await calendar.settleRendering()
        calendar.expectInvocation(after: before, owner: .agendaJoin, key: key == .space ? .space : .returnKey,
                                  route: "activate")
        #expect(calendar.actions.value == ["joinMeeting:Haircut"])
        #expect(calendar.meetingLinkOpens.value.map(\.absoluteString) == [AgendaFixture.meetingURL])
        #expect(calendar.calendarAppOpens.value.isEmpty)
        #expect(calendar.previousAppRestorations == 0)
    }

    @Test
    func commandJJoinsFromAnywhereInThePanelOnlyWhenAMeetingIsJoinable() async throws {
        let calendar = try AgendaFixture.make(meetingLink: true)
        defer { calendar.close() }
        try await AgendaFixture.openWithEvents(calendar)
        try await calendar.focusOwner(.agendaEvent0)
        try calendar.send(.joinShortcut)
        await calendar.settleRendering()
        #expect(calendar.actions.value == ["joinMeeting:Haircut"])
        #expect(calendar.meetingLinkOpens.value.map(\.absoluteString) == [AgendaFixture.meetingURL])

        let plain = try AgendaFixture.make()
        defer { plain.close() }
        try await AgendaFixture.openWithEvents(plain)
        try await plain.focusOwner(.agendaEvent0)
        try plain.send(.joinShortcut)
        await plain.settleRendering()
        #expect(plain.store.joinableEventID == nil)
        #expect(plain.actions.value.isEmpty)
        #expect(plain.meetingLinkOpens.value.isEmpty)
    }

    @Test
    func agendaRowEscapeStillClosesThePanelWithoutOpeningCalendar() async throws {
        let calendar = try AgendaFixture.make()
        defer { calendar.close() }
        try await AgendaFixture.openWithEvents(calendar)
        try await calendar.focusOwner(.agendaEvent1)
        try calendar.send(.escape)
        await calendar.settleRendering()
        #expect(!calendar.panel.isVisible)
        #expect(calendar.calendarAppOpens.value.isEmpty)
    }

    @Test(arguments: [false, true])
    func agendaRowClickOpensEventAndAbandonsTheRestorationLease(pinned: Bool) async throws {
        let calendar = try AgendaFixture.make(showAI: true)
        defer { calendar.close() }
        try await AgendaFixture.openWithEvents(calendar)
        calendar.panel.isPinned = pinned
        if pinned { calendar.store.send(.togglePin) }
        // Editing text took a restoration lease on the app that was in front.
        calendar.panel.activateForTextInput()
        calendar.aiModel.setEditorOpen(true)
        await calendar.settleRendering()
        let row = try AgendaFixture.row(calendar, title: "Haircut")
        #expect(row.help == CalendarAgendaEventRow.openHint)
        #expect(row.label?.hasPrefix("Haircut, ") == true)
        try calendar.clickOwned(at: NSPoint(x: row.frame.midX, y: row.frame.midY))
        await calendar.settleRendering()
        #expect(calendar.actions.value == ["openEvent:Haircut"])
        #expect(calendar.actionCurrentEvents.value == [true])
        #expect(calendar.calendarAppOpens.value.count == 1)
        #expect(calendar.inputModality.modality == .pointer)
        #expect(calendar.panel.isVisible == pinned)
        // Calendar is now in front: nothing may re-front the previous app over it.
        calendar.panel.deactivateTextInput()
        calendar.panel.orderOut(nil)
        #expect(calendar.previousAppRestorations == 0)
    }

    @Test
    func agendaRowAccessibilityPressOpensTheEvent() async throws {
        let calendar = try AgendaFixture.make()
        defer { calendar.close() }
        try await AgendaFixture.openWithEvents(calendar)
        let row = try AgendaFixture.row(calendar, title: "Design review")
        #expect(row.role == .button)
        #expect(row.inputLabels.contains("Design review"))
        #expect(row.press())
        await calendar.settleRendering()
        #expect(calendar.calendarAppOpens.value.count == 1)
    }

    @Test(arguments: [false, true])
    func agendaRowFocusRingFollowsInputModality(dark: Bool) async throws {
        let calendar = try AgendaFixture.make()
        defer { calendar.close() }
        let appearance = dark ? "dark" : "light"
        try await AgendaFixture.openWithEvents(calendar)
        calendar.panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        await calendar.settleRendering()
        let list = try AgendaFixture.listFrame(calendar)
        let rest = try await AgendaFixture.stableBitmap(calendar, list)
        try calendar.saveFocusedDateBitmap(list, name: "agenda-rest-\(appearance)")

        // Keyboard focus draws the inset ring; the same focus after pointer use draws nothing.
        try await calendar.focusOwner(.agendaEvent0)
        await calendar.settleRendering()
        // Focusing a row scrolls the agenda into view; compare at the row's current place.
        let focusedList = try AgendaFixture.listFrame(calendar)
        let focused = try await AgendaFixture.stableBitmap(calendar, focusedList)
        try calendar.saveFocusedDateBitmap(focusedList, name: "agenda-focus-\(appearance)")
        calendar.inputModality.note(.pointer)
        let pointerFocused = try await AgendaFixture.stableBitmap(calendar, focusedList)
        #expect(pointerFocused != focused)
        if focusedList == list { #expect(pointerFocused == rest) }
        #expect(calendar.lastPublishedOwner == .agendaEvent0)
        calendar.inputModality.note(.keyboard)
        #expect(try await AgendaFixture.stableBitmap(calendar, focusedList) == focused)
    }
}

/// Fixture wiring for agenda rows: full access with two events on the fixture's today.
@MainActor
enum AgendaFixture {
    static let meetingURL = "https://zoom.us/j/555"

    static func make(showAI: Bool = false, meetingLink: Bool = false) throws -> CalendarKeyboardRootFixture {
        let today = try #require(Calendar.current.date(from: DateComponents(
            year: 2030, month: 11, day: 15, hour: 12
        )))
        let events = try events(on: today, meetingLink: meetingLink)
        let client = EventKitClient(
            requestAccess: { true },
            fetchEvents: { _ in events },
            authorizationStatus: { .fullAccess }
        )
        return try CalendarKeyboardRootFixture(showAI: showAI, maximumHeight: 812, initialToday: today,
                                               eventKitClient: client)
    }

    private static func events(on today: Date, meetingLink: Bool) throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let standup = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today))
        let haircut = try #require(calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today))
        return [
            CalendarEvent(id: "standup", title: "Design review", startDate: standup,
                          endDate: standup.addingTimeInterval(3_600), isAllDay: false,
                          itemIdentifier: "ITEM-STANDUP", isRecurring: true),
            CalendarEvent(id: "haircut", title: "Haircut", startDate: haircut,
                          endDate: haircut.addingTimeInterval(3_600), isAllDay: false,
                          itemIdentifier: "ITEM-HAIRCUT",
                          meetingLink: meetingLink ? URL(string: meetingURL).flatMap(MeetingLink.init(url:)) : nil)
        ]
    }

    static func openWithEvents(_ calendar: CalendarKeyboardRootFixture) async throws {
        try await calendar.open()
        for _ in 0..<40 where calendar.store.events.count < 2 {
            await calendar.settleRendering()
        }
        try #require(calendar.store.events.count == 2)
        await calendar.settleRendering()
    }

    static func row(_ calendar: CalendarKeyboardRootFixture, title: String) throws -> AccessibilityTestNode {
        try calendar.loadOwnedAccessibilityTree()
        let nodes = calendar.accessibilityNodes()
        let rows = nodes.filter {
            $0.role == .button && $0.label?.hasPrefix("\(title), ") == true
        }
        let candidates = nodes.filter { $0.label?.contains(title) == true }
            .map { "\(String(describing: $0.role)) \($0.label ?? "")" }
        try #require(rows.count == 1, "AX candidates for \(title): \(candidates)")
        return try #require(rows.first)
    }

    /// The region's bitmap once two consecutive settled captures agree (rings may animate in).
    static func stableBitmap(_ calendar: CalendarKeyboardRootFixture, _ rect: NSRect) async throws -> Data {
        await calendar.settleRendering()
        var previous = try calendar.bitmap(rect)
        for _ in 0..<20 {
            await calendar.settleRendering()
            let current = try calendar.bitmap(rect)
            if current == previous { return current }
            previous = current
        }
        Issue.record("Agenda rendering never settled")
        return previous
    }

    /// Both rows' union, padded to include the list border.
    static func listFrame(_ calendar: CalendarKeyboardRootFixture) throws -> NSRect {
        let frame = try row(calendar, title: "Design review").frame.union(row(calendar, title: "Haircut").frame)
        return frame.insetBy(dx: -6, dy: -8)
    }

}

/// Hover cannot be driven without moving the owner's real cursor (SwiftUI hover follows it), so
/// the hovered appearance is rendered through the row's render-only override, beside the resting
/// row, in both appearances. Ordinary (non key-window) suite: nothing here takes focus.
@MainActor
struct CalendarAgendaEventRowRenderTests {
    private static let event = CalendarEvent(
        id: "haircut", title: "Haircut", startDate: Date(timeIntervalSince1970: 1_900_000_000),
        endDate: Date(timeIntervalSince1970: 1_900_003_600), isAllDay: false, itemIdentifier: "ITEM"
    )

    @Test(arguments: [false, true])
    func hoveredRowDrawsFillAndOpenGlyphOnlyWhileHovered(dark: Bool) throws {
        let appearance = dark ? "dark" : "light"
        let rest = try render(hovered: nil, dark: dark)
        let hovered = try render(hovered: true, dark: dark)
        #expect(rest.png != hovered.png)
        #expect(try render(hovered: false, dark: dark).png == rest.png)
        // The hover fill stays subtle: an empty pixel inside the row differs, but by little.
        let x = rest.bitmap.pixelsWide * 6 / 10, y = rest.bitmap.pixelsHigh / 2
        let delta = abs(rest.luminance(atX: x, y: y) - hovered.luminance(atX: x, y: y))
        #expect(delta > 0.01 && delta < 0.2)
        try save(rest.png, name: "agenda-row-rest-\(appearance)")
        try save(hovered.png, name: "agenda-row-hover-\(appearance)")
    }

    private struct Render {
        let png: Data
        let bitmap: NSBitmapImageRep

        func luminance(atX x: Int, y: Int) -> CGFloat {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return -1 }
            return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        }
    }

    private func render(hovered: Bool?, dark: Bool) throws -> Render {
        let row = CalendarAgendaEventRow(event: Self.event, owner: .agendaEvent0, open: {}, hoverOverride: hovered)
            .frame(width: 260)
            .padding(AppDesign.Spacing.xs)
            .background(AppDesign.Colors.calendarSurface)
        let hosting = NSHostingView(rootView: row)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return Render(png: try #require(bitmap.representation(using: .png, properties: [:])), bitmap: bitmap)
    }

    private func save(_ data: Data, name: String) throws {
        let base = ProcessInfo.processInfo.environment["GLIMPSE_KEYBOARD_ARTIFACT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("agenda-rendering", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try data.write(to: base.appendingPathComponent(name + ".png"))
    }
}
