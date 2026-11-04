---
paths:
  - "Glimpse/**/*View.swift"
  - "Glimpse/CalendarPopoverView.swift"
---

# SwiftUI View Rules

- Views take `StoreOf<Feature>` via `@Bindable var store`
- Use `store.scope(state:action:)` to pass child stores
- Use `$store.property.sending(\.action)` for bindings to TCA state
- Keep `body` lightweight — move heavy computation to the reducer
- Use `AppDesign` tokens for spacing, colors, corner radius, animation
- Calendar/footer buttons use `.buttonStyle(.plain)` and `.focusable(false)` except for the calendar keyboard controls below.
- Settings uses one non-lazy categorized page in a vertical scroll viewport. Controls preserve native keyboard focus, traversal and activation in document order; do not suppress their focus rings or add a second focus layer. Any local activation handler must prove the Settings window owns the current event.
- Calendar keyboard slice exception: month-header/search/footer and Quit-confirmation controls retain intrinsic Button focus (no extra `.focusable(true)` layer), with one inset focus outline. The calendar grid has one stable editing-focus container and a separate logical date outline; all 42 native date Buttons remain `.focusable(false)`. Local focused handlers and native editor submission own activation; focus requests and cached hierarchy absence never authorize shared-key consumption.
- Use `.contentShape()` to expand tap targets beyond visible content
- Avoid force unwraps in views — use `guard let` or `if let`
- Log errors in catch blocks — never use empty `catch {}`
- NSViewRepresentable for sharing AppKit views (e.g. StatusItemPreview)
