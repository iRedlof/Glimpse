import GlimpseCore
import SwiftUI

/// "✦ 80 workdays" with the counting convention underneath.
struct AIAnswerRow: View {
    let answer: DateAnswer

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs / 2) {
                Text(answer.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail = answer.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppDesign.Colors.calendarContextText)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(answer.accessibilityLabel)
        .announcing(answer.accessibilityLabel)
    }
}

/// "Next 3 Fridays · Nov 13, 20, 27" (+N in other months).
struct AIRangeSummaryRow: View {
    let highlight: DateRangeHighlight
    let summary: AIRangeSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("\(highlight.label) · \(summary.listed)")
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if summary.outsideMonth > 0 {
                Text("+\(summary.outsideMonth) in other months")
                    .font(.caption)
                    .foregroundStyle(AppDesign.Colors.calendarContextText)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel(label: highlight.label))
        .announcing(summary.accessibilityLabel(label: highlight.label))
    }
}

/// Range summary text. Cheap (at most 31 dates) and kept out of the view so it is unit-testable.
struct AIRangeSummary: Equatable {
    let listed: String
    let outsideMonth: Int
    let count: Int

    private static let dayStyle = Date.FormatStyle.dateTime.month(.abbreviated).day()

    init(highlight: DateRangeHighlight, displayedMonth: Date, calendar: Calendar) {
        let dates = highlight.dates.compactMap { $0.date(in: calendar) }
        let shown = dates.prefix(AppDesign.Schedule.maximumListedDates).map { $0.formatted(Self.dayStyle) }
        let more = dates.count > AppDesign.Schedule.maximumListedDates ? ", …" : ""
        listed = shown.joined(separator: ", ") + more
        outsideMonth = dates.filter {
            !calendar.isDate($0, equalTo: displayedMonth, toGranularity: .month)
        }.count
        count = dates.count
    }

    func accessibilityLabel(label: String) -> String {
        let days = count == 1 ? "1 day" : "\(count) days"
        return "Highlighted \(days): \(label), \(listed)"
    }
}

/// One short question back from the AI; the draft stays for editing.
struct AIClarificationRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
            Image(systemName: "questionmark.bubble")
                .font(.caption)
                .foregroundStyle(AppDesign.Colors.calendarContextText)
                .accessibilityHidden(true)
            // The text itself carries the label so it reads as one static text.
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Glimpse asks: \(message)")
            Spacer(minLength: 0)
        }
        .announcing("Glimpse asks: \(message)")
    }
}

extension View {
    /// Posts a VoiceOver announcement when the row appears or its text changes.
    func announcing(_ text: String) -> some View {
        onAppear { AccessibilityNotification.Announcement(text).post() }
            .onChange(of: text) { _, newText in AccessibilityNotification.Announcement(newText).post() }
    }
}
