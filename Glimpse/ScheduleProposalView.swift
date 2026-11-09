import ComposableArchitecture
import EventKit
import GlimpseCore
import SwiftUI

/// Free-time proposal for an AI "create" request. Replaces the events list
/// while active. Nothing is preselected; a click or Return on a picked row
/// is the only way to save.
struct ScheduleProposalView: View {
    @Bindable var store: StoreOf<ScheduleFeature>
    let calendar: Calendar
    /// Lets the card's links take keyboard focus like the panel's other controls.
    var keyboard: ScheduleKeyboard? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            if let draft = store.draft {
                header(draft)
                Text("✦ \(ScheduleCopy.draftLine(draft, calendar: store.calendar))")
                    .font(.caption)
                    .foregroundStyle(AppDesign.Colors.calendarContextText)
                    .lineLimit(2)
                    .accessibilityLabel(ScheduleCopy.draftLine(draft, calendar: store.calendar))
            }
            phaseContent
            if let notice = store.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .announcing(notice)
            }
        }
        .padding(AppDesign.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.md)
                .strokeBorder(Color.secondary.opacity(AppDesign.Grid.borderOpacity), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add event")
    }

    private func header(_ draft: EventDraft) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ScheduleCopy.header(for: draft, calendar: calendar))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: AppDesign.Spacing.sm)
            if store.phase == .choosing || store.phase == .saving {
                Text(ScheduleCopy.freeTimes(store.slots.count))
                    .font(.caption)
                    .foregroundStyle(AppDesign.Colors.calendarContextText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .idle:
            EmptyView()
        case .needsAccess:
            Text(ScheduleCopy.needsAccess).font(.caption)
            // The only way to the system prompt: Return in the field never asks.
            ScheduleLinkButton(
                title: ScheduleCopy.allowAccess, owner: .scheduleAllowAccess,
                accessibilityLabel: "Allow calendar access to find free times",
                accessibilityHint: ScheduleCopy.allowAccessHint, keyboard: keyboard
            ) { store.send(.allowAccessTapped) }
        case .requestingAccess:
            progress(ScheduleCopy.requestingAccess)
        case let .accessUnavailable(status):
            ScheduleAccessUnavailableRow(status: status, keyboard: keyboard)
        case .searching:
            progress(ScheduleCopy.searching)
        case .noSlots:
            if let draft = store.draft {
                Text(ScheduleCopy.noSlots(draft, calendar: calendar)).font(.caption)
                    .announcing(ScheduleCopy.noSlots(draft, calendar: calendar))
            }
        case .choosing, .saving:
            timeline
            if store.phase == .saving {
                progress(ScheduleCopy.saving)
            } else if store.selectedSlotIndex == nil {
                Text(ScheduleCopy.choosingHint)
                    .font(.caption)
                    .foregroundStyle(AppDesign.Colors.calendarContextText)
            }
        case let .failed(error):
            Text(error.message).font(.caption).announcing(error.message)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs / 2) {
            ForEach(ScheduleTimeline.rows(events: store.dayEvents, slots: store.slots)) { row in
                switch row.kind {
                case let .busy(event): busyRow(event)
                case let .slot(index, slot): slotRow(index: index, slot: slot)
                }
            }
        }
        .disabled(store.phase == .saving)
    }

    private func busyRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            RoundedRectangle(cornerRadius: AppDesign.Schedule.timelineBarWidth / 2)
                .fill(Color.secondary.opacity(AppDesign.Schedule.busyBarOpacity))
                .frame(width: AppDesign.Schedule.timelineBarWidth, height: AppDesign.Schedule.timelineBarHeight)
            Text(event.title).font(.caption).lineLimit(1)
            Spacer(minLength: 0)
            Text(ScheduleCopy.timeRange(FreeSlot(start: event.startDate, end: event.endDate)))
                .font(.caption)
                .foregroundStyle(AppDesign.Colors.calendarContextText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ScheduleCopy.busyAccessibilityLabel(event))
    }

    private func slotRow(index: Int, slot: FreeSlot) -> some View {
        let selected = store.selectedSlotIndex == index
        let title = store.draft?.title ?? ""
        return Button { store.send(.slotActivated(index)) } label: {
            HStack(spacing: AppDesign.Spacing.sm) {
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(ScheduleCopy.timeRange(slot))
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                Spacer(minLength: 0)
                if selected {
                    Text(ScheduleCopy.selectedHint)
                        .font(.caption)
                        .foregroundStyle(AppDesign.Colors.calendarContextText)
                }
            }
            .padding(.horizontal, AppDesign.Spacing.sm)
            .frame(height: AppDesign.Schedule.slotRowHeight)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Schedule.chipCornerRadius)
                    .fill(Color.accentColor.opacity(selected ? AppDesign.Schedule.selectedFillOpacity : 0))
            )
            .overlay(slotBorder(selected: selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(ScheduleCopy.slotAccessibilityLabel(slot, title: title, calendar: store.calendar))
        .accessibilityHint(selected ? "Press Return to add" : "Use the arrow keys to pick, or activate to add")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func slotBorder(selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppDesign.Schedule.chipCornerRadius)
        if selected {
            shape.strokeBorder(Color.accentColor, lineWidth: AppDesign.Schedule.selectedLineWidth)
        } else {
            shape.strokeBorder(
                Color.accentColor.opacity(AppDesign.Schedule.ghostOpacity),
                style: StrokeStyle(lineWidth: AppDesign.Schedule.ghostLineWidth, dash: AppDesign.Schedule.ghostDash)
            )
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text(text).font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .announcing(text)
    }
}

struct ScheduleAccessUnavailableRow: View {
    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
    )

    let status: EKAuthorizationStatus
    var keyboard: ScheduleKeyboard? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Text(ScheduleCopy.accessUnavailable(status)).font(.caption)
            if status != .restricted {
                ScheduleLinkButton(
                    title: ScheduleCopy.openPrivacySettings, owner: .scheduleOpenPrivacySettings,
                    accessibilityLabel: ScheduleCopy.openPrivacySettings,
                    accessibilityHint: "Opens System Settings to turn on calendar access.", keyboard: keyboard
                ) {
                    guard let url = Self.privacySettingsURL else {
                        AppLogger.general.error("Calendar privacy settings URL is invalid")
                        return
                    }
                    NSWorkspace.shared.open(url)
                }
            }
            Text(ScheduleCopy.otherIntentsStillWork)
                .font(.caption)
                .foregroundStyle(AppDesign.Colors.calendarContextText)
        }
        .announcing(ScheduleCopy.accessUnavailable(status))
    }
}

/// Keyboard plumbing shared with the panel's other focusable controls.
struct ScheduleKeyboard {
    let context: () -> CalendarKeyboardContext
    var observe: ((CalendarKeyboardInvocation) -> Void)?
    var focus: FocusState<CalendarKeyboardOwner?>.Binding?
}

/// The card's text actions ("Allow calendar access", "Open Calendar Privacy
/// Settings"): one link style, focusable, with Return/Space on focus.
struct ScheduleLinkButton: View {
    let title: String
    let owner: CalendarKeyboardOwner
    let accessibilityLabel: String
    let accessibilityHint: String
    var keyboard: ScheduleKeyboard?
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
                .overlay { CalendarKeyboardFocusOutline() }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        if let keyboard {
            button.modifier(CalendarControlReturn(
                owner: owner, context: keyboard.context, action: action,
                observe: keyboard.observe, focus: keyboard.focus
            ))
        } else {
            button.focusable(false)
        }
    }
}

/// "✓ Added to Work · Undo 10". Outlives the editor so it stays usable.
struct ScheduleUndoChip: View {
    let chip: ScheduleFeature.UndoChip
    let undo: () -> Void

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            switch chip.status {
            case .available:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(ScheduleCopy.added(chip.event)).font(.caption)
                    .announcing(ScheduleCopy.added(chip.event))
                Spacer(minLength: 0)
                Button(action: undo) {
                    Text(ScheduleCopy.undoButton(remaining: chip.remaining))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(ScheduleCopy.undoAccessibilityLabel(chip.event))
                .accessibilityValue(ScheduleCopy.undoAccessibilityValue(remaining: chip.remaining))
                .accessibilityHint("Removes the event. Command-Z also works.")
            case .undoing:
                ProgressView().controlSize(.small)
                Text(ScheduleCopy.removing).font(.caption)
                Spacer(minLength: 0)
            case .undone:
                Text(ScheduleCopy.removed).font(.caption).announcing(ScheduleCopy.removed)
                Spacer(minLength: 0)
            case let .failed(error):
                Text(error.message).font(.caption).announcing(error.message)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, AppDesign.Spacing.sm)
        .padding(.vertical, AppDesign.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.Schedule.chipCornerRadius)
                .fill(Color.accentColor.opacity(AppDesign.Schedule.chipBackgroundOpacity))
        )
        .accessibilityElement(children: .contain)
    }
}

/// Busy context and free slots interleaved in time order.
enum ScheduleTimeline {
    struct Row: Identifiable, Equatable {
        enum Kind: Equatable {
            case busy(CalendarEvent)
            case slot(Int, FreeSlot)
        }
        let id: String
        let start: Date
        let kind: Kind
    }

    static func rows(events: [CalendarEvent], slots: [FreeSlot]) -> [Row] {
        let busy = events.prefix(AppDesign.Schedule.maximumContextEvents).map {
            Row(id: "busy-\($0.id)", start: $0.startDate, kind: .busy($0))
        }
        let free = slots.enumerated().map { index, slot in
            Row(id: "slot-\(index)-\(slot.start.timeIntervalSinceReferenceDate)", start: slot.start,
                kind: .slot(index, slot))
        }
        return (busy + free).sorted { $0.start == $1.start ? $0.id > $1.id : $0.start < $1.start }
    }
}
