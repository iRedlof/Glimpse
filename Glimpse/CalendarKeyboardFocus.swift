import AppKit
import SwiftUI

private struct CalendarKeyboardOwnerKey: FocusedValueKey {
    typealias Value = CalendarKeyboardOwner
}

extension FocusedValues {
    var calendarKeyboardOwner: CalendarKeyboardOwner? {
        get { self[CalendarKeyboardOwnerKey.self] }
        set { self[CalendarKeyboardOwnerKey.self] = newValue }
    }
}

/// Hierarchy observations are snapshots. Absence alone never authorizes browse.
@MainActor
final class CalendarKeyboardOwnerRelay {
    private(set) var owner: CalendarKeyboardOwner?
    private(set) var observed = false
    private weak var responder: NSResponder?

    func observe(_ owner: CalendarKeyboardOwner?, panel: CalendarPanel?) {
        self.owner = owner
        observed = true
        responder = panel?.firstResponder
    }

    func reset() {
        owner = nil
        observed = false
        responder = nil
    }

    func browseOwnership(in panel: CalendarPanel) -> CalendarKeyboardBrowseOwnership {
        CalendarKeyboardRouter.ownership(
            published: owner, observed: observed,
            responderIsWindowDefault: panel.firstResponder === panel,
            snapshotMatchesResponder: responder != nil && responder === panel.firstResponder
        )
    }
}

@MainActor
struct CalendarKeyboardOwnerObserver: View {
    @FocusedValue(\.calendarKeyboardOwner) private var owner
    let relay: CalendarKeyboardOwnerRelay
    weak var panel: CalendarPanel?
    let session: Int
    var onOwnerChange: (CalendarKeyboardOwner?) -> Void = { _ in }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: owner, initial: true) { _, owner in
                relay.observe(owner, panel: panel)
                onOwnerChange(owner)
            }
            .onChange(of: session) { _, _ in
                relay.observe(owner, panel: panel)
                onOwnerChange(owner)
            }
    }
}

@MainActor
struct CalendarGridKeyboardContent<Content: View>: View {
    let isEligible: Bool
    let focus: FocusState<CalendarKeyboardOwner?>.Binding
    let context: () -> CalendarKeyboardContext
    let move: (Int) -> Void
    let activate: () -> Void
    var observe: ((CalendarKeyboardInvocation) -> Void)? = nil
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        ZStack {
            CalendarGridKeyboardAppearance(content: content)
        }
            .focusable(isEligible, interactions: .edit)
            .focusEffectDisabled()
            .focused(focus, equals: .grid)
            .focusedValue(\.calendarKeyboardOwner, .grid)
            .onKeyPress(phases: [.down, .repeat]) { press in
                // Attach to the focusable control, after focus registration.
                // The descendant appearance view reads focus for drawing only.
                let context = keyContext(press, from: context())
                let key = CalendarKeyboardKey(press)
                let phase = CalendarKeyboardPhase(press)
                let route = CalendarKeyboardRouter.local(
                    key, phase: phase, owner: .grid, context: context
                )
                observe?(.init(owner: .grid, key: key, phase: phase, route: route,
                               context: context, focusRenderingSnapshot: nil))
                switch route {
                case let .move(delta): move(delta)
                case .activate: activate()
                case .consume: break
                default: return .ignored
                }
                return .handled
            }
    }
}

@MainActor
private struct CalendarGridKeyboardAppearance<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(isFocused)
            .preference(key: CalendarGridFocusPreference.self, value: isFocused)
    }
}

struct CalendarGridFocusPreference: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

@MainActor
struct CalendarControlReturn: ViewModifier {
    let owner: CalendarKeyboardOwner
    let context: () -> CalendarKeyboardContext
    let action: () -> Void
    var observe: ((CalendarKeyboardInvocation) -> Void)? = nil
    var focus: FocusState<CalendarKeyboardOwner?>.Binding? = nil
    var isEnabled: Bool = true

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .modifier(CalendarControlFocusBinding(owner: owner, focus: focus))
            .focusedValue(\.calendarKeyboardOwner, owner)
            .onKeyPress(phases: [.down, .repeat]) { press in
                let context = keyContext(press, from: context())
                let key = CalendarKeyboardKey(press)
                let phase = CalendarKeyboardPhase(press)
                let route = CalendarKeyboardRouter.local(key, phase: phase, owner: owner, context: context, isEnabled: isEnabled)
                observe?(.init(owner: owner, key: key, phase: phase, route: route,
                               context: context, focusRenderingSnapshot: nil))
                switch route {
                case .activate: action(); return .handled
                case .consume: return .handled
                default: return .ignored
                }
            }
    }
}

/// This binding dismisses focus during lifecycle reset; it never authorizes input.
@MainActor
private struct CalendarControlFocusBinding: ViewModifier {
    let owner: CalendarKeyboardOwner
    let focus: FocusState<CalendarKeyboardOwner?>.Binding?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus, equals: owner)
        } else {
            content
        }
    }
}

/// Optional read-only callback receipts for an injected owned-panel fixture.
/// Neither rendering snapshots nor these receipts request or decide focus.
struct CalendarKeyboardInvocation: Sendable {
    let owner: CalendarKeyboardOwner
    let key: CalendarKeyboardKey
    let phase: CalendarKeyboardPhase
    let route: CalendarKeyboardRoute
    let context: CalendarKeyboardContext
    let focusRenderingSnapshot: Bool?
}

struct CalendarKeyboardFocusOutline: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.self) private var environment
    var color: Color? = nil

    var body: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: AppDesign.Control.focusCornerRadius)
                .strokeBorder(color ?? AppDesign.Colors.calendarEssentialAccent(in: environment),
                              lineWidth: AppDesign.Control.focusLineWidth)
                .padding(AppDesign.Control.focusInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private func keyContext(_ press: KeyPress, from context: CalendarKeyboardContext) -> CalendarKeyboardContext {
    var context = context
    context.modified = context.modified ||
        !press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty
    return context
}

private extension CalendarKeyboardKey {
    init(_ press: KeyPress) {
        switch press.key {
        case .leftArrow: self = .left
        case .rightArrow: self = .right
        case .upArrow: self = .up
        case .downArrow: self = .down
        case .return: self = .returnKey
        case KeyEquivalent("\u{3}"): self = .keypadEnter
        case .space: self = .space
        case .tab: self = .tab
        default: self = .other
        }
    }
}

private extension CalendarKeyboardPhase {
    init(_ press: KeyPress) {
        self = press.phase == .down ? .down :
            press.phase == .repeat ? .repeatPress : .up
    }
}
