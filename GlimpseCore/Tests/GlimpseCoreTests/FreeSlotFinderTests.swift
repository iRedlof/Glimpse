import Foundation
import Testing

@testable import GlimpseCore

struct FreeSlotFinderTests {
    private let calendar = fixedCalendar()
    private let day = "2026-11-12"  // Thursday

    private func at(_ hhmm: String, _ iso: String? = nil) -> Date { instant(iso ?? day, hhmm, calendar) }

    private func busy(_ ranges: [(String, String)]) -> [DateInterval] {
        ranges.map { DateInterval(start: at($0.0), end: at($0.1)) }
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false, blocks: Bool = true) -> CalendarEvent {
        CalendarEvent(id: id, title: id, startDate: start, endDate: end, isAllDay: allDay, blocksTime: blocks)
    }

    private func draft(_ window: TimeWindow, minutes: Int = 30, on iso: String? = nil) -> EventDraft {
        EventDraft(title: "Coffee with Priya", day: civil(iso ?? day), window: window, durationMinutes: minutes)
    }

    private func starts(_ slots: [FreeSlot]) -> [Date] { slots.map(\.start) }

    private var earlyMorning: Date { at("06:00") }

    // MARK: - Windows

    @Test
    func windowsCoverNamedPartsOfDay() {
        #expect(FreeSlotFinder.window(for: draft(.partOfDay(.afternoon)), calendar: calendar)
            == DateInterval(start: at("13:00"), end: at("17:00")))
        #expect(FreeSlotFinder.window(for: draft(.partOfDay(.morning)), calendar: calendar)
            == DateInterval(start: at("09:00"), end: at("12:00")))
        #expect(FreeSlotFinder.window(for: draft(.unspecified), calendar: calendar)
            == DateInterval(start: at("09:00"), end: at("17:00")))
        #expect(FreeSlotFinder.window(for: draft(.between(clock("10:15"), clock("11:45"))), calendar: calendar)
            == DateInterval(start: at("10:15"), end: at("11:45")))
    }

    @Test
    func exactWindowIsClampedToTheDay() {
        let late = FreeSlotFinder.window(for: draft(.exact(clock("23:00")), minutes: 60), calendar: calendar)
        #expect(late == DateInterval(start: at("21:00"), end: at("00:00", "2026-11-13")))
        let early = FreeSlotFinder.window(for: draft(.exact(clock("01:00"))), calendar: calendar)
        #expect(early?.start == at("00:00"))
        #expect(early?.end == at("03:30"))
    }

    // MARK: - Slots

    @Test
    func storyAfternoonOffersTwoThreeThirtyAndFourFifteen() {
        let slots = FreeSlotFinder.slots(
            for: draft(.partOfDay(.afternoon)),
            events: [
                event("lunch run-over", at("13:00"), at("14:00")),
                event("design review", at("14:30"), at("15:30")),
                event("standup", at("16:00"), at("16:15")),
                event("gym", at("16:45"), at("17:30")),
            ],
            now: earlyMorning, calendar: calendar
        )
        #expect(starts(slots) == [at("14:00"), at("15:30"), at("16:15")])
        #expect(slots.allSatisfy { $0.end.timeIntervalSince($0.start) == 30 * 60 })
    }

    @Test
    func allDayAndFreeEventsDoNotBlock() {
        let events = [
            event("holiday", at("00:00"), at("00:00", "2026-11-13"), allDay: true),
            event("focus (free)", at("13:00"), at("17:00"), blocks: false),
            event("negative", at("15:00"), at("14:00")),
        ]
        #expect(FreeSlotFinder.busyIntervals(from: events).isEmpty)
        let slots = FreeSlotFinder.slots(for: draft(.partOfDay(.afternoon)), events: events,
                                         now: earlyMorning, calendar: calendar)
        #expect(starts(slots) == [at("13:00"), at("13:30"), at("14:00")])
    }

    @Test
    func overlappingBusyIntervalsAreMerged() {
        let slots = FreeSlotFinder.slots(
            busy: busy([("13:00", "14:30"), ("14:00", "15:00"), ("14:45", "15:15")]),
            window: DateInterval(start: at("13:00"), end: at("17:00")),
            duration: 30 * 60, notBefore: earlyMorning
        )
        #expect(starts(slots) == [at("15:15"), at("15:45"), at("16:15")])
    }

    @Test
    func pastTimesTodayAreSkippedAndRoundedUpToQuarterHours() {
        let slots = FreeSlotFinder.slots(
            busy: [], window: DateInterval(start: at("13:00"), end: at("17:00")),
            duration: 30 * 60, notBefore: at("14:07")
        )
        #expect(starts(slots) == [at("14:15"), at("14:45"), at("15:15")])
    }

    @Test
    func busyEndsOffTheGridAreRoundedUp() {
        let slots = FreeSlotFinder.slots(
            busy: busy([("13:00", "14:10")]), window: DateInterval(start: at("13:00"), end: at("15:00")),
            duration: 30 * 60, notBefore: earlyMorning
        )
        #expect(starts(slots) == [at("14:15")])
    }

    @Test
    func windowAlreadyOverReturnsNothing() {
        let slots = FreeSlotFinder.slots(
            busy: [], window: DateInterval(start: at("13:00"), end: at("17:00")),
            duration: 30 * 60, notBefore: at("16:50")
        )
        #expect(slots.isEmpty)
    }

    @Test
    func noGapLongEnoughReturnsNothing() {
        let slots = FreeSlotFinder.slots(
            busy: busy([("13:00", "16:45")]), window: DateInterval(start: at("13:00"), end: at("17:00")),
            duration: 30 * 60, notBefore: earlyMorning
        )
        #expect(slots.isEmpty)
    }

    @Test
    func durationLongerThanWindowReturnsNothing() {
        let slots = FreeSlotFinder.slots(for: draft(.partOfDay(.midday), minutes: 180), events: [],
                                         now: earlyMorning, calendar: calendar)
        #expect(slots.isEmpty)
    }

    @Test
    func singleGapIsFilledWithBackToBackOptions() {
        let slots = FreeSlotFinder.slots(
            busy: busy([("13:00", "15:00")]), window: DateInterval(start: at("13:00"), end: at("17:00")),
            duration: 30 * 60, notBefore: earlyMorning
        )
        #expect(starts(slots) == [at("15:00"), at("15:30"), at("16:00")])
    }

    @Test
    func longDurationsRespectTheDuration() {
        let slots = FreeSlotFinder.slots(
            busy: [], window: DateInterval(start: at("09:00"), end: at("17:00")),
            duration: 3 * 60 * 60, notBefore: earlyMorning
        )
        #expect(starts(slots) == [at("09:00"), at("12:00")])
    }

    @Test
    func exactTimeFreeComesFirst() {
        let slots = FreeSlotFinder.slots(for: draft(.exact(clock("14:00"))), events: [],
                                         now: earlyMorning, calendar: calendar)
        #expect(starts(slots) == [at("14:00"), at("13:30"), at("14:30")])
    }

    @Test
    func exactTimeBusyOffersNearestAlternatives() {
        let slots = FreeSlotFinder.slots(
            for: draft(.exact(clock("14:00"))), events: [event("1:1", at("14:00"), at("15:00"))],
            now: earlyMorning, calendar: calendar
        )
        #expect(starts(slots) == [at("13:30"), at("13:00"), at("15:00")])
    }

    @Test
    func slotsNeverCrossMidnight() {
        let slots = FreeSlotFinder.slots(for: draft(.exact(clock("23:30")), minutes: 60), events: [],
                                         now: earlyMorning, calendar: calendar)
        #expect(slots.first?.start == at("23:00"))
        #expect(slots.allSatisfy { $0.end <= at("00:00", "2026-11-13") })
    }

    @Test
    func eventsSpanningMidnightBlockTheMorning() {
        let slots = FreeSlotFinder.slots(
            for: draft(.partOfDay(.morning)),
            events: [event("red-eye", at("22:00", "2026-11-11"), at("10:00"))],
            now: at("06:00", "2026-11-11"), calendar: calendar
        )
        #expect(slots.first?.start == at("10:00"))
    }

    @Test
    func isFreeDetectsOverlapButAllowsTouching() {
        let busy = busy([("14:00", "15:00")])
        #expect(FreeSlotFinder.isFree(FreeSlot(start: at("13:30"), end: at("14:00")), busy: busy))
        #expect(FreeSlotFinder.isFree(FreeSlot(start: at("15:00"), end: at("15:30")), busy: busy))
        #expect(!FreeSlotFinder.isFree(FreeSlot(start: at("14:45"), end: at("15:15")), busy: busy))
        #expect(!FreeSlotFinder.isFree(FreeSlot(start: at("13:00"), end: at("16:00")), busy: busy))
    }

    @Test
    func neverMoreThanThree() {
        let slots = FreeSlotFinder.slots(
            busy: [], window: DateInterval(start: at("09:00"), end: at("17:00")),
            duration: 15 * 60, notBefore: earlyMorning
        )
        #expect(slots.count == FreeSlotFinder.maximumSlots)
    }

    @Test
    func blocksTimeDefaultsToTrueForExistingCallSites() {
        let event = CalendarEvent(id: "a", title: "a", startDate: at("09:00"), endDate: at("10:00"), isAllDay: false)
        #expect(event.blocksTime)
    }
}
