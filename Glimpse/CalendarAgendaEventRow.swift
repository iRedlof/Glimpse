import AppKit
import GlimpseCore
import SwiftUI

/// One agenda event: a full-width Button that opens the event in Apple's Calendar app.
/// Pointer: hover fill, pointing-hand cursor and a trailing "open" glyph. Keyboard: native
/// Button focus in document order (Tab), the shared inset outline only after keyboard use,
/// and Return/Space through `CalendarControlReturn`, like the footer controls.
@MainActor
struct CalendarAgendaEventRow: View {
    static let openHint = "Open in Calendar"

    let event: CalendarEvent
    let owner: CalendarKeyboardOwner
    let open: () -> Void
    var keyboardContext: () -> CalendarKeyboardContext = { .init(visible: false) }
    var keyboardObservation: ((CalendarKeyboardInvocation) -> Void)? = nil
    var controlFocus: FocusState<CalendarKeyboardOwner?>.Binding? = nil
    /// Render-only: draws the hovered appearance without a pointer (native render captures,
    /// where SwiftUI hover follows the real cursor). Nil follows the pointer.
    var hoverOverride: Bool? = nil

    var body: some View {
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
                    Text(event.timeString)
                        .font(.caption)
                        .foregroundStyle(AppDesign.Colors.calendarContextText)
                }
                Spacer(minLength: AppDesign.Spacing.xs)
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
        .accessibilityLabel("\(event.title), \(event.timeString)")
        // .help is AXHelp on macOS, as is .accessibilityHint: one string carries the hint.
        .help(Self.openHint)
        .accessibilityInputLabels([event.title, "\(Self.openHint) \(event.title)"])
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
