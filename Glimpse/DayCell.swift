import GlimpseCore
import SwiftUI

/// Per-day values that only change when the grid's days, calendar or locale change:
/// computed once per month instead of per cell on every body pass.
struct CalendarDayEntry: Equatable {
    let start: Date
    let dayNumber: Int
    /// "Friday, November 20, 2026": the accessibility label's date part.
    let dateLabel: String
}

/// Memoizes `CalendarDayEntry` values. The key compare is 42 `CalendarDay ==` checks,
/// far cheaper than the 42 × several `Calendar` queries it replaces.
@MainActor
final class CalendarDayIndexCache {
    private struct Key: Equatable {
        let days: [GlimpseCore.CalendarDay]
        let calendar: Calendar
        let locale: Locale
    }

    private var key: Key?
    private var cached: [CalendarDayEntry] = []
    /// Number of rebuilds; visible for tests and measurement.
    private(set) var buildCount = 0

    func entries(
        for days: [GlimpseCore.CalendarDay], calendar: Calendar, locale: Locale = .current
    ) -> [CalendarDayEntry] {
        let key = Key(days: days, calendar: calendar, locale: locale)
        guard key != self.key else { return cached }
        var style = DayCellModel.accessibilityDateStyle
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        cached = days.map { day in
            CalendarDayEntry(
                start: calendar.startOfDay(for: day.date),
                dayNumber: calendar.component(.day, from: day.date),
                dateLabel: day.date.formatted(style)
            )
        }
        self.key = key
        buildCount += 1
        return cached
    }
}

/// Grid-wide values resolved once per body pass, shared by all 42 cells.
struct DayCellContext {
    let todayStart: Date
    let selectedStart: Date?
    let logicalStart: Date?
    let highlightedDays: Set<Date>
    let highlightSuffix: String
    let keyboardFocused: Bool
    let showsFocusRing: Bool
    /// Bumped when the pointer leaves the grid or the panel hides; cells drop hover.
    let hoverResetToken: Int
    let todayFill: Color
    let accent: Color
}

/// Everything a day cell draws. Two equal models draw identically, so SwiftUI can
/// skip a cell's body when only another cell (e.g. the hovered one) changed.
struct DayCellModel: Equatable {
    let date: Date
    let dayNumber: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isHighlighted: Bool
    let isWorkdayColumn: Bool
    /// The grid owns keyboard focus; a click then also moves the logical date.
    let keyboardFocused: Bool
    let showsFocusRing: Bool
    let hoverResetToken: Int
    let todayFill: Color
    let accent: Color
    let accessibilityLabel: String

    static let accessibilityDateStyle = Date.FormatStyle.dateTime
        .weekday(.wide).month(.wide).day().year()

    init(day: GlimpseCore.CalendarDay, entry: CalendarDayEntry, isWorkdayColumn: Bool, context: DayCellContext) {
        let isToday = day.isCurrentMonth && entry.start == context.todayStart
        let isHighlighted = context.highlightedDays.contains(entry.start)
        date = day.date
        dayNumber = entry.dayNumber
        isCurrentMonth = day.isCurrentMonth
        self.isToday = isToday
        isSelected = entry.start == context.selectedStart
        self.isHighlighted = isHighlighted
        self.isWorkdayColumn = isWorkdayColumn
        keyboardFocused = context.keyboardFocused
        showsFocusRing = context.keyboardFocused && context.showsFocusRing && entry.start == context.logicalStart
        hoverResetToken = context.hoverResetToken
        todayFill = context.todayFill
        accent = context.accent
        var label = entry.dateLabel
        if isToday { label += ", today" }
        if !day.isCurrentMonth { label += ", outside current month" }
        if isHighlighted { label += context.highlightSuffix }
        accessibilityLabel = label
    }
}

/// One calendar date button. Hover is cell-local state, so moving the pointer across
/// the grid re-renders only the two cells it crosses, not the whole popover.
struct DayCell: View, Equatable {
    let model: DayCellModel
    /// Excluded from `==`: it captures only stable references plus values in `model`.
    let action: () -> Void
    @State private var isHovered = false

    nonisolated static func == (lhs: DayCell, rhs: DayCell) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        Button(action: action) {
            Text("\(model.dayNumber)")
                .font(.system(.body, design: .rounded))
                .fontWeight(model.isToday || model.isSelected ? .bold : .regular)
                .foregroundStyle(Self.foregroundColor(model))
                .frame(maxWidth: .infinity)
                .frame(height: AppDesign.Grid.cellHeight)
                .background { markBackground }
                .background {
                    if model.isHighlighted {
                        RoundedRectangle(cornerRadius: AppDesign.Grid.rangeHighlightCornerRadius)
                            .fill(Color.accentColor.opacity(AppDesign.Grid.rangeHighlightOpacity))
                    }
                }
                .foregroundStyle(model.isToday ? .white : Self.foregroundColor(model))
                .contentShape(Rectangle())
                .overlay {
                    if model.showsFocusRing {
                        RoundedRectangle(cornerRadius: AppDesign.Control.focusCornerRadius)
                            .strokeBorder(model.accent, lineWidth: AppDesign.Control.focusLineWidth)
                            .padding(AppDesign.Control.focusInset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { isHovered = $0 }
            .onChange(of: model.hoverResetToken) { _, _ in isHovered = false }
            .accessibilityLabel(model.accessibilityLabel)
            .accessibilityAddTraits(model.isSelected ? .isSelected : [])
    }

    @ViewBuilder private var markBackground: some View {
        if model.isToday {
            Circle()
                .fill(model.todayFill)
                .frame(width: AppDesign.Grid.todayCircleSize, height: AppDesign.Grid.todayCircleSize)
        } else if model.isSelected {
            Circle()
                .strokeBorder(model.accent, lineWidth: 2)
                .frame(width: AppDesign.Grid.todayCircleSize, height: AppDesign.Grid.todayCircleSize)
        } else if isHovered {
            Circle()
                .strokeBorder(Color.secondary.opacity(AppDesign.Grid.hoverBorderOpacity), lineWidth: 1)
                .frame(width: AppDesign.Grid.todayCircleSize, height: AppDesign.Grid.todayCircleSize)
        } else if model.isWorkdayColumn && model.isCurrentMonth {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(AppDesign.Grid.workdayTintOpacity))
        }
    }

    static func foregroundColor(_ model: DayCellModel) -> Color {
        if model.isToday { return .white }
        if model.isSelected { return .primary }
        if !model.isCurrentMonth { return AppDesign.Colors.calendarContextText }
        return .primary
    }
}
