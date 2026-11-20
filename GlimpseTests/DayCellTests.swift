import Foundation
import GlimpseCore
import SwiftUI
import Testing
@testable import Glimpse

/// Day cells are Equatable value views: hover is cell-local and per-day work is
/// memoized per month, so a pointer move re-renders two cells, not the popover.
@MainActor
struct DayCellTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US")
        return cal
    }
    private let locale = Locale(identifier: "en_US")

    private func day(_ dayOfMonth: Int, hour: Int = 0, inMonth: Bool = true) -> GlimpseCore.CalendarDay {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: dayOfMonth, hour: hour))!
        return GlimpseCore.CalendarDay(date: date, isCurrentMonth: inMonth)
    }

    private func context(
        today: Int = 20, selected: Int? = nil, logical: Int? = nil, highlighted: [Int] = [],
        keyboardFocused: Bool = false, showsFocusRing: Bool = true, hoverResetToken: Int = 0
    ) -> DayCellContext {
        func start(_ value: Int) -> Date { calendar.startOfDay(for: day(value).date) }
        return DayCellContext(
            todayStart: start(today), selectedStart: selected.map(start), logicalStart: logical.map(start),
            highlightedDays: Set(highlighted.map(start)), highlightSuffix: ", highlighted, Next 3 Fridays",
            keyboardFocused: keyboardFocused, showsFocusRing: showsFocusRing,
            hoverResetToken: hoverResetToken, todayFill: .blue, accent: .blue
        )
    }

    private func model(_ day: GlimpseCore.CalendarDay, _ context: DayCellContext, workday: Bool = true) -> DayCellModel {
        let entry = CalendarDayIndexCache().entries(for: [day], calendar: calendar, locale: locale)[0]
        return DayCellModel(day: day, entry: entry, isWorkdayColumn: workday, context: context)
    }

    @Test
    func indexIsBuiltOncePerDistinctGrid() {
        let cache = CalendarDayIndexCache()
        let days = (1...30).map { day($0) }
        let first = cache.entries(for: days, calendar: calendar, locale: locale)
        _ = cache.entries(for: days, calendar: calendar, locale: locale)
        #expect(cache.buildCount == 1)
        #expect(first[19].dayNumber == 20)
        #expect(first[19].start == calendar.startOfDay(for: day(20).date))
        #expect(first[19].dateLabel == "Friday, November 20, 2026")
        _ = cache.entries(for: Array(days.dropFirst()), calendar: calendar, locale: locale)
        #expect(cache.buildCount == 2)
        _ = cache.entries(for: Array(days.dropFirst()), calendar: calendar, locale: Locale(identifier: "fr_FR"))
        #expect(cache.buildCount == 3)
    }

    @Test
    func todayAndSelectionCompareDayStartsNotInstants() {
        let cell = model(day(20, hour: 15), context(today: 20, selected: 20))
        #expect(cell.isToday && cell.isSelected)
        #expect(cell.dayNumber == 20)
        #expect(cell.accessibilityLabel == "Friday, November 20, 2026, today")
    }

    @Test
    func outsideMonthIsNeverTodayAndSaysSo() {
        let cell = model(day(20, inMonth: false), context(today: 20))
        #expect(!cell.isToday)
        #expect(cell.accessibilityLabel == "Friday, November 20, 2026, outside current month")
    }

    @Test
    func highlightAddsTheRangeSuffix() {
        let cell = model(day(27), context(highlighted: [27]))
        #expect(cell.isHighlighted)
        #expect(cell.accessibilityLabel == "Friday, November 27, 2026, highlighted, Next 3 Fridays")
    }

    @Test
    func focusRingNeedsGridFocusModalityAndLogicalDate() {
        #expect(model(day(5), context(logical: 5, keyboardFocused: true)).showsFocusRing)
        #expect(!model(day(5), context(logical: 5, keyboardFocused: false)).showsFocusRing)
        #expect(!model(day(5), context(logical: 5, keyboardFocused: true, showsFocusRing: false)).showsFocusRing)
        #expect(!model(day(6), context(logical: 5, keyboardFocused: true)).showsFocusRing)
    }

    @Test
    func unrelatedGridChangesLeaveOtherCellsEqual() {
        // Moving the logical date from the 5th to the 6th only changes those two cells.
        let before = context(logical: 5, keyboardFocused: true)
        let after = context(logical: 6, keyboardFocused: true)
        #expect(model(day(12), before) == model(day(12), after))
        #expect(model(day(5), before) != model(day(5), after))
        #expect(model(day(6), before) != model(day(6), after))
        // Hover reset and focus ownership reach every cell (the click closure reads it).
        #expect(model(day(12), context()) != model(day(12), context(hoverResetToken: 1)))
        #expect(model(day(12), context()) != model(day(12), context(keyboardFocused: true)))
    }

    @Test
    func equalityIgnoresTheActionClosure() {
        let cell = model(day(9), context())
        var taps = 0
        let first = DayCell(model: cell) { taps += 1 }
        let second = DayCell(model: cell) { taps += 2 }
        #expect(first == second)
        #expect(first != DayCell(model: model(day(9), context(selected: 9))) {})
        first.action()
        #expect(taps == 1)
    }

    @Test
    func foregroundFollowsTodaySelectionAndMonth() {
        #expect(DayCell.foregroundColor(model(day(20), context(today: 20))) == .white)
        #expect(DayCell.foregroundColor(model(day(3), context(selected: 3))) == .primary)
        #expect(DayCell.foregroundColor(model(day(3, inMonth: false), context()))
                == AppDesign.Colors.calendarContextText)
    }

    /// Measurement: 42-cell equality (what SwiftUI runs per pass) vs. rebuilding the index.
    @Test
    func cellEqualityIsCheapRelativeToIndexing() {
        let days = (0..<42).map { offset in
            GlimpseCore.CalendarDay(
                date: calendar.date(byAdding: .day, value: offset, to: day(1).date)!, isCurrentMonth: offset < 30
            )
        }
        let ctx = context(selected: 9, logical: 9, keyboardFocused: true)
        let entries = CalendarDayIndexCache().entries(for: days, calendar: calendar, locale: locale)
        let models = zip(days, entries).map { DayCellModel(day: $0, entry: $1, isWorkdayColumn: true, context: ctx) }
        let copies = models
        let rounds = 200
        let clock = ContinuousClock()
        var equal = 0
        let compare = clock.measure {
            for _ in 0..<rounds { for i in 0..<42 where models[i] == copies[i] { equal += 1 } }
        }
        let rebuild = clock.measure {
            for _ in 0..<rounds { _ = CalendarDayIndexCache().entries(for: days, calendar: calendar, locale: locale) }
        }
        #expect(equal == rounds * 42)
        print("GLIMPSE_DAYCELL_BENCH compare42=\(compare / rounds) rebuild42=\(rebuild / rounds)")
    }
}
