import Foundation
import Testing

@testable import GlimpseCore

struct AIIntentDecoderTests {
    private let today = civil("2026-11-08")

    private func decode(_ text: String) -> AIIntent? {
        AIIntentDecoder.decode(text: text, today: today)
    }

    @Test
    func navigate() {
        #expect(decode(#"{"intent":"navigate","date":"2026-11-13"}"#) == .navigate(civil("2026-11-13")))
    }

    @Test(arguments: ["2026-11-13", " 2026-11-13\n", "`2026-11-13`", "\"2026-11-13\".", "```\n2026-11-13\n```"])
    func legacyBareDateIsNavigate(_ text: String) {
        #expect(decode(text) == .navigate(civil("2026-11-13")))
    }

    @Test
    func jsonInsideFencesAndProse() {
        let text = """
        Sure! Here you go:
        ```json
        {"intent": "navigate", "date": "2026-12-25", "note": "has {braces} and \\"quotes\\""}
        ```
        Let me know if you need anything else {not json}.
        """
        #expect(decode(text) == .navigate(civil("2026-12-25")))
    }

    @Test
    func rangeIsSortedDedupedAndCapped() {
        let dates = (1...40).map { civil("2026-12-01").adding(days: $0)!.iso }.reversed() + ["2026-12-05", "bad"]
        let json = #"{"intent":"range","label":"Lots","dates":[""# + dates.joined(separator: #"",""#) + #""]}"#
        guard case let .range(highlight) = decode(json) else {
            Issue.record("expected range")
            return
        }
        #expect(highlight.dates.count == DateRangeHighlight.maximumDates)
        #expect(highlight.dates == highlight.dates.sorted())
        #expect(Set(highlight.dates).count == highlight.dates.count)
        #expect(highlight.dates.first == civil("2026-12-02"))
        #expect(highlight.label == "Lots")
    }

    @Test
    func rangeOfFridays() {
        let json = #"{"intent":"range","dates":["2026-11-27","2026-11-13","2026-11-20"],"label":"Next 3 Fridays"}"#
        #expect(decode(json) == .range(DateRangeHighlight(
            dates: [civil("2026-11-13"), civil("2026-11-20"), civil("2026-11-27")], label: "Next 3 Fridays"
        )))
    }

    @Test
    func rangeWithoutLabelGetsDefault() {
        guard case let .range(highlight) = decode(#"{"intent":"range","dates":["2026-11-13"]}"#) else {
            Issue.record("expected range")
            return
        }
        #expect(highlight.label == DateRangeHighlight.defaultLabel)
    }

    @Test(arguments: [#"{"intent":"range","dates":[]}"#, #"{"intent":"range"}"#, #"{"intent":"range","dates":["nope"]}"#])
    func emptyRangeIsUnparsed(_ json: String) {
        #expect(decode(json) == nil)
    }

    @Test
    func questionKinds() {
        #expect(decode(#"{"intent":"question","question":"countWorkdays","from":"2026-11-08","to":"2027-03-01"}"#)
            == .question(.count(.workdays, from: civil("2026-11-08"), to: civil("2027-03-01"))))
        #expect(decode(#"{"intent":"question","question":"countDays","from":"2026-11-08","to":"2026-12-25"}"#)
            == .question(.count(.days, from: civil("2026-11-08"), to: civil("2026-12-25"))))
        #expect(decode(#"{"intent":"question","question":"countWeekendDays","from":"2026-11-08","to":"2026-12-25"}"#)
            == .question(.count(.weekendDays, from: civil("2026-11-08"), to: civil("2026-12-25"))))
        #expect(decode(#"{"intent":"question","question":"weekNumber","date":"2026-11-13"}"#)
            == .question(.weekNumber(civil("2026-11-13"))))
        #expect(decode(#"{"intent":"question","question":"weekday","date":"2027-03-01"}"#)
            == .question(.weekday(civil("2027-03-01"))))
    }

    @Test
    func questionDefaultsMissingStartAndDayToToday() {
        #expect(decode(#"{"intent":"question","question":"countDays","to":"2026-11-18"}"#)
            == .question(.count(.days, from: today, to: civil("2026-11-18"))))
        #expect(decode(#"{"intent":"question","question":"weekNumber"}"#) == .question(.weekNumber(today)))
    }

    @Test
    func questionSwapsReversedBounds() {
        #expect(decode(#"{"intent":"question","question":"countDays","from":"2026-12-25","to":"2026-11-08"}"#)
            == .question(.count(.days, from: civil("2026-11-08"), to: civil("2026-12-25"))))
    }

    @Test(arguments: [#"{"intent":"question","question":"moonPhase","date":"2026-11-08"}"#,
                      #"{"intent":"question","question":"countDays"}"#])
    func unanswerableQuestionAsksForClarification(_ json: String) {
        #expect(decode(json) == .clarify(AIIntentDecoder.unsupportedQuestionMessage))
    }

    @Test
    func createWithPartOfDay() {
        let json = #"{"intent":"create","title":" Coffee with Priya ","date":"2026-11-12","partOfDay":"afternoon","durationMinutes":30}"#
        #expect(decode(json) == .create(EventDraft(
            title: "Coffee with Priya", day: civil("2026-11-12"), window: .partOfDay(.afternoon), durationMinutes: 30
        )))
    }

    @Test
    func createWithExactStart() {
        let json = #"{"intent":"create","title":"Lunch","date":"2026-11-10","start":"13:00","end":null,"durationMinutes":60}"#
        #expect(decode(json) == .create(EventDraft(
            title: "Lunch", day: civil("2026-11-10"), window: .exact(clock("13:00")), durationMinutes: 60
        )))
    }

    @Test
    func createWithStartAndEndIsThatExactSpan() {
        let json = #"{"intent":"create","title":"Review","date":"2026-11-10","start":"14:00","end":"15:30"}"#
        #expect(decode(json) == .create(EventDraft(
            title: "Review", day: civil("2026-11-10"), window: .exact(clock("14:00")), durationMinutes: 90
        )))
    }

    @Test
    func createWithShorterDurationInsideStartAndEndIsBetween() {
        let json = #"{"intent":"create","title":"Call","date":"2026-11-10","start":"14:00","end":"17:00","durationMinutes":30}"#
        #expect(decode(json) == .create(EventDraft(
            title: "Call", day: civil("2026-11-10"), window: .between(clock("14:00"), clock("17:00")), durationMinutes: 30
        )))
    }

    @Test(arguments: [#""start":"15:00","end":"14:00""#, #""start":"14:00","end":"14:00""#,
                      #""start":"14:00","end":"14:30","durationMinutes":60"#])
    func createWithImpossibleSpanAsksForTime(_ fields: String) {
        let json = #"{"intent":"create","title":"Call","date":"2026-11-10","# + fields + "}"
        #expect(decode(json) == .clarify(AIIntentDecoder.timeMessage))
    }

    @Test
    func createWithoutTimeUsesWorkingHoursAndDefaultDuration() {
        let json = #"{"intent":"create","title":"Dentist","date":"2026-11-10"}"#
        #expect(decode(json) == .create(EventDraft(
            title: "Dentist", day: civil("2026-11-10"), window: .unspecified,
            durationMinutes: EventDraft.defaultDurationMinutes
        )))
    }

    @Test(arguments: [0, 4, 481, -30, 10_000])
    func createWithOutOfRangeDurationAsksHowLong(_ minutes: Int) {
        let json = #"{"intent":"create","title":"Gym","date":"2026-11-10","durationMinutes":"# + "\(minutes)}"
        #expect(decode(json) == .clarify(AIIntentDecoder.durationMessage))
    }

    @Test(arguments: [#""title":"   ""#, #""title":"""#, #""note":"x""#])
    func createWithoutTitleAsksForOne(_ field: String) {
        let json = #"{"intent":"create","date":"2026-11-10","# + field + "}"
        #expect(decode(json) == .clarify(AIIntentDecoder.titleMessage))
    }

    @Test
    func createWithoutDayAsksForOne() {
        #expect(decode(#"{"intent":"create","title":"Lunch"}"#) == .clarify(AIIntentDecoder.dayMessage))
    }

    @Test
    func createOnPastDayAsksAgainButTodayIsFine() {
        #expect(decode(#"{"intent":"create","title":"Lunch","date":"2026-11-07"}"#)
            == .clarify(AIIntentDecoder.pastDayMessage))
        #expect(decode(#"{"intent":"create","title":"Lunch","date":"2026-11-08"}"#) != .clarify(AIIntentDecoder.pastDayMessage))
    }

    @Test
    func createTitleIsSingleLineAndCapped() {
        let long = String(repeating: "a", count: 300)
        let json = #"{"intent":"create","title":"Line one\nline\ttwo "# + long + #"","date":"2026-11-10"}"#
        guard case let .create(draft) = decode(json) else {
            Issue.record("expected create")
            return
        }
        #expect(!draft.title.contains("\n"))
        #expect(draft.title.hasPrefix("Line one line two a"))
        #expect(draft.title.count == EventDraft.maximumTitleLength)
    }

    @Test
    func createUnknownPartOfDayFallsBackToWorkingHours() {
        let json = #"{"intent":"create","title":"Walk","date":"2026-11-10","partOfDay":"teatime"}"#
        #expect(decode(json) == .create(EventDraft(
            title: "Walk", day: civil("2026-11-10"), window: .unspecified, durationMinutes: 30
        )))
    }

    @Test
    func clarifyIsSanitized() {
        let long = String(repeating: "why ", count: 60)
        guard case let .clarify(message) = decode(#"{"intent":"clarify","message":"Which\n\n day?  "# + long + #""}"#) else {
            Issue.record("expected clarify")
            return
        }
        #expect(message.hasPrefix("Which day? why"))
        #expect(!message.contains("\n"))
        #expect(message.count <= AIIntentDecoder.maximumClarifyLength)
        #expect(message.hasSuffix("…"))
    }

    @Test(arguments: [#"{"intent":"clarify","message":"  \n "}"#, #"{"intent":"clarify"}"#])
    func emptyClarifyUsesDefaultLine(_ json: String) {
        #expect(decode(json) == .clarify(AIIntentDecoder.defaultClarifyMessage))
    }

    @Test(arguments: [#"{"intent":"delete","date":"2026-11-10"}"#, #"{"date":"2026-11-10"}"#, "I can't help with that.",
                      "{", "}{", "{\"intent\":", "null", "[1,2]", "", "Friday 2026-11-13 maybe",
                      #"{"intent":"navigate","date":"13/11/2026"}"#, #"{"intent":"navigate"}"#,
                      #"{"intent":5}"#])
    func garbageIsUnparsed(_ text: String) {
        #expect(decode(text) == nil)
    }

    @Test
    func datesBeyondHundredYearsAreRejected() {
        #expect(decode(#"{"intent":"navigate","date":"2127-01-01"}"#) == nil)
        #expect(decode(#"{"intent":"navigate","date":"1925-01-01"}"#) == nil)
        #expect(decode(#"{"intent":"navigate","date":"2126-11-08"}"#) == .navigate(civil("2126-11-08")))
        #expect(decode(#"{"intent":"navigate","date":"1926-11-08"}"#) == .navigate(civil("1926-11-08")))
    }

    @Test
    func intentNameIsCaseInsensitive() {
        #expect(decode(#"{"intent":" Navigate ","date":"2026-11-13"}"#) == .navigate(civil("2026-11-13")))
    }

    @Test
    func validateTakesWireDirectly() {
        var wire = AIIntentWire(intent: "navigate")
        wire.date = "2026-11-13"
        #expect(AIIntentDecoder.validate(wire, today: today) == .navigate(civil("2026-11-13")))
    }

    // MARK: - Reply length (untrusted)

    @Test
    func replyIsCappedBeforeScanning() {
        let padding = String(repeating: "{", count: AIIntentDecoder.maximumReplyLength)
        #expect(decode(padding + #"{"intent":"navigate","date":"2026-11-13"}"#) == nil)
        let fits = String(repeating: " ", count: 100) + #"{"intent":"navigate","date":"2026-11-13"}"#
        #expect(decode(fits) == .navigate(civil("2026-11-13")))
    }

    @Test
    func manyBracesStayFast() {
        let text = String(repeating: "{", count: 200_000)
        let start = ContinuousClock.now
        #expect(decode(text) == nil)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    // MARK: - Golden: real wrong replies from the on-device model (2026-11-08, a Sunday)

    private func validate(_ wire: AIIntentWire, query: String) -> AIIntent? {
        AIIntentDecoder.validate(wire, today: today, query: query)
    }

    @Test
    func nextFridayIsFridayEvenWhenTheModelSaysTuesday() {
        let wire = AIIntentWire(intent: "navigate", date: "2026-11-10")
        #expect(validate(wire, query: "next Friday") == .navigate(civil("2026-11-13")))
    }

    @Test
    func nextThreeFridaysAreFridaysEvenWhenTheModelGivesTuesdays() {
        let wire = AIIntentWire(intent: "range", dates: ["2026-11-10", "2026-11-17", "2026-11-24"],
                                label: "Next 3 Fridays")
        #expect(validate(wire, query: "next 3 Fridays") == .range(DateRangeHighlight(
            dates: [civil("2026-11-13"), civil("2026-11-20"), civil("2026-11-27")], label: "Next 3 Fridays"
        )))
    }

    @Test
    func modelWeekdayAndCountBuildTheSeriesWhenTheWordsDoNot() {
        let wire = AIIntentWire(intent: "range", dates: ["2026-11-11"], weekday: "Friday", count: 2, label: "Fridays")
        #expect(validate(wire, query: "a couple of Fridays") == .range(DateRangeHighlight(
            dates: [civil("2026-11-13"), civil("2026-11-20")], label: "Fridays"
        )))
    }

    @Test
    func workdaysUntilMarchFirstIsAnsweredWhenTheModelDropsTheKindAndYear() {
        // Recorded: question kind missing, title "workdays", to in the past year.
        let wire = AIIntentWire(intent: "question", from: "2026-11-08", to: "2026-03-01", title: "workdays",
                                message: "how many workdays until Mar 1?")
        #expect(validate(wire, query: "how many workdays until Mar 1?")
            == .question(.count(.workdays, from: civil("2026-11-08"), to: civil("2027-03-01"))))
    }

    @Test
    func coffeeOnThursdayAfternoonIsThursdayEvenWhenTheModelSaysMonday() {
        let wire = AIIntentWire(intent: "create", date: "2026-11-16", title: "coffee with Priya",
                                start: "15:00", end: "15:30", durationMinutes: 30)
        guard case let .create(draft) = validate(wire, query: "coffee with Priya Thursday afternoon, 30 min") else {
            Issue.record("expected create")
            return
        }
        #expect(draft.day == civil("2026-11-12"))
        #expect(draft.title == "coffee with Priya")
        #expect(draft.durationMinutes == 30)
    }

    @Test
    func modelDatesStillCountWhenTheQueryNamesNoDay() {
        #expect(validate(AIIntentWire(intent: "navigate", date: "2026-11-26"), query: "Thanksgiving")
            == .navigate(civil("2026-11-26")))
        #expect(validate(AIIntentWire(intent: "question", date: "2026-12-25", question: "weekNumber"),
                         query: "week number of the 25th") == .question(.weekNumber(civil("2026-12-25"))))
    }

    @Test
    func countBetweenTwoNamedDays() {
        let wire = AIIntentWire(intent: "question", question: "countDays", from: "2026-01-01", to: "2026-01-02")
        #expect(validate(wire, query: "days between Mar 1 and Apr 3")
            == .question(.count(.days, from: civil("2027-03-01"), to: civil("2027-04-03"))))
    }

    @Test
    func legacyBareDateUsesTheNamedDay() {
        #expect(AIIntentDecoder.decode(text: "2026-11-10", today: today, query: "next Friday")
            == .navigate(civil("2026-11-13")))
    }

    @Test
    func weekdayAndCountDecodeFromJSON() {
        let json = #"{"intent":"range","weekday":"monday","count":"2","dates":[],"label":"Mondays"}"#
        #expect(decode(json) == .range(DateRangeHighlight(dates: [civil("2026-11-09"), civil("2026-11-16")],
                                                          label: "Mondays")))
    }
}
