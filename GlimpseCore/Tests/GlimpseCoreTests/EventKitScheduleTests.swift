import EventKit
import Foundation
import Testing

@testable import GlimpseCore

struct EventKitScheduleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func timedEvent() -> EKEvent {
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Design review"
        event.startDate = start
        event.endDate = start.addingTimeInterval(3_600)
        return event
    }

    @Test
    func onlyTimedNonFreeEventsBlockTime() {
        #expect(EventKitClient.blocksTime(isAllDay: false, availability: .busy))
        #expect(EventKitClient.blocksTime(isAllDay: false, availability: .tentative))
        #expect(EventKitClient.blocksTime(isAllDay: false, availability: .unavailable))
        // Events outside a calendar report notSupported; treat them as busy.
        #expect(EventKitClient.blocksTime(isAllDay: false, availability: .notSupported))
        #expect(!EventKitClient.blocksTime(isAllDay: false, availability: .free))
        #expect(!EventKitClient.blocksTime(isAllDay: true, availability: .busy))
    }

    @Test
    func conversionCarriesBlocksTime() throws {
        let timed = timedEvent()
        #expect(try #require(EventKitClient.calendarEvent(from: timed)).blocksTime)
        let allDay = timedEvent()
        allDay.isAllDay = true
        #expect(try !#require(EventKitClient.calendarEvent(from: allDay)).blocksTime)
    }

    @Test
    func deniedStoreRefusesEveryScheduleOperationWithoutTouchingEventKit() async {
        let store = EventStore(authorizationStatus: { .denied })
        let saved = SavedEvent(eventID: "x", title: "Coffee", start: start, end: start.addingTimeInterval(1_800),
                               calendarTitle: "Work")
        await #expect(throws: ScheduleError.accessUnavailable) {
            try await store.fetchEvents(in: DateInterval(start: start, duration: 3_600))
        }
        await #expect(throws: ScheduleError.accessUnavailable) { try await store.defaultWritableCalendar() }
        await #expect(throws: ScheduleError.accessUnavailable) {
            try await store.save(NewEvent(title: "Coffee", start: start, end: start.addingTimeInterval(1_800),
                                          calendarID: "cal"))
        }
        await #expect(throws: ScheduleError.accessUnavailable) { try await store.remove(saved) }
    }

    @Test(arguments: [EKAuthorizationStatus.writeOnly, .restricted, .notDetermined])
    func partialAccessIsNotEnoughToSchedule(_ status: EKAuthorizationStatus) async {
        let store = EventStore(authorizationStatus: { status })
        await #expect(throws: ScheduleError.accessUnavailable) { try await store.defaultWritableCalendar() }
    }

    @Test
    func defaultCalendarIsPreferredWhenWritable() {
        let work = EventKitClient.CalendarCandidate(id: "w", title: "Work", allowsModifications: true)
        let home = EventKitClient.CalendarCandidate(id: "h", title: "Home", allowsModifications: true)
        #expect(EventKitClient.preferredWritableCalendar(default: work, all: [home, work])
            == WritableCalendar(id: "w", title: "Work"))
    }

    @Test
    func readOnlyDefaultFallsBackToFirstWritable() {
        let holidays = EventKitClient.CalendarCandidate(id: "hol", title: "Holidays", allowsModifications: false)
        let home = EventKitClient.CalendarCandidate(id: "h", title: "Home", allowsModifications: true)
        #expect(EventKitClient.preferredWritableCalendar(default: holidays, all: [holidays, home])
            == WritableCalendar(id: "h", title: "Home"))
        #expect(EventKitClient.preferredWritableCalendar(default: nil, all: [holidays]) == nil)
    }

    @Test
    func savedEventRequiresAnIdentifier() {
        let new = NewEvent(title: "Coffee", start: start, end: start.addingTimeInterval(1_800), calendarID: "w")
        #expect(EventKitClient.savedEvent(identifier: nil, new: new, calendarTitle: "Work") == nil)
        #expect(EventKitClient.savedEvent(identifier: "", new: new, calendarTitle: "Work") == nil)
        #expect(EventKitClient.savedEvent(identifier: "id-1", new: new, calendarTitle: "Work")
            == SavedEvent(eventID: "id-1", title: "Coffee", start: new.start, end: new.end, calendarTitle: "Work"))
    }

    @Test
    func unknownErrorsMapToTheOperationFallback() {
        struct Opaque: Error {}
        #expect(ScheduleError.from(Opaque(), fallback: .saveFailed) == .saveFailed)
        #expect(ScheduleError.from(ScheduleError.slotTaken, fallback: .saveFailed) == .slotTaken)
        #expect(ScheduleError.from(EventKitClient.QueryError.accessUnavailable, fallback: .searchFailed)
            == .accessUnavailable)
    }

    @Test
    func everyErrorHasAPlainMessage() {
        let all: [ScheduleError] = [.accessUnavailable, .noWritableCalendar, .calendarReadOnly, .slotTaken,
                                    .saveFailed, .eventMissing, .removeFailed, .searchFailed]
        for error in all {
            #expect(!error.message.isEmpty)
            #expect(error.message.hasSuffix("."))
        }
        #expect(ScheduleError.saveFailed.message == "Couldn't add the event. Nothing was saved.")
        #expect(ScheduleError.slotTaken.message == "That time just filled up. Pick another.")
    }
}
