import Foundation
import Testing

@testable import GlimpseCore

struct DateAnswererTests {
    private let today = civil("2026-11-08")
    private let monToFri: Set<Int> = [2, 3, 4, 5, 6]

    private func answer(_ question: DateQuestion, workdays: Set<Int>? = nil, firstWeekday: Int = 1) -> DateAnswer {
        DateAnswerer.answer(question, today: today, calendar: fixedCalendar(firstWeekday: firstWeekday),
                            workdays: workdays ?? monToFri)
    }

    @Test
    func storyWorkdaysUntilMarchFirst() {
        let result = answer(.count(.workdays, from: today, to: civil("2027-03-01")))
        #expect(result.text == "80 workdays")
        #expect(result.detail == "Nov 8 → Mar 1, 2027 · Mon–Fri · holidays not counted")
    }

    @Test
    func customWorkdays() {
        let result = answer(.count(.workdays, from: today, to: civil("2027-03-01")), workdays: [2, 3, 4, 5])
        #expect(result.text == "64 workdays")
        #expect(result.detail?.contains("Mon–Thu") == true)
    }

    @Test
    func nonContiguousWorkdaysAreListed() {
        let result = answer(.count(.workdays, from: today, to: civil("2026-11-15")), workdays: [2, 4, 6])
        #expect(result.text == "3 workdays")
        #expect(result.detail?.contains("Mon, Wed, Fri") == true)
    }

    @Test
    func daysAndWeekendDays() {
        #expect(answer(.count(.days, from: today, to: civil("2027-03-01"))).text == "113 days")
        #expect(answer(.count(.days, from: today, to: civil("2027-03-01"))).detail == "Nov 8 → Mar 1, 2027")
        let weekend = answer(.count(.weekendDays, from: today, to: civil("2027-03-01")))
        #expect(weekend.text == "33 weekend days")
        #expect(weekend.detail?.contains("Sat, Sun") == true)
    }

    @Test
    func sameDayIsZeroAndSingularIsSingular() {
        #expect(answer(.count(.workdays, from: today, to: today)).text == "0 workdays")
        // Sunday → Tuesday covers Sunday and Monday: one workday.
        #expect(answer(.count(.workdays, from: today, to: civil("2026-11-10"))).text == "1 workday")
        #expect(answer(.count(.days, from: today, to: civil("2026-11-09"))).text == "1 day")
        #expect(answer(.count(.weekendDays, from: today, to: civil("2026-11-09"))).text == "1 weekend day")
    }

    @Test
    func longRangesCountArithmetically() {
        let result = answer(.count(.days, from: civil("1926-11-08"), to: civil("2126-11-08")))
        #expect(result.text == "73,049 days")
    }

    @Test
    func weekNumberHonoursFirstWeekday() {
        #expect(answer(.weekNumber(today), firstWeekday: 1).text == "Week 46")
        #expect(answer(.weekNumber(today), firstWeekday: 2).text == "Week 45")
        #expect(answer(.weekNumber(today)).detail == "Sun, Nov 8")
    }

    @Test
    func weekdayNamesTheDay() {
        let result = answer(.weekday(civil("2027-03-01")))
        #expect(result.text == "Monday")
        #expect(result.detail == "Mar 1, 2027")
    }

    @Test
    func accessibilityTextReadsNaturally() {
        let result = answer(.count(.workdays, from: today, to: civil("2027-03-01")))
        #expect(result.accessibilityLabel == "Answer: 80 workdays. Nov 8 to Mar 1, 2027, Mon–Fri, holidays not counted")
    }
}
