import Foundation
import Testing

@testable import GlimpseCore

/// Today is Sunday 2026-11-08 throughout, the day the live probe ran.
struct DayPhraseParserTests {
    private let today = civil("2026-11-08")

    private func days(_ text: String) -> [CivilDate] {
        DayPhraseParser.days(in: text, today: today)
    }

    @Test(arguments: [
        ("next Friday", "2026-11-13"),
        ("Friday", "2026-11-13"),
        ("this friday", "2026-11-13"),
        ("coffee with Priya Thursday afternoon, 30 min", "2026-11-12"),
        ("lunch Tue 1pm", "2026-11-10"),
        ("thurs", "2026-11-12"),
        ("Sunday", "2026-11-08"),
        ("next Sunday", "2026-11-15"),
        ("Friday after next", "2026-11-20"),
        ("last Friday", "2026-11-06"),
        ("on sat", "2026-11-14"),
    ])
    func weekdaysResolveFromToday(_ text: String, _ expected: String) {
        #expect(days(text) == [civil(expected)], "\(text)")
    }

    @Test(arguments: [
        ("today", "2026-11-08"),
        ("dentist tomorrow at 9", "2026-11-09"),
        ("day after tomorrow", "2026-11-10"),
        ("yesterday", "2026-11-07"),
        ("in 10 days", "2026-11-18"),
        ("in a week", "2026-11-15"),
        ("in 2 weeks", "2026-11-22"),
    ])
    func relativeDays(_ text: String, _ expected: String) {
        #expect(days(text) == [civil(expected)], "\(text)")
    }

    @Test(arguments: [
        ("how many workdays until Mar 1?", "2027-03-01"),
        ("March 3 2027", "2027-03-03"),
        ("Mar 1, 2026", "2026-03-01"),
        ("the 1st of March", "2027-03-01"),
        ("25 December", "2026-12-25"),
        ("Nov 8", "2026-11-08"),
        ("Christmas", "2026-12-25"),
        ("christmas eve", "2026-12-24"),
        ("New Year's Eve", "2026-12-31"),
        ("new year's day", "2027-01-01"),
        ("2026-12-01", "2026-12-01"),
        ("days since Mar 1", "2026-03-01"),
    ])
    func monthDaysWithoutAYearAreTheNextOccurrence(_ text: String, _ expected: String) {
        #expect(days(text) == [civil(expected)], "\(text)")
    }

    @Test
    func twoDaysAreReturnedInOrder() {
        #expect(days("days between Mar 1 and Apr 3") == [civil("2027-03-01"), civil("2027-04-03")])
    }

    @Test(arguments: [
        "blorp the thing", "lunch at 9", "may I have lunch", "the sun is out", "1pm", "Feb 30",
        "meeting in the morning", "",
    ])
    func wordsThatAreNotDaysAreIgnored(_ text: String) {
        #expect(days(text).isEmpty, "\(text)")
    }

    @Test
    func leapDayWithoutAYearFindsTheNextLeapYear() {
        #expect(days("Feb 29") == [civil("2028-02-29")])
    }

    @Test
    func countedWeekdaySeries() {
        let fridays = [civil("2026-11-13"), civil("2026-11-20"), civil("2026-11-27")]
        #expect(DayPhraseParser.weekdaySeries(in: "next 3 Fridays", today: today) == fridays)
        #expect(DayPhraseParser.weekdaySeries(in: "the next three fridays", today: today) == fridays)
        #expect(DayPhraseParser.weekdaySeries(in: "next 2 Sundays", today: today)
            == [civil("2026-11-15"), civil("2026-11-22")])
    }

    @Test
    func monthWeekdaySeries() {
        #expect(DayPhraseParser.weekdaySeries(in: "every Monday in December", today: today)
            == ["2026-12-07", "2026-12-14", "2026-12-21", "2026-12-28"].map(civil))
        #expect(DayPhraseParser.weekdaySeries(in: "all Fridays in March", today: today)?.first == civil("2027-03-05"))
        #expect(DayPhraseParser.weekdaySeries(in: "next Friday", today: today) == nil)
    }

    @Test
    func seriesCountIsCapped() {
        #expect(DayPhraseParser.weekdaySeries(in: "next 99 Mondays", today: today)?.count
            == DateRangeHighlight.maximumDates)
        #expect(DayPhraseParser.weekdaySeries(in: "next 0 Mondays", today: today) == nil)
    }

    @Test(arguments: [
        ("how many workdays until Mar 1?", "countWorkdays"),
        ("business days to Christmas", "countWorkdays"),
        ("weekend days until new year", "countWeekendDays"),
        ("how many days until Christmas", "countDays"),
        ("what week is Christmas?", "weekNumber"),
        ("week number of Mar 3", "weekNumber"),
        ("what day is May 4?", "weekday"),
        ("blorp", nil),
    ] as [(String, String?)])
    func questionKindFromTheWords(_ text: String, _ expected: String?) {
        #expect(DayPhraseParser.questionKind(in: text) == expected, "\(text)")
    }

    @Test
    func longInputIsCappedBeforeTokenizing() {
        let text = String(repeating: "x ", count: 10_000) + "tomorrow"
        #expect(days(text).isEmpty)
    }
}
