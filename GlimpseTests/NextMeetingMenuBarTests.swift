import AppKit
import ComposableArchitecture
import GlimpseCore
import SwiftUI
import Testing

@testable import Glimpse

/// The opt-in next-meeting segment: composited into the one status item image (never a
/// subview), amber within five minutes, identical in the Settings preview, and ⌘J routing.
@Suite(.serialized)
@MainActor
struct NextMeetingMenuBarTests {
    private static let upcoming = MenuBarMeetingSegment(text: "Standup in 12m", isImminent: false)
    private static let imminent = MenuBarMeetingSegment(text: "Standup in 4m", isImminent: true)
    private static let inMeeting = MenuBarMeetingSegment(text: "Standup ends 10:30", isImminent: false)

    private func options(
        filled: Bool = false, icon: Bool = true, nextMeeting: Bool = true, dayOfWeek: Bool = true, month: Bool = true
    ) -> MenuBarDisplayOptions {
        MenuBarDisplayOptions(showIcon: icon, showDayOfWeek: dayOfWeek, showMonth: month, showDate: true,
                              showYear: false, showFilledBackground: filled, showNextMeeting: nextMeeting)
    }

    @Test
    func meetingSegmentWidensTheItemByItsTextAndOneSeparator() throws {
        let plain = MenuBarItemRenderer.render(options: options(), dateString: "Tue 10 Nov", isDark: false)
        let withMeeting = MenuBarItemRenderer.render(
            options: options(), dateString: "Tue 10 Nov", meeting: Self.upcoming, isDark: false
        )
        let textWidth = ceil(NSAttributedString(string: Self.upcoming.text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: AppDesign.StatusItem.fontSize, weight: .medium),
        ]).size().width)
        let separator = AppDesign.StatusItem.innerPadding * 2 + 1
        #expect(abs(withMeeting.size.width - (plain.size.width + separator + textWidth)) <= 1)
        #expect(withMeeting.size.height == plain.size.height)
        #expect(!withMeeting.isTemplate)
    }

    @Test
    func withoutAMeetingTheImageIsUnchanged() throws {
        // Default-off (or nothing left today) must render exactly the pre-feature item.
        let before = try png(MenuBarItemRenderer.render(options: options(nextMeeting: false), dateString: "Tue 10 Nov", isDark: true))
        let after = try png(MenuBarItemRenderer.render(options: options(), dateString: "Tue 10 Nov", meeting: nil, isDark: true))
        #expect(before == after)
    }

    @Test
    func meetingAloneNeedsNoIconAndNoLeadingSeparator() {
        let alone = MenuBarItemRenderer.render(
            options: options(icon: false), dateString: "", meeting: Self.upcoming, isDark: false
        )
        let withIcon = MenuBarItemRenderer.render(
            options: options(icon: true), dateString: "", meeting: Self.upcoming, isDark: false
        )
        let separator = AppDesign.StatusItem.innerPadding * 2 + 1
        #expect(abs(withIcon.size.width - alone.size.width - (AppDesign.Icon.menuBarSize + separator)) <= 1)
        #expect(MenuBarItemRenderer.itemWidth(showIcon: false, segmentWidths: [50, 40])
            == ceil(AppDesign.StatusItem.padding * 2 + separator + 90))
    }

    @Test
    func tabularDigitsKeepTheCountdownWidthStable() {
        let widths = ["Standup in 11m", "Standup in 18m", "Standup in 44m"].map { text in
            MenuBarItemRenderer.render(
                options: options(), dateString: "Tue 10 Nov",
                meeting: MenuBarMeetingSegment(text: text, isImminent: false), isDark: false
            ).size.width
        }
        #expect(Set(widths).count == 1)
    }

    @Test(arguments: [false, true])
    func imminentTurnsThePillAmberInBothStyles(dark: Bool) throws {
        for filled in [false, true] {
            let image = MenuBarItemRenderer.render(
                options: options(filled: filled), dateString: "Tue", meeting: Self.imminent, isDark: dark
            )
            let fill = try pixel(in: image, xFraction: 0.5, yFraction: 0.12)
            let amber = AppDesign.Colors.accentAmberNS
            #expect(abs(fill.redComponent - amber.redComponent) < 0.05)
            #expect(abs(fill.greenComponent - amber.greenComponent) < 0.05)
            #expect(abs(fill.blueComponent - amber.blueComponent) < 0.05)
        }
        // Not imminent: the bordered pill stays clear.
        let normal = MenuBarItemRenderer.render(
            options: options(), dateString: "Tue", meeting: Self.upcoming, isDark: dark
        )
        #expect(try pixel(in: normal, xFraction: 0.5, yFraction: 0.12).alphaComponent < 0.05)
    }

    @Test
    func segmentWordingComesFromTheCoreText() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEvent(id: "a", title: "Standup", startDate: start,
                                  endDate: start.addingTimeInterval(1_800), isAllDay: false)
        let soon = MenuBarMeetingSegment(NextMeeting(event: event, phase: .upcoming(minutesUntil: 3)),
                                         calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(soon == MenuBarMeetingSegment(text: "Standup in 3m", isImminent: true))
        let later = MenuBarMeetingSegment(NextMeeting(event: event, phase: .upcoming(minutesUntil: 30)),
                                          calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(later.isImminent == false)
    }

    @Test
    func previewRendersTheSameImageAsTheMenuBar() async throws {
        let options = options(icon: false)
        for scheme in [ColorScheme.light, .dark] {
            let host = AccessibilityTestHost(width: 360, height: 48) {
                StatusItemPreview(displayOptions: options, dateString: "Wednesday", meeting: Self.imminent)
                    .environment(\.colorScheme, scheme)
            }
            defer { host.close() }
            try await host.settle()
            let preview = try #require(imageViews(in: host.hosting).first?.image)
            let direct = MenuBarItemRenderer.render(
                options: options, dateString: "Wednesday", meeting: Self.imminent, isDark: scheme == .dark
            )
            #expect(preview.size == direct.size)
            #expect(try png(preview) == png(direct))
        }
    }

    @Test
    func commandJJoinsOnlyWithAJoinableMeeting() {
        let j = CalendarKeyboardRouter.joinKeyCode
        #expect(CalendarKeyboardRouter.joinsMeeting(keyCode: j, commandOnly: true, isRepeat: false, canJoin: true))
        #expect(!CalendarKeyboardRouter.joinsMeeting(keyCode: j, commandOnly: true, isRepeat: false, canJoin: false))
        #expect(!CalendarKeyboardRouter.joinsMeeting(keyCode: j, commandOnly: false, isRepeat: false, canJoin: true))
        #expect(!CalendarKeyboardRouter.joinsMeeting(keyCode: j, commandOnly: true, isRepeat: true, canJoin: true))
        #expect(!CalendarKeyboardRouter.joinsMeeting(keyCode: 5, commandOnly: true, isRepeat: false, canJoin: true))
        // The Join button is its own owner, never an agenda row and never a browse source.
        #expect(!CalendarKeyboardOwner.agendaJoin.isAgendaEvent)
        #expect(CalendarKeyboardRouter.local(.returnKey, phase: .down, owner: .agendaJoin, context: .eligible) == .activate)
        #expect(CalendarKeyboardRouter.local(.left, phase: .down, owner: .agendaJoin, context: .eligible) == .yield)
    }

    @Test
    func controllerPublishesTheStoresMeetingAndNotifiesOnChange() async throws {
        // Midday, so "ten minutes before" is the same local day in any zone.
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let start = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day))
        let event = CalendarEvent(id: "a", title: "Standup", startDate: start,
                                  endDate: start.addingTimeInterval(1_800), isAllDay: false)
        let now = LockIsolated(start.addingTimeInterval(-600))
        let store = Store(initialState: NextMeetingFeature.State()) {
            NextMeetingFeature()
        } withDependencies: {
            $0.date = DateGenerator { now.value }
            $0.calendar = calendar
            $0.continuousClock = TestClock()
            $0.uuid = .incrementing
            $0.eventKitClient.authorizationStatus = { .fullAccess }
            $0.eventKitClient.fetchEvents = { _ in [event] }
        }
        let controller = NextMeetingMenuBarController(store: store, notificationCenter: NotificationCenter())
        var changes = 0
        controller.onChange = { changes += 1 }
        now.setValue(start.addingTimeInterval(1_900))
        controller.setEnabled(true)
        try await waitUntil { controller.segment == nil && store.events == [event] }
        #expect(controller.isEnabled)

        now.setValue(start.addingTimeInterval(-600))
        controller.refresh()
        try await waitUntil { controller.segment != nil }
        #expect(controller.segment?.text.hasPrefix("Standup in ") == true)
        #expect(changes >= 1)
        controller.setEnabled(false)
        try await waitUntil { controller.segment == nil }
    }

    // MARK: - Native renders (light/dark × bordered/filled × upcoming/imminent/in meeting)

    @Test
    func writesNativeRendersOfEveryState() throws {
        let states: [(String, MenuBarMeetingSegment?)] = [
            ("off", nil), ("upcoming", Self.upcoming), ("imminent", Self.imminent), ("in-meeting", Self.inMeeting),
        ]
        for dark in [false, true] {
            for filled in [false, true] {
                for (name, meeting) in states {
                    let image = MenuBarItemRenderer.render(
                        options: options(filled: filled), dateString: "Tue 10 Nov", meeting: meeting, isDark: dark
                    )
                    let data = try menuBarStrip(image, dark: dark)
                    try save(data, name: "menubar-\(dark ? "dark" : "light")-\(filled ? "filled" : "bordered")-\(name)")
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func writesNativeRendersOfTheJoinRow(dark: Bool) throws {
        let start = Date().addingTimeInterval(240)
        let event = CalendarEvent(
            id: "standup", title: "Standup", startDate: start, endDate: start.addingTimeInterval(1_800),
            isAllDay: false, meetingLink: URL(string: "https://zoom.us/j/123").flatMap(MeetingLink.init(url:))
        )
        let row = VStack(spacing: 0) {
            CalendarAgendaEventRow(event: event, owner: .agendaEvent0, open: {}, join: {})
            CalendarAgendaEventRow(event: CalendarEvent(
                id: "review", title: "Design review", startDate: start.addingTimeInterval(10_800),
                endDate: start.addingTimeInterval(14_400), isAllDay: false
            ), owner: .agendaEvent1, open: {})
        }
        .frame(width: 284)
        .padding(AppDesign.Spacing.xs)
        .background(AppDesign.Colors.calendarSurface)
        let hosting = NSHostingView(rootView: row)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try save(data, name: "agenda-join-\(dark ? "dark" : "light")")
        #expect(hosting.fittingSize.width > 0)
    }

    // MARK: - Leave-by

    private static let leaveBy = MenuBarMeetingSegment(text: "Dentist · leave by 8:40", isImminent: false)
    private static let leaveByAmber = MenuBarMeetingSegment(text: "Dentist · leave by 8:40", isImminent: true)

    private static func leaveByFixture() -> (Calendar, CalendarEvent, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let nine = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9)) ?? .distantPast
        let dentist = CalendarEvent(id: "dentist", title: "Dentist", startDate: nine,
                                    endDate: nine.addingTimeInterval(3_600), isAllDay: false, location: "412 Oak St")
        return (calendar, dentist, nine)
    }

    @Test
    func leaveBySegmentReadsLeaveByAndTurnsAmberFiveMinutesBefore() throws {
        let (calendar, dentist, nine) = Self.leaveByFixture()
        let locale = Locale(identifier: "en_US")
        func segment(minutesBeforeStart: Double) throws -> MenuBarMeetingSegment {
            let meeting = try #require(NextMeetingSelector.select(
                [dentist], now: nine.addingTimeInterval(-minutesBeforeStart * 60), calendar: calendar, leaveByMinutes: 20
            ))
            return MenuBarMeetingSegment(meeting, calendar: calendar, locale: locale)
        }
        #expect(try segment(minutesBeforeStart: 35) == Self.leaveBy)
        #expect(try segment(minutesBeforeStart: 24) == Self.leaveByAmber)
        #expect(try segment(minutesBeforeStart: 12) == MenuBarMeetingSegment(text: "Dentist in 12m", isImminent: false))
        // The amber leave-by pill is the same amber as the imminent countdown.
        let image = MenuBarItemRenderer.render(options: options(), dateString: "Sat", meeting: Self.leaveByAmber, isDark: true)
        let fill = try pixel(in: image, xFraction: 0.5, yFraction: 0.12)
        #expect(abs(fill.redComponent - AppDesign.Colors.accentAmberNS.redComponent) < 0.05)
        #expect(abs(fill.greenComponent - AppDesign.Colors.accentAmberNS.greenComponent) < 0.05)
    }

    @Test
    func controllerAppliesTheLeaveByBufferBeforeEnabling() {
        let store = Store(initialState: NextMeetingFeature.State()) {
            NextMeetingFeature()
        } withDependencies: {
            $0.eventKitClient.authorizationStatus = { .denied }
        }
        let controller = NextMeetingMenuBarController(store: store, notificationCenter: NotificationCenter())
        controller.apply(MenuBarDisplayOptions(showNextMeeting: true, showLeaveBy: true, leaveByMinutes: 45))
        #expect(controller.isEnabled)
        #expect(controller.leaveByMinutes == 45)
        controller.apply(MenuBarDisplayOptions(showNextMeeting: true, showLeaveBy: false, leaveByMinutes: 45))
        #expect(controller.leaveByMinutes == nil)
        controller.apply(.default)
        #expect(!controller.isEnabled)
    }

    @Test
    func agendaRowSpeaksThePlaceAndTheChip() {
        let (_, dentist, nine) = Self.leaveByFixture()
        let row = CalendarAgendaEventRow(event: dentist, owner: .agendaEvent0, open: {},
                                         badge: .leaveBy(nine.addingTimeInterval(-1_200)))
        #expect(row.subtitle == "\(dentist.startDate.formatted(CalendarAgendaEventRow.startTimeStyle)) · 412 Oak St")
        #expect(row.accessibilityText.hasPrefix("Dentist, \(dentist.timeString), 412 Oak St, Leave by "))
        let plain = CalendarAgendaEventRow(event: CalendarEvent(
            id: "s", title: "Standup", startDate: nine, endDate: nine.addingTimeInterval(900), isAllDay: false
        ), owner: .agendaEvent1, open: {})
        #expect(plain.subtitle == plain.event.timeString)
        #expect(plain.accessibilityText == "Standup, \(plain.event.timeString)")
        let trip = CalendarAgendaEventRow(event: CalendarEvent(
            id: "t", title: "Tahoe trip", startDate: nine, endDate: nine.addingTimeInterval(86_400 * 4),
            isAllDay: false, location: "South Lake Tahoe"
        ), owner: .agendaEvent2, open: {}, badge: .away(days: 5))
        #expect(trip.subtitle == "5 days · South Lake Tahoe")
        #expect(trip.accessibilityText.hasSuffix("South Lake Tahoe, Away 5 days"))
    }

    @Test
    func writesNativeRendersOfLeaveBy() throws {
        let states: [(String, MenuBarMeetingSegment)] = [
            ("upcoming", Self.leaveBy), ("amber", Self.leaveByAmber),
            ("after", MenuBarMeetingSegment(text: "Dentist in 12m", isImminent: false)),
        ]
        for dark in [false, true] {
            for (name, meeting) in states {
                let image = MenuBarItemRenderer.render(
                    options: options(icon: true, dayOfWeek: false, month: false), dateString: "",
                    meeting: meeting, isDark: dark, day: 21
                )
                try save(try menuBarStrip(image, dark: dark),
                         name: "leave-by-menubar-\(dark ? "dark" : "light")-\(name)")
            }
        }
    }

    @Test(arguments: [false, true])
    func writesNativeRendersOfTheLeaveByAndTripChips(dark: Bool) throws {
        // 9:00 AM local, as in the mock.
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9)) ?? .now
        let dentist = CalendarEvent(id: "dentist", title: "Dentist", startDate: start,
                                    endDate: start.addingTimeInterval(3_600), isAllDay: false, location: "412 Oak St")
        let lunch = CalendarEvent(id: "lunch", title: "Lunch with Sam", startDate: start.addingTimeInterval(12_600),
                                  endDate: start.addingTimeInterval(16_200), isAllDay: false)
        let trip = CalendarEvent(id: "tahoe", title: "Tahoe trip", startDate: start.addingTimeInterval(86_400 * 2),
                                 endDate: start.addingTimeInterval(86_400 * 6), isAllDay: false,
                                 location: "South Lake Tahoe")
        let rows = VStack(spacing: 0) {
            CalendarAgendaEventRow(event: dentist, owner: .agendaEvent0, open: {},
                                   badge: .leaveBy(start.addingTimeInterval(-1_200)))
            CalendarAgendaEventRow(event: lunch, owner: .agendaEvent1, open: {})
            CalendarAgendaEventRow(event: trip, owner: .agendaEvent2, open: {}, badge: .away(days: 5))
        }
        let data = try render(rows, dark: dark)
        try save(data, name: "leave-by-agenda-\(dark ? "dark" : "light")")
        #expect(!data.isEmpty)
    }

    private func render(_ content: some View, dark: Bool) throws -> Data {
        let root = content
            .frame(width: 284)
            .padding(AppDesign.Spacing.xs)
            .background(AppDesign.Colors.calendarSurface)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    // MARK: - Helpers

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for the next-meeting controller")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func imageViews(in view: NSView) -> [NSImageView] {
        ((view as? NSImageView).map { [$0] } ?? []) + view.subviews.flatMap { imageViews(in: $0) }
    }

    private func bitmap(_ image: NSImage, scale: CGFloat = 2) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func png(_ image: NSImage) throws -> Data {
        try #require(bitmap(image).representation(using: .png, properties: [:]))
    }

    private func pixel(in image: NSImage, xFraction: CGFloat, yFraction: CGFloat) throws -> NSColor {
        let rep = try bitmap(image)
        let color = try #require(rep.colorAt(
            x: Int(CGFloat(rep.pixelsWide) * xFraction), y: Int(CGFloat(rep.pixelsHigh) * yFraction)
        )?.usingColorSpace(.sRGB))
        return color
    }

    /// The item on a menu-bar-like strip, at 2x, so renders read like the real menu bar.
    private func menuBarStrip(_ image: NSImage, dark: Bool) throws -> Data {
        let inset: CGFloat = 12
        let size = NSSize(width: image.size.width + inset * 2, height: image.size.height + 8)
        let strip = NSImage(size: size, flipped: false) { rect in
            (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            rect.fill()
            image.draw(in: NSRect(x: inset, y: 4, width: image.size.width, height: image.size.height))
            return true
        }
        return try png(strip)
    }

    private func save(_ data: Data, name: String) throws {
        // The sandboxed test host can't write outside its container; with this opt-in the
        // PNG also goes to the test log as base64, for collection outside the sandbox.
        if ProcessInfo.processInfo.environment["GLIMPSE_RENDER_LOG"] == "1" {
            print("GLIMPSE_RENDER \(name).png \(data.base64EncodedString())")
        }
        // Native artifacts go to /tmp (see gotchas): never straight to a removable volume.
        let base = ProcessInfo.processInfo.environment["GLIMPSE_NEXT_MEETING_ARTIFACT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("next-meeting-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try data.write(to: base.appendingPathComponent(name + ".png"))
    }
}
