# Gotchas & Hard-Won Debugging Insights

## NSPanel Behavior

- **onAppear/onDisappear don't fire on panel reshow**: NSPanel reused via
  orderOut/orderFront doesn't trigger SwiftUI onAppear OR onDisappear, and the TCA
  store is created once and lives for the panel's lifetime. So any reset wired to
  `.onDisappear` (e.g. "reset to current month") silently never runs across a
  hide/show cycle. Reset the reused store from the show path instead:
  `CalendarPanel.prepareForReopen()` (sends `.prepareForReopen`) is called from
  CalendarStatusItem.showPanel(). It collapses preferences, resets to the current
  month with today selected, and reloads preferences.

- **TextField in non-activating panel**: `.nonactivatingPanel` prevents keyboard focus.
  Must call `NSApp.activate(ignoringOtherApps: true)` via `panel.activateForTextInput()`.
  Restore previous app on deactivate.

- **Key monitor intercepts Enter**: `NSEvent.addLocalMonitorForEvents` intercepts
  keyCode 36 before SwiftUI `onSubmit`. Handle Enter explicitly in the monitor when
  AI field is active.

- **Custom NSView subview in status button = CPU loop (macOS 26)**: Adding a child
  `NSView` to `NSStatusItem.button` pegs the CPU (~40% sustained, panel closed) on
  macOS 26 Tahoe. The status button is backed by a scene-managed `NSStatusItemScene`/
  `FBSScene`; a child view never settles its content frame, so `_setSelectedContentFrame
  → updateSettings:transition → newFence` fires every runloop pass forever. Confirmed by
  `sample` (continuous `CA::Transaction::commit`) and by controlled experiment (removing
  the subview → 0% CPU). Fix: composite the whole item (border, fill, icon, separator,
  text) into ONE `NSImage` via `MenuBarItemRenderer` and set it as `button.image`
  (`.imageOnly`). Never add a subview to the status button.

- **Don't KVO the status button's effectiveAppearance**: re-rendering on
  `button.observe(\.effectiveAppearance)` loops — setting `button.image` invalidates the
  bezel, which re-evaluates appearance, which re-fires the observer (observe→mutate→
  observe, ~90% CPU). Use `DistributedNotificationCenter`'s
  `AppleInterfaceThemeChangedNotification` instead; it doesn't reenter on image updates.

- **intrinsicContentSize KVO resize loop (high CPU)**: `CalendarPanel` observes
  `NSHostingView.intrinsicContentSize` to auto-size, and the handler calls
  `setFrame`. But `setFrame` triggers a hosting-view layout pass that re-emits the
  KVO notification → observe→setFrame→observe. The 0.05s debounce only rate-limits
  it to ~20 Hz; it does NOT terminate the loop, so on some displays/macOS versions
  it pegs the main thread while the panel is open. Fix: `resizeToFitContent()` has
  an idempotency guard — if the computed frame matches the current frame within a
  0.5pt tolerance, return without calling `setFrame`. Any future observe→mutate
  cycle needs the same guard to converge.

## Build & Project

- **Sparkle Team ID mismatch**: Pre-built Sparkle.framework has a different Team ID.
  Local builds need `codesign --force --sign -` on embedded frameworks. CI uses
  `xcodebuild -exportArchive`.

- **pbxproj UUID collisions**: `AA00000000000000000020` is used by Frameworks build
  phase. Use `DD`-prefixed UUIDs for new app files.

- **`-skipMacroValidation` required**: TCA macros need this flag for both build and test.

- **`#if canImport(FoundationModels)`**: Required for CI (macOS < 26). The
  `@available(macOS 26, *)` guard alone isn't enough — the import itself fails.

## TCA / SwiftUI

- **Capturing state in .run closures**: Always capture specific values before the
  `.run` block, never capture `[state]`.

- **Result<Void, Error> in TCA actions**: Causes Swift compiler crashes. Use separate
  success/failure actions.

- **onChange on TCA @ObservableState bindings**: Does NOT reliably fire. Use custom
  Bindings that post NotificationCenter notifications instead.

- **`@Dependency(\.date)` not `Date()`**: Direct Date() in reducers breaks purity
  and test determinism.

## Git

- **`git commit --amend` must use `--no-edit`**: When amending a commit (e.g., to add
  a version bump), NEVER pass `-m` — it overwrites the original commit message. Always
  use `--no-edit` to preserve the existing message. If the message needs changing, that
  should be a deliberate separate action, not a side effect of an amend.

## AI

- **The on-device model miscounts weekdays**: given only "today is Sunday", the small
  FoundationModels model answered "next Friday" with a Tuesday and gave "Mar 1" the past
  year. Days the query names are resolved in Swift (`DayPhraseParser`, used by
  `AIIntentDecoder.validate(_:today:query:)`) and win over model dates; the prompts carry
  a 28-day date table for phrases Swift can't read. A flat all-fields `@Generable` also
  made it file questions as events; one enum case per intent fixed that.

## Date Handling

- **ISO 8601 timezone**: `ISO8601DateFormatter` defaults to UTC → off-by-one dates.
  Use `DateFormatter` with `TimeZone.current`.

- **Use `Date.FormatStyle` over `DateFormatter`**: `DateFormatter` is not thread-safe.
  `Date.FormatStyle` (macOS 12+) is thread-safe and preferred in all new code.
  Never create `DateFormatter` in computed properties or hot paths.

## Menu Bar

- **StatusItemView rendering**: StatusItemView is a subview of NSStatusBarButton.
  It cannot draw borders or backgrounds — the button's own rendering covers them.
  Style the button's layer directly in CalendarStatusItem.updateMenuBarDisplay().

- **Menu bar refresh**: NotificationCenter `.menuBarDisplayDidChange` is the reliable
  path. Direct onChange or AppDelegate access don't work consistently.
