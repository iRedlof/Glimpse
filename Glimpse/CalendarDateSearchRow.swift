import GlimpseCore
import SwiftUI

/// The ⌘G "Ask Glimpse" field: prompt button when closed, native TextField when open.
@MainActor
struct CalendarDateSearchRow: View {
    @Binding var query: String
    @Binding var isActive: Bool
    let isProcessing: Bool
    let error: String?
    var clarification: String? = nil
    /// e.g. "3 free times" while a proposal is showing; the list announces it.
    var trailingChip: String? = nil
    let focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onDismiss: () -> Void
    let onEditorAppear: () -> Void
    var keyboardContext: () -> CalendarKeyboardContext = { .init(visible: false) }
    var keyboardObservation: ((CalendarKeyboardInvocation) -> Void)? = nil
    var controlFocus: FocusState<CalendarKeyboardOwner?>.Binding? = nil

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(
                    isProcessing ? Color.accentColor :
                    isActive ? Color.accentColor :
                    Color.secondary
                )

            if isActive {
                TextField(Self.placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .accessibilityLabel(Self.accessibilityName)
                    .accessibilityHint(Self.accessibilityHint)
                    .focused(focused)
                    .focusedValue(\.calendarKeyboardOwner, .editor)
                    .onSubmit { onSubmit() }
                    .onAppear(perform: onEditorAppear)

                if let trailingChip, !isProcessing {
                    Text(trailingChip)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, AppDesign.Spacing.xs + 2)
                        .padding(.vertical, AppDesign.Spacing.xs / 2)
                        .background(Capsule().fill(Color.accentColor.opacity(AppDesign.Schedule.chipBackgroundOpacity)))
                        .accessibilityHidden(true)
                }
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button(action: dismissSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(width: AppDesign.Control.dismissTargetSize,
                                   height: AppDesign.Control.dismissTargetSize)
                            .contentShape(Rectangle())
                            .overlay { CalendarKeyboardFocusOutline() }
                    }
                    .buttonStyle(.plain)
                    .modifier(CalendarControlReturn(
                        owner: .searchDismiss, context: keyboardContext, action: dismissSearch,
                        observe: keyboardObservation, focus: controlFocus
                    ))
                    .accessibilityLabel(Self.closeName)
                    .accessibilityHint("Clears the query and closes Ask Glimpse.")
                }
            } else {
                Button(action: openSearch) {
                    Text(Self.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppDesign.Spacing.xs + 2)
                        .padding(.horizontal, AppDesign.Spacing.xs + 2)
                        .overlay { CalendarKeyboardFocusOutline() }
                }
                .buttonStyle(.plain)
                .modifier(CalendarControlReturn(
                    owner: .searchPrompt, context: keyboardContext, action: openSearch,
                    observe: keyboardObservation, focus: controlFocus
                ))
                .accessibilityLabel(Self.accessibilityName)
                .accessibilityHint(Self.accessibilityHint)
            }
        }
        .padding(.horizontal, AppDesign.Spacing.sm)
        .padding(.vertical, isActive ? AppDesign.Spacing.xs + 2 : 0)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                .fill(Color.secondary.opacity(isActive ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.sm + 2)
                .strokeBorder(
                    isActive ? Color.accentColor.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive {
                isActive = true
            }
        }

        if let error = error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.primary)
        } else if let clarification {
            AIClarificationRow(message: clarification)
        }
    }

    nonisolated static let placeholder = "Type a date, plan or question"
    nonisolated static let prompt = "Ask Glimpse…  ⌘G"
    nonisolated static let accessibilityName = "Ask Glimpse"
    nonisolated static let accessibilityHint = "Go to a date, highlight dates, ask a question, or add an event."
    nonisolated static let closeName = "Close Ask Glimpse"

    private func openSearch() { isActive = true }

    private func dismissSearch() {
        onDismiss()
        // Keep the reused panel's existing text activation/restoration lifecycle.
    }
}
