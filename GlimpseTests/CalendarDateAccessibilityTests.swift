import AppKit
import ComposableArchitecture
import GlimpseCore
import SwiftUI
import Testing

@testable import Glimpse

@Suite(.serialized) @MainActor
struct CalendarDateAccessibilityTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func datesExposeDistinctNativeActions(appearance: ColorScheme) async throws {
        let fixture = try DateAccessibilityFixture(appearance: appearance)
        defer { fixture.close() }
        try await fixture.host.settle()
        try fixture.host.loadAccessibilityWindowTree()
        let dates = fixture.dateButtons
        #expect(dates.count == 42, "Dates must have individual native actions; \(fixture.host.treeDescription)")
        #expect(Set(dates.compactMap(\.label)).count == 42)
        for (index, date) in dates.enumerated() {
            #expect(date.enabled)
            #expect(abs(date.frame.height - 30) < 0.5)
            #expect(date.frame.width > 28)
            for other in dates.dropFirst(index + 1) {
                #expect(!date.frame.intersects(other.frame))
            }
        }
        #expect(fixture.store.selectedDate == nil)
        #expect(fixture.store.displayedMonth == fixture.month)
        #expect(fixture.dateReceipts.value.isEmpty)
        #expect(fixture.eventReads.value == 0)
        #expect(fixture.host.elements().contains {
            $0.label == "Calendar grid for November 2030"
        })
    }

    @Test
    func defaultPressSelectsAndRepeatedPressDeselects() async throws {
        let fixture = try DateAccessibilityFixture()
        defer { fixture.close() }
        try await fixture.host.settle()
        let date = try fixture.date(month: 11, day: 4)
        let name = "Monday, November 4, 2030"
        let initial = try fixture.host.control(named: name)
        #expect(!initial.selected)
        #expect(initial.press())
        try await fixture.host.settle()
        #expect(fixture.store.selectedDate == date)
        #expect(fixture.store.displayedMonth == fixture.month)
        #expect(fixture.dateReceipts.value == [date])
        #expect(try fixture.host.control(named: name).selected)
        #expect(try fixture.host.control(named: name).press())
        try await fixture.host.settle()
        #expect(fixture.store.selectedDate == nil)
        #expect(fixture.store.displayedMonth == fixture.month)
        #expect(fixture.dateReceipts.value == [date, date])
        #expect(try !fixture.host.control(named: name).selected)
        #expect(fixture.eventReads.value == 0)
    }

    @Test
    func outsideMonthPressSelectsWithoutNavigatingOrReadingEvents() async throws {
        let fixture = try DateAccessibilityFixture()
        defer { fixture.close() }
        try await fixture.host.settle()
        let date = try fixture.date(month: 10, day: 31)
        let name = "Thursday, October 31, 2030, outside current month"
        #expect(try fixture.host.control(named: name).press())
        try await fixture.host.settle()
        #expect(fixture.store.selectedDate == date)
        #expect(fixture.store.displayedMonth == fixture.month)
        #expect(fixture.dateReceipts.value == [date])
        #expect(try fixture.host.control(named: name).selected)
        #expect(fixture.eventReads.value == 0)
        #expect(!fixture.store.calendarAccessGranted)
    }

    @Test(arguments: IconClickPosition.allCases)
    func pointerPressDispatchesOnceAtCenterAndInsetEdges(
        position: IconClickPosition
    ) async throws {
        let fixture = try DateAccessibilityFixture()
        defer { fixture.close() }
        try await fixture.host.settle()
        let date = try fixture.date(month: 11, day: 4)
        let node = try fixture.host.control(named: "Monday, November 4, 2030")
        try await fixture.host.click(atScreenPoint: position.point(in: node.frame))
        #expect(fixture.store.selectedDate == date)
        #expect(fixture.dateReceipts.value == [date])
        #expect(fixture.store.displayedMonth == fixture.month)
        #expect(fixture.eventReads.value == 0)
    }
}

/// Hosts the real calendar root; only external dependencies are isolated.
@MainActor
private final class DateAccessibilityFixture {
    let month: Date
    let store: StoreOf<CalendarFeature>
    let host: AccessibilityTestHost
    let dateReceipts = LockIsolated<[Date]>([])
    let eventReads = LockIsolated(0)

    var dateButtons: [AccessibilityTestNode] {
        host.elements().filter { $0.role == .button && $0.label?.contains("2030") == true }
    }

    init(appearance: ColorScheme = .light) throws {
        month = try #require(Calendar.current.date(from: DateComponents(
            year: 2030, month: 11, day: 15, hour: 12
        )))
        let receipts = dateReceipts
        let reads = eventReads
        let fixedToday = month
        store = Store(initialState: CalendarFeature.State(displayedMonth: month)) {
            Reduce<CalendarFeature.State, CalendarFeature.Action> { _, action in
                if case let .dateTapped(date) = action {
                    receipts.withValue { $0.append(date) }
                }
                return .none
            }
            CalendarFeature()
        } withDependencies: {
            $0.date = .constant(fixedToday)
            $0.calendarClient = .liveValue // Pure calendar generation, no OS/service I/O.
            $0.calendarClient.menuBarDateString = { _, _ in
                Issue.record("Date fixture must not render a production status item")
                return ""
            }
            $0.preferencesClient = .testValue
            $0.preferencesClient.loadStartOfWeekday = { 1 }
            $0.preferencesClient.loadWorkdays = { [2, 3, 4, 5, 6] }
            $0.preferencesClient.loadShowAISearch = { false }
            $0.eventKitClient = EventKitClient(
                requestAccess: {
                    Issue.record("Date fixture must not request calendar access")
                    return false
                },
                fetchEvents: { _ in
                    reads.withValue { $0 += 1 }
                    Issue.record("Unauthorized date fixture must not read calendar events")
                    return []
                },
                authorizationStatus: { .notDetermined }
            )
        }
        let calendarStore = store
        let aiModel = AIDateQueryModel(
            client: AIDateQueryClient(
                resolveProvider: { _ in
                    Issue.record("Date fixture must not resolve an AI provider")
                    return .none
                },
                interpret: { _, _ in
                    Issue.record("Date fixture must not request an AI date")
                    return nil
                }
            ),
            enabled: false, preference: .auto,
            onIntent: { _ in Issue.record("Date fixture must not receive an AI date") }
        )
        host = AccessibilityTestHost(width: 316, height: 550) {
            CalendarPopoverView(
                store: calendarStore,
                aiQueryModel: aiModel, loadAISettings: { (false, .auto) }
            )
                .environment(\.colorScheme, appearance)
        }
    }

    func date(month: Int, day: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(
            year: 2030, month: month, day: day
        )))
    }

    func close() {
        host.hosting.rootView = AnyView(EmptyView())
        host.close()
    }
}
