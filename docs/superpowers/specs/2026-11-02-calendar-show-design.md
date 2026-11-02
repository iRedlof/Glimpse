# Reliable explicit calendar Show

Status: lead-selected design under the user's instruction to navigate and work autonomously. No additional approval or routine opening request is needed. Implementation and native acceptance are pending.

## Intent and evidence

An explicit “Show Glimpse Calendar” request should open or raise the calendar. Today its AppIntent calls `statusItemClicked()`, a toggle that can close a visible unpinned calendar. The intent also returns success when its concrete application-delegate cast fails or when presentation cannot occur. Normal reopening of the already-running menu-bar app has no calendar handler.

The installed v1.4.11 calendar was initially observed open. Later CUA reads/navigation, Shortcuts actions and Finder reopening did not produce an accepted panel observation. These timeouts do not diagnose a crash or prove that an intent did not execute. Record the actual guarded test-host delegate type and cast outcome; do not assert a guessed SwiftUI implementation.

## Behavior

- Add one main-actor, throwing `CalendarStatusItem.showCalendar()` operation.
- Hidden or never-created: validate the normal status-anchor geometry first, create/reuse one panel, invoke `prepareForReopen()` once and raise it. Preserve the existing reset-to-today, preference reload and authorized event refresh behavior.
- Already ordered in (`panel.isVisible`): reuse and raise the same panel. Preserve month/date, expanded preferences, pin state, editor draft/selection/first responder and event/monitor lifecycle. Do not call prepare or orderOut. Occlusion does not turn an existing panel into a hidden one.
- For an existing visible panel, update valid placement; otherwise retain its prior frame and raise it. A hidden panel with missing or invalid geometry fails before allocation or lifecycle notifications.
- Add `CalendarShowCommand`, a small main-actor owner for the registered throwing Show target. Missing registration fails explicitly; do not buffer requests, add arbitrary waits, or claim future delivery.
- The actual `ShowCalendarIntent.perform()` uses this owned command, without casting `NSApp.delegate`. Errors propagate through the system's existing intent error surface.
- Production startup registers the owned status item after its existing setup. Registration alone never opens a panel.
- `AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)` requests Show for both flag values and returns false after custom handling. Log presentation failures without claiming success. About-window visibility must not suppress the calendar.
- Menu-bar click and global hotkey retain their toggle, pin and cross-screen behavior. Preserve quiet launch at login and the `XCTestBundlePath` startup guard.

## Implementation choices and scope

Use the existing macOS 14+, Swift 6, AppKit/SwiftUI/AppIntents/TCA structure and locked dependencies. No new URL scheme, scripting interface, dependency, permission, startup preference or blanket app activation is needed. Keep text activation and previous-app restoration in `CalendarPanel`.

Use narrow initializer seams for status-anchor geometry, real panel construction and the existing toggle visibility/screen observations. Production defaults preserve current behavior. Tests own offscreen actual `CalendarPanel` windows with injected stores and inert content, never a live NSStatusItem or production preferences/calendars.

Keep the command in `AppIntents.swift`; `register(_:)` returns its previous closure so serialized tests can restore a scoped registration. Inject the command/status owner into owned AppDelegate fixtures without replacing the application’s real delegate.

This covers already-running Finder reopening and explicit AppIntent requests. Cold Finder launch versus login launch is a separate lifecycle design; do not open unconditionally during startup. A cold intent arriving before route readiness reports a retryable error. Actual native ordering, focus, Spaces/displays and system callback forwarding remain separate acceptance checks.

## Verification and delivery

First exercise unchanged `ShowCalendarIntent.perform()` in the guarded test host: an undeliverable request must throw. Retain its actual delegate observation and the expected behavioral RED, rather than accepting a missing-symbol compiler error as the root regression.

Then use real owned panels to verify repeated visible Show, hidden reopening, geometry failure, reanchoring, pin/editor preservation and unchanged toggle behavior. Execute the actual intent and reopen callback through that fixture. Verify guarded startup leaves production setup/command registration untouched.

Use focused behavioral regressions, then the ordinary exact staged-source quality gate and one independent A1–A8 whole-branch review. Synchronize all four marketing versions to 1.4.13, all four build numbers to 20 and the README badge. Readiness approvals must refer to actual candidate evidence; protected integration and public/signed installation checks are separate.

The original other-machine crash remains unexplained. Real restart testing is user-deferred. CPU/memory observations do not establish optimized performance or endurance, and tool timeouts remain unaccepted native checks.
