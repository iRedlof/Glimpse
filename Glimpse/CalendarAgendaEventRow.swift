import AppKit
import GlimpseCore
import SwiftUI

/// One agenda event: a full-width Button that opens the event in Apple's Calendar app.
/// Pointer: hover fill, pointing-hand cursor and a trailing "open" glyph. Keyboard: native
/// Button focus in document order (Tab), the shared inset outline only after keyboard use,
/// and Return/Space through `CalendarControlReturn`, like the footer controls.
///
/// Today's next/current meeting with a strict meeting link also gets a trailing Join
/// button (its own keyboard owner, after the row in Tab order; ⌘J anywhere in the panel).
///
/// A located event can carry a trailing chip: "Leave by 8:40" (leave-by on, not started)
/// or "Away 5 days" (a trip). The chip is part of the row Button, not a separate control.
@MainActor
struct CalendarAgendaEventRow: View {
    static let openHint = "Open in Calendar"

    let event: CalendarEvent
    let owner: CalendarKeyboardOwner
    let open: () -> Void
    /// Non-nil only for the joinable meeting; opens its link.
    var join: (() -> Void)? = nil
    /// "Leave by 8:40" / "Away 5 days", from `CalendarFeature.State.agendaBadge(for:)`.
    var badge: AgendaBadge? = nil
    var keyboardContext: () -> CalendarKeyboardContext = { .init(visible: false) }
    var keyboardObservation: ((CalendarKeyboardInvocation) -> Void)? = nil
    var controlFocus: FocusState<CalendarKeyboardOwner?>.Binding? = nil
    /// Render-only: draws the hovered appearance without a pointer (native render captures,
    /// where SwiftUI hover follows the real cursor). Nil follows the pointer.
    var hoverOverride: Bool? = nil

    var body: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            rowButton
            if let join, let link = event.meetingLink {
                CalendarAgendaJoinButton(
                    eventTitle: event.title, provider: link.provider, join: join,
                    keyboardContext: keyboardContext, keyboardObservation: keyboardObservation,
                    controlFocus: controlFocus
                )
            }
        }
    }

    private var rowButton: some View {
        Button(action: open) {
            HStack(spacing: AppDesign.Spacing.sm) {
                RoundedRectangle(cornerRadius: AppDesign.Agenda.accentCornerRadius)
                    .fill(Color.accentColor)
                    .frame(width: AppDesign.Agenda.accentWidth, height: AppDesign.Agenda.accentHeight)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppDesign.Colors.calendarContextText)
                        .lineLimit(1)
                }
                Spacer(minLength: AppDesign.Spacing.xs)
                if let badge {
                    CalendarAgendaBadgeChip(badge: badge)
                }
                CalendarAgendaOpenGlyph()
            }
            .padding(.horizontal, AppDesign.Agenda.rowHorizontalInset)
            .padding(.vertical, AppDesign.Agenda.rowVerticalInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay { CalendarKeyboardFocusOutline() }
        }
        .buttonStyle(CalendarAgendaRowButtonStyle(hoverOverride: hoverOverride))
        .modifier(CalendarControlReturn(
            owner: owner, context: keyboardContext, action: open,
            observe: keyboardObservation, focus: controlFocus
        ))
        .modifier(PointingHandCursor())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        // .help is AXHelp on macOS, as is .accessibilityHint: one string carries the hint.
        .help(Self.openHint)
        .accessibilityInputLabels([event.title, "\(Self.openHint) \(event.title)"])
    }
}

extension CalendarAgendaEventRow {
    /// Thread-safe, auto-updating start time style ("9:00 AM"), shared by every row.
    static let startTimeStyle = Date.FormatStyle(date: .omitted, time: .shortened)

    /// "9:00 AM · 412 Oak St" for a located event, "5 days · South Lake Tahoe" for a trip,
    /// else the event's time range. The place keeps the line short enough to stay readable.
    var subtitle: String {
        guard let location = event.location else { return event.timeString }
        if case let .away(days) = badge { return "\(days) days · \(location)" }
        let time = event.isAllDay ? event.timeString : event.startDate.formatted(Self.startTimeStyle)
        return "\(time) · \(location)"
    }

    /// "Dentist, 9:00 AM – 10:00 AM, 412 Oak St, Leave by 8:40 AM".
    var accessibilityText: String {
        ([event.title, event.timeString, event.location]
            + [badge?.accessibilityText(calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)])
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// The trailing agenda chip: amber "Leave by 8:40" (like the amber menu bar pill), or a quiet
/// neutral "Away 5 days". Tabular digits so times line up across rows.
struct CalendarAgendaBadgeChip: View {
    let badge: AgendaBadge

    var body: some View {
        Text(badge.text(calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(isLeaveBy ? AppDesign.Colors.onAmberText : Color.primary)
            .padding(.horizontal, AppDesign.Agenda.chipHorizontalPadding)
            .padding(.vertical, AppDesign.Agenda.chipVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm)
                    .fill(isLeaveBy ? AppDesign.Colors.accentAmber
                        : Color.primary.opacity(AppDesign.Agenda.tripChipFillOpacity))
            )
            .fixedSize()
            .accessibilityLabel(badge.accessibilityText(calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent))
    }

    private var isLeaveBy: Bool {
        if case .leaveBy = badge { return true }
        return false
    }
}

/// "Join": opens the meeting link. Native Button focus with the shared inset outline and
/// Return/Space through `CalendarControlReturn` (owner `.agendaJoin`).
private struct CalendarAgendaJoinButton: View {
    static let shortcutHint = "⌘J"

    let eventTitle: String
    let provider: MeetingLink.Provider
    let join: () -> Void
    let keyboardContext: () -> CalendarKeyboardContext
    let keyboardObservation: ((CalendarKeyboardInvocation) -> Void)?
    let controlFocus: FocusState<CalendarKeyboardOwner?>.Binding?

    var body: some View {
        Button(action: join) {
            Text("Join")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, AppDesign.Agenda.joinHorizontalPadding)
                .padding(.vertical, AppDesign.Agenda.joinVerticalPadding)
                .contentShape(Rectangle())
                .overlay { CalendarKeyboardFocusOutline(color: .primary) }
        }
        .buttonStyle(CalendarAgendaJoinButtonStyle())
        .modifier(CalendarControlReturn(
            owner: .agendaJoin, context: keyboardContext, action: join,
            observe: keyboardObservation, focus: controlFocus
        ))
        .modifier(PointingHandCursor())
        .accessibilityLabel("Join \(provider.displayName) meeting, \(eventTitle)")
        .help("Join \(provider.displayName) meeting (\(Self.shortcutHint))")
        .accessibilityInputLabels(["Join", "Join \(eventTitle)"])
    }
}

private struct CalendarAgendaJoinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CalendarAgendaJoinAppearance(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct CalendarAgendaJoinAppearance<Label: View>: View {
    @Environment(\.self) private var environment
    let label: Label
    let isPressed: Bool

    var body: some View {
        label
            .background(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm)
                    .fill(AppDesign.Colors.calendarSolidFill(.accentColor, in: environment))
            )
            .opacity(isPressed ? AppDesign.Agenda.joinPressedOpacity : 1)
    }
}

/// The trailing "opens elsewhere" glyph: present only while the row is hovered or
/// keyboard-focused, so a resting list stays as quiet as before.
private struct CalendarAgendaOpenGlyph: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.inputModality) private var inputModality
    @Environment(\.agendaRowHovered) private var isHovered

    var body: some View {
        Image(systemName: "arrow.up.forward.app")
            .font(.caption)
            .foregroundStyle(AppDesign.Colors.calendarContextText)
            .opacity(isHovered || (isFocused && inputModality.showsFocusRing) ? 1 : 0)
            .accessibilityHidden(true)
    }
}

private extension EnvironmentValues {
    @Entry var agendaRowHovered = false
}

/// Full-row hover/pressed fill, matching the footer's opacities.
private struct CalendarAgendaRowButtonStyle: ButtonStyle {
    let hoverOverride: Bool?

    func makeBody(configuration: Configuration) -> some View {
        CalendarAgendaRowAppearance(label: configuration.label, isPressed: configuration.isPressed,
                                    hoverOverride: hoverOverride)
    }
}

private struct CalendarAgendaRowAppearance<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let hoverOverride: Bool?
    @State private var pointerHovered = false

    private var isHovered: Bool { hoverOverride ?? pointerHovered }

    var body: some View {
        label
            .environment(\.agendaRowHovered, isHovered)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm)
                    .fill(Color.primary.opacity(isPressed ? AppDesign.Footer.pressedBackgroundOpacity
                        : isHovered ? AppDesign.Footer.hoverBackgroundOpacity : 0))
            )
            .onHover { pointerHovered = $0 }
    }
}

/// Pointing-hand cursor while hovered. macOS 15 has `pointerStyle(.link)`; macOS 14 uses a
/// balanced NSCursor push/pop that is also undone if the row disappears while hovered.
private struct PointingHandCursor: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(.link)
        } else {
            content
                .onHover { inside in
                    if inside, !pushed { NSCursor.pointingHand.push(); pushed = true }
                    else if !inside, pushed { NSCursor.pop(); pushed = false }
                }
                .onDisappear {
                    if pushed { NSCursor.pop(); pushed = false }
                }
        }
    }
}
