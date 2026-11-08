import AppKit
import ComposableArchitecture
import EventKit
import GlimpseCore
import SwiftUI
import Testing
@testable import Glimpse

// MARK: - Return routing (honest button)

struct AISubmitRouterTests {
    @Test
    func pickedTimeConfirms() {
        #expect(AISubmitRouter.route(phase: .choosing, canConfirm: true) == .confirm)
    }

    @Test(arguments: [ScheduleFeature.Phase.choosing, .saving, .searching, .requestingAccess])
    func returnWithoutAPickOrWhileBusyDoesNothing(_ phase: ScheduleFeature.Phase) {
        #expect(AISubmitRouter.route(phase: phase, canConfirm: false) == .ignore)
    }

    @Test
    func needsAccessReturnIsTheExplicitAllowAction() {
        #expect(AISubmitRouter.route(phase: .needsAccess, canConfirm: false) == .allowAccess)
    }

    @Test(arguments: [ScheduleFeature.Phase.idle, .noSlots, .failed(.saveFailed), .accessUnavailable(.denied)])
    func otherwiseReturnSubmitsTheDraft(_ phase: ScheduleFeature.Phase) {
        #expect(AISubmitRouter.route(phase: phase, canConfirm: false) == .submit)
    }
}

// MARK: - Key routing

struct ScheduleKeyRoutingTests {
    @Test
    func arrowsPickSlotsOnlyWhileChoosingInTheEditor() {
        func route(_ key: CalendarKeyboardKey, choosing: Bool = true, open: Bool = true,
                   editing: Bool = true, modified: Bool = false,
                   phase: CalendarKeyboardPhase = .down) -> CalendarKeyboardRoute {
            CalendarKeyboardRouter.slotPicker(key, phase: phase, choosingSlots: choosing, editorOpen: open,
                                              editingText: editing, modified: modified)
        }
        #expect(route(.down) == .move(1))
        #expect(route(.up) == .move(-1))
        #expect(route(.down, phase: .repeatPress) == .move(1))
        #expect(route(.down, phase: .up) == .yield)
        #expect(route(.down, choosing: false) == .yield)
        #expect(route(.down, open: false) == .yield)
        #expect(route(.down, editing: false) == .yield)
        #expect(route(.down, modified: true) == .yield)
        for key in [CalendarKeyboardKey.left, .right, .returnKey, .keypadEnter, .space, .tab, .other] {
            #expect(route(key) == .yield)
        }
    }

    @Test
    func commandZUndoesOnlyOutsideTextEditing() {
        let z = CalendarKeyboardRouter.undoKeyCode
        #expect(CalendarKeyboardRouter.undoesAddedEvent(keyCode: z, commandOnly: true, canUndo: true, editingText: false))
        #expect(!CalendarKeyboardRouter.undoesAddedEvent(keyCode: z, commandOnly: true, canUndo: true, editingText: true))
        #expect(!CalendarKeyboardRouter.undoesAddedEvent(keyCode: z, commandOnly: true, canUndo: false, editingText: false))
        #expect(!CalendarKeyboardRouter.undoesAddedEvent(keyCode: z, commandOnly: false, canUndo: true, editingText: false))
        #expect(!CalendarKeyboardRouter.undoesAddedEvent(keyCode: 5, commandOnly: true, canUndo: true, editingText: false))
    }
}

// MARK: - Copy

struct ScheduleCopyTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()
    private static let day = CivilDate(year: 2026, month: 11, day: 12)!
    private static let draft = EventDraft(title: "Coffee with Priya", day: day, window: .partOfDay(.afternoon),
                                          durationMinutes: 30)
    private static let work = WritableCalendar(id: "w", title: "Work")

    private static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour, minute: minute))!
    }

    @Test
    func draftLineNamesTheTargetCalendar() {
        #expect(ScheduleCopy.draftLine(Self.draft, calendar: Self.work) == "Coffee with Priya · 30 min · saves to Work")
        #expect(ScheduleCopy.draftLine(Self.draft, calendar: nil) == "Coffee with Priya · 30 min")
    }

    @Test
    func headerAndCountsReadNaturally() {
        #expect(ScheduleCopy.header(for: Self.draft, calendar: Self.calendar).hasSuffix("· afternoon"))
        #expect(ScheduleCopy.freeTimes(1) == "1 free time")
        #expect(ScheduleCopy.freeTimes(3) == "3 free times")
        #expect(ScheduleCopy.duration(90) == "1 h 30 min")
        #expect(ScheduleCopy.duration(60) == "1 h")
        #expect(ScheduleCopy.windowName(.between(ClockTime(hour: 14, minute: 0)!, ClockTime(hour: 17, minute: 30)!))
            == "14:00–17:30")
    }

    @Test
    func slotLabelSaysWhatWillHappen() {
        let slot = FreeSlot(start: Self.at(14), end: Self.at(14, 30))
        let label = ScheduleCopy.slotAccessibilityLabel(slot, title: "Coffee with Priya", calendar: Self.work)
        #expect(label.hasPrefix("Add Coffee with Priya, "))
        #expect(label.contains(" to "))
        #expect(label.hasSuffix(", to Work"))
        #expect(label.contains(Self.at(14).formatted(.dateTime.weekday(.wide))))
    }

    @Test
    func noSlotsSuggestsAnotherTime() {
        let text = ScheduleCopy.noSlots(Self.draft, calendar: Self.calendar)
        #expect(text.hasPrefix("No free 30 min time "))
        #expect(text.hasSuffix(" afternoon. Try another time."))
    }

    @Test(arguments: [EKAuthorizationStatus.denied, .restricted, .writeOnly])
    func deniedAccessIsExplained(_ status: EKAuthorizationStatus) {
        #expect(!ScheduleCopy.accessUnavailable(status).isEmpty)
        #expect(ScheduleCopy.accessUnavailable(status).hasSuffix("."))
    }

    @Test
    func undoCountdownIsSpoken() {
        #expect(ScheduleCopy.undoButton(remaining: 10) == "Undo 10")
        #expect(ScheduleCopy.undoAccessibilityValue(remaining: 10) == "10 seconds left")
        #expect(ScheduleCopy.undoAccessibilityValue(remaining: 1) == "1 second left")
    }

    @Test
    func timelineInterleavesBusyAndFreeInOrder() {
        let events = [
            CalendarEvent(id: "a", title: "Lunch", startDate: Self.at(13), endDate: Self.at(14), isAllDay: false),
            CalendarEvent(id: "b", title: "Review", startDate: Self.at(14, 30), endDate: Self.at(15, 30), isAllDay: false),
        ]
        let slots = [FreeSlot(start: Self.at(14), end: Self.at(14, 30)), FreeSlot(start: Self.at(15, 30), end: Self.at(16))]
        let rows = ScheduleTimeline.rows(events: events, slots: slots)
        #expect(rows.map(\.start) == [Self.at(13), Self.at(14), Self.at(14, 30), Self.at(15, 30)])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test
    func rangeSummaryListsAndCountsOtherMonths() {
        let dates = [13, 20, 27].map { CivilDate(year: 2026, month: 11, day: $0)! }
            + [CivilDate(year: 2026, month: 12, day: 4)!, CivilDate(year: 2026, month: 12, day: 11)!]
        let summary = AIRangeSummary(highlight: DateRangeHighlight(dates: dates, label: "Fridays"),
                                     displayedMonth: Self.at(12), calendar: Self.calendar)
        #expect(summary.outsideMonth == 2)
        #expect(summary.count == 5)
        #expect(summary.listed.hasSuffix(", …"))
        #expect(summary.accessibilityLabel(label: "Fridays").hasPrefix("Highlighted 5 days: Fridays, "))
    }

    @Test
    func highlightedDaysSayWhy() {
        let fridays = DateRangeHighlight(dates: [Self.day], label: "Next Friday")
        #expect(CalendarPopoverView.highlightSuffix(fridays) == ", highlighted, Next Friday")
        #expect(CalendarPopoverView.highlightSuffix(nil) == ", highlighted")
    }

    @Test
    func scheduleTokensAreSane() {
        #expect((0.05...0.4).contains(AppDesign.Grid.rangeHighlightOpacity))
        #expect(AppDesign.Schedule.slotRowHeight >= AppDesign.Control.dismissTargetSize)
        #expect(AppDesign.Schedule.selectedLineWidth > AppDesign.Schedule.ghostLineWidth)
        #expect(AppDesign.Schedule.ghostDash.count == 2)
        #expect((1...6).contains(AppDesign.Schedule.maximumContextEvents))
        #expect(AppDesign.Schedule.maximumListedDates >= 3)
    }
}

// MARK: - Accessibility

@Suite(.serialized) @MainActor
struct ScheduleProposalAccessibilityTests {
    private static let day = CivilDate(year: 2026, month: 11, day: 12)!
    private static let draft = EventDraft(title: "Coffee with Priya", day: day, window: .partOfDay(.afternoon),
                                          durationMinutes: 30)

    private static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour, minute: minute))!
    }

    private func host(_ state: ScheduleFeature.State) -> (AccessibilityTestHost, StoreOf<ScheduleFeature>) {
        let store = Store(initialState: state) { EmptyReducer<ScheduleFeature.State, ScheduleFeature.Action>() }
        let host = AccessibilityTestHost(width: 300, height: 360) {
            ScheduleProposalView(store: store, calendar: .current)
        }
        return (host, store)
    }

    private func choosing(selected: Int?) -> ScheduleFeature.State {
        var state = ScheduleFeature.State()
        state.draft = Self.draft
        state.phase = .choosing
        state.calendar = WritableCalendar(id: "w", title: "Work")
        state.slots = [FreeSlot(start: Self.at(14), end: Self.at(14, 30)),
                       FreeSlot(start: Self.at(15, 30), end: Self.at(16))]
        state.dayEvents = [CalendarEvent(id: "a", title: "Lunch", startDate: Self.at(13), endDate: Self.at(14),
                                         isAllDay: false)]
        state.selectedSlotIndex = selected
        return state
    }

    @Test
    func everySlotIsALabelledButtonAndOnlyThePickIsSelected() async throws {
        let (host, _) = host(choosing(selected: 1))
        defer { host.close() }
        try await host.settle(until: {
            host.elements().filter { $0.role == .button && ($0.label ?? "").hasPrefix("Add Coffee") }.count == 2
        })
        let slots = host.elements().filter { $0.role == .button && ($0.label ?? "").hasPrefix("Add Coffee") }
        #expect(slots.allSatisfy { ($0.label ?? "").hasSuffix(", to Work") })
        #expect(slots.filter { $0.selected }.count == 1)
        #expect(slots.last?.selected == true)
        #expect(host.elements().contains { ($0.label ?? "").hasPrefix("Busy: Lunch") })
    }

    @Test
    func noPickShowsTheHintAndNothingIsSelected() async throws {
        let (host, _) = host(choosing(selected: nil))
        defer { host.close() }
        try await host.settle(until: {
            host.elements().contains { ($0.label ?? "") == ScheduleCopy.choosingHint || ($0.value as? String) == ScheduleCopy.choosingHint }
        })
        let slots = host.elements().filter { $0.role == .button && ($0.label ?? "").hasPrefix("Add Coffee") }
        #expect(!slots.contains { $0.selected })
    }

    @Test
    func needsAccessOffersOneLabelledAllowButton() async throws {
        var state = ScheduleFeature.State()
        state.draft = Self.draft
        state.phase = .needsAccess
        let (host, _) = host(state)
        defer { host.close() }
        try await host.settle(until: { !host.controls(named: "Allow calendar access to find free times").isEmpty })
        let allow = try host.control(named: "Allow calendar access to find free times")
        #expect(allow.enabled)
    }

    @Test
    func undoChipCountsDownForVoiceOver() async throws {
        let saved = SavedEvent(eventID: "e", title: "Coffee with Priya", start: Self.at(14), end: Self.at(14, 30),
                               calendarTitle: "Work")
        var undone = 0
        let host = AccessibilityTestHost(width: 300, height: 80) {
            ScheduleUndoChip(chip: .init(event: saved, remaining: 7, status: .available)) { undone += 1 }
        }
        defer { host.close() }
        try await host.settle(until: { !host.controls(named: "Undo adding Coffee with Priya").isEmpty })
        let button = try host.control(named: "Undo adding Coffee with Priya")
        #expect(button.value as? String == "7 seconds left")
        #expect(button.press())
        #expect(undone == 1)
    }

    @Test
    func answerRowReadsAsOneSentence() async throws {
        let answer = DateAnswer(text: "80 workdays", detail: "Nov 8 → Mar 1, 2027 · Mon–Fri · holidays not counted")
        let host = AccessibilityTestHost(width: 300, height: 80) { AIAnswerRow(answer: answer) }
        defer { host.close() }
        try await host.settle(until: { host.elements().contains { $0.label == answer.accessibilityLabel } })
        #expect(answer.accessibilityLabel == "Answer: 80 workdays. Nov 8 to Mar 1, 2027, Mon–Fri, holidays not counted")
    }

    @Test
    func clarificationIsAnnouncedAsAQuestion() async throws {
        let host = AccessibilityTestHost(width: 300, height: 80) { AIClarificationRow(message: "Which day?") }
        defer { host.close() }
        // Static text exposes its text as the value or label depending on the host.
        try await host.settle(until: {
            host.elements().contains {
                $0.role == .staticText
                    && ($0.label == "Glimpse asks: Which day?" || $0.value as? String == "Glimpse asks: Which day?")
            }
        })
    }
}
