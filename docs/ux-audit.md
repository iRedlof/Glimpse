# Reliability UX audit

Audit date: 2026-11-01. This is a source audit of the calendar, preferences, panel, About window, and diagnostics. Native UI and restart checks belong to QA; no crash or missing-menu-bar reproduction is claimed here.

The user sometimes notices the menu bar item missing days after launch. Availability is the first priority: report what macOS has actually registered, offer a recovery path, and collect enough evidence to distinguish an exited process from a hidden menu bar item. Launch at login only establishes startup at a future login; it does not guarantee that the app remains running.

## First-iteration findings

### A6 — P1: Launch-at-login status can claim success before macOS enables it

Evidence:

- `GlimpseCore/Sources/GlimpseCore/Dependencies/LaunchAtLoginClient.swift:13–14` reduces `SMAppService.mainApp.status` to an enabled Boolean, losing approval-required and unavailable states.
- `GlimpseCore/Sources/GlimpseCore/Features/PreferencesFeature.swift:130–143` switches the UI on before registration, then clears the error without reading the resulting system status.
- `Glimpse/PreferencesView.swift:257–272` offers a switch and raw error text without a System Settings recovery action.
- `PreferencesFeature.swift:67–74` refreshes on view appearance only. The reused panel does not receive an appearance event on every show, and returning from System Settings while preferences remain open does not refresh this status.

Impact: registration can require user approval while the switch claims startup is enabled. Reopening preferences then shows it disabled, leaving the user without an explanation. This directly undermines confidence in restart behavior.

Small change: preserve the system status, show a short status message, expose “Open Login Items Settings” when approval is required, and refresh when the app returns from System Settings or preferences reopen. Display errors as actionable sentences rather than raw implementation text. Keep changes to the registration operation serialized or disable the switch while a change is pending.

Acceptance criteria:

1. The switch indicates enabled only when the current system status is enabled; a successful `register()` return alone is insufficient.
2. Approval required is shown as “Approval needed in System Settings” with “Open Login Items Settings.”
3. Disabled and unavailable registration are distinct. A registration error offers retry and preserves the last confirmed system state.
4. Enabling or disabling twice quickly cannot leave the switch displaying an older request's result.
5. Returning from System Settings refreshes the visible status without requiring an app restart or a preferences toggle.
6. Reopening preferences reads current system status, including a login item disabled externally.
7. QA verifies a signed, installed build after an actual logout/login or restart: the menu bar item appears, the status remains enabled, and the app does not require another permission prompt to show its basic calendar.

### A3/A2 — P1: The calendar intercepts editor and other-window keyboard events

Evidence:

- `Glimpse/CalendarPopoverView.swift:76–124` installs an application-wide local key monitor without checking `event.window`, panel visibility, or the current text responder.
- `CalendarPopoverView.swift:84–103` consumes arrow keys and Return even when the AI TextField is active. Arrow keys navigate months/years instead of moving the insertion point.
- `CalendarPopoverView.swift:56–64` removes monitors only on SwiftUI disappearance. `Glimpse/CalendarPanel.swift:114–122` and the repository gotchas explicitly state that hiding this reused panel does not cause disappearance.
- `Glimpse/AboutWindow.swift:9–11,26–27` can make another app window key while the calendar monitor remains installed.

Impact: an AI query cannot be edited normally with arrows; calendar shortcuts can consume events in About or while the panel is hidden. Shortcut recording adds another application-wide monitor and can compete with the calendar monitor.

Small change: scope calendar handling to its visible panel. Let normal editor/navigation keys pass through to a text field or picker. Preserve the explicit AI Return submission and layered Escape behavior. Give shortcut recording a defined priority and lifecycle.

Acceptance criteria:

1. Left/right, Option-left/right, and Command-left/right edit an active AI query without changing the displayed calendar.
2. Return submits an active, nonempty query once; an in-flight query cannot be submitted twice.
3. With focus in About or the panel hidden, arrows, Return, and Escape do not mutate calendar state or consume the other window's event.
4. Outside an editor, the visible calendar retains documented arrow navigation and Return-to-today behavior.
5. Escape closes the AI input first, then preferences, then the panel. Shortcut recording receives Escape to cancel before this sequence.
6. Hiding/reopening the panel cannot leave a shortcut recorder installed or a text field displayed without a working activation/focus path.
7. QA repeats show/hide, text input, About, preferences, pin/unpin, and shortcut recording without accumulating monitors or unexpected focus changes.

### A1/A6 — P2: Calendar denial and permission changes lack a recovery state

Evidence:

- `Glimpse/CalendarPopoverView.swift:537–551` presents “Show today's events” for every non-granted state.
- `GlimpseCore/Sources/GlimpseCore/Features/CalendarFeature.swift:78–91,177–191` represents authorization as a Boolean.
- `CalendarFeature.swift:218–237` refreshes events only when the cached Boolean is already true; it does not check the current authorization status.
- `GlimpseCore/Sources/GlimpseCore/Dependencies/EventKitClient.swift:18–23` turns request errors into `false`, indistinguishable from user denial.

Impact: after denial, the request button can do nothing useful. Granting access externally does not enable events on reopening; revoking access can leave the app displaying “No events today” instead of explaining why events are unavailable.

Small change: distinguish not determined, requesting, granted, denied/restricted, and read-access-unavailable states. Keep the initial permission request behind an explicit click. Offer the relevant Calendar privacy settings recovery action and refresh authorization when returning to the app or reopening the panel.

Acceptance criteria:

1. First launch shows a neutral opt-in action and never requests permission automatically.
2. Requesting permission shows progress and disables duplicate requests.
3. Denied access displays “Calendar access is off” with “Open Calendar Privacy Settings.”
4. Restricted access explains the restriction; write-only access does not claim permission to read events.
5. After an external grant or revocation, reopening/returning to the app immediately shows the corresponding state and clears data that is no longer authorized.
6. A permission request or query failure is distinguishable from a valid empty result.

### A6 — P2: Selected-date events are queried and labeled as today's events

Evidence:

- `GlimpseCore/Sources/GlimpseCore/Features/CalendarFeature.swift:135–160` fetches today's events when another date is selected and filters that limited result to the selected date.
- `GlimpseCore/Sources/GlimpseCore/Dependencies/EventKitClient.swift:29–38` queries only the current day.
- `Glimpse/CalendarPopoverView.swift:552–565` labels results “Today” or “No events today” regardless of selection.
- `CalendarFeature.swift:129–133,204–209` changes the selected date through Today/AI without consistently reloading matching events.
- `CalendarFeature.swift:16–17,193–195` has no loading or failure state; an empty array is immediately rendered as no events. Unidentified concurrent responses can overwrite a more recent selection.

Impact: choosing tomorrow commonly yields no results even when tomorrow has events. Loading is presented as a confirmed empty day, and a late response can pair one day's events with another day's selected date.

Small change: fetch the selected day's interval, tie the response to that date, and derive the heading and empty message from the same date. Show “Loading events…” until the relevant request completes. Cancel or reject stale responses.

Acceptance criteria:

1. Today and another selected day use that day's query interval and heading; empty results say “No events today” or “No events on [date]” appropriately.
2. While fetching, the UI shows loading rather than an empty-day claim. Previous-day events are not displayed under the new date's heading.
3. Tap, AI navigation, Today, deselection, and reopen all resolve to a single explicit event date and refresh the matching results.
4. Rapidly choosing two dates never allows the first date's later response to replace the second date's results.
5. All-day and multi-day events follow EventKit's overlap behavior for the selected day.
6. A fetch error offers retry for the same date instead of masquerading as no events.

### A7 — P1: Diagnostics can remain exporting indefinitely and omit availability evidence

Evidence:

- `Glimpse/DiagnosticsExport.swift:48–64` connects both process streams to a pipe but drains it only in the process termination handler. Sufficient log output can fill the pipe, prevent process exit, and leave the continuation waiting forever.
- `DiagnosticsExport.swift:24–44` exports preferences and calendar authorization but omits the login-item system status and running app bundle location.
- `DiagnosticsExport.swift:31` reads `hotkeyEnabled` with `bool(forKey:)`, reporting false when the unset preference actually defaults to true in the app.
- `DiagnosticsExport.swift:65–69` writes subprocess output as a successful report without distinguishing subprocess failure.
- `Glimpse/AboutWindow.swift:80–99,222–235` has no timeout or cancel path; failure replaces the action with text and provides no retry. Successful Finder recovery disappears after ten seconds.

Impact: the support action intended to explain missing availability can itself stall. A report lacks the information needed to distinguish enabled, disabled, approval-required, or wrong-installation startup configurations.

Small change: drain output during process execution, bound the operation, preserve a useful partial report on log failure, include actual startup status and bundle location, and retain a retry/export action. Keep the successful file discoverable until another export or window close.

Acceptance criteria:

1. Export succeeds with logs exceeding the pipe buffer; it finishes or produces a recoverable timeout state within a bounded interval.
2. Permission denial, command failure, or timeout collecting logs does not lose the rest of the diagnostics. The report explicitly records which collection step failed.
3. The report includes readable launch-at-login system status, app bundle path, app version/build, calendar permission, and the same effective hotkey default used by the product.
4. A failed export provides Retry. A completed export preserves “Show in Finder” long enough to use it without a ten-second deadline.
5. QA exports diagnostics immediately after launch, after sleep/wake, and after returning from Login Items Settings.

## Next-iteration findings

### A2 — P2: Expanded preferences can exceed the usable screen area

`Glimpse/CalendarPopoverView.swift:26–49` places preferences, calendar, events, and footer in one unscrollable VStack. `Glimpse/CalendarPanel.swift:82–91` caps window height at the entire visible-screen height while retaining the existing top edge. The menu bar gap means the actual space below that edge is smaller; content still has no scrolling path when compressed.

Verify on a laptop display/scaled resolution with AI enabled, five events, a launch-at-login error, and preferences open. Acceptance: the footer and every setting remain reachable, the panel stays inside the screen's visible frame with margins, and scroll gestures inside settings do not navigate calendar months.

### A1 — P2: Hidden control labels and tiny targets reduce reliable operation

`Glimpse/PreferencesView.swift:91–98,154–167,223–246,261–264,320–323` uses empty Toggle/Picker labels without explicit accessibility labels. The visible adjacent Text is not an explicit accessible name for the control. `Glimpse/CalendarPopoverView.swift:193–221,257–269,616–679` gives several icon actions only glyph-size hit areas; the AI clear button also lacks its own label. Date cells are Text plus tap gestures (`CalendarPopoverView.swift:445–487`) rather than semantic buttons.

Acceptance: VoiceOver names each preference control and announces its state; AI clear has a name; important icon targets are expanded with padding/content shape; date activation has a button action/role. Preserve the repository's deliberate focus-ring policy while verifying actual keyboard access.

### A3 — P2: Shortcut registration errors are visible only in logs

`Glimpse/PreferencesView.swift:405–413` saves the recorded combination and exits recording before obtaining a registration result. `Glimpse/GlobalHotkey.swift:58–84` unregisters the previous working hotkey, publishes the proposed combination, and logs failure without returning it to the UI.

Acceptance: a system registration conflict preserves the previous working shortcut and tells the user to choose another combination; the displayed shortcut reflects successful registration. Cancel recording without changing the shortcut.

### A4 — P2: An updater error has no retry action

`Glimpse/AboutWindow.swift:151–159` renders only error text. `Glimpse/SparkleUpdater.swift:105–108` leaves that state active. A transient connection problem removes “Check for Updates” until the state is reset elsewhere.

Acceptance: after an update error, retry is available when Sparkle permits it; initialization failure is visible rather than only disabling the check button.

### A5 — P2: Unavailable on-device AI suggests a nonexistent API-key setup

`Glimpse/CalendarPopoverView.swift:317–320` tells the user to set a Groq API key, although preferences expose Auto, Cloud AI, and On-device AI without an API-key field. `Glimpse/AIDateHelper.swift:23–29` shows that selecting On-device on an unsupported system reaches this path.

Acceptance: the message explains that on-device AI is unavailable and directs the user to Cloud AI or Auto. The intentional Auto-to-proxy behavior documented in known issues should remain unchanged.

## Review checklist coverage

- A1: permission gating is explicit; denial/revocation and accessible preference names need work.
- A2: existing reopen reset, pin behavior, positioning, and resize idempotency are present. Text-input/local-view reset and screen fit need native QA.
- A3: local key scope, editor behavior, recording lifecycle, and registration-result feedback need work.
- A4: About handles all declared update states; retry after failure needs work. Release/feed configuration is outside this UX audit.
- A5: unavailable-provider recovery copy needs correction; deferred Auto behavior is respected.
- A6: truthful system status and selected-date event consistency are the main correctness gaps.
- A7: bounded diagnostics, pipe draining, report fidelity, and reachable panel content support reliability.
- A8: current reducer tests cover Boolean login success/failure and basic selection/reopen. Add regressions for approval-required status, external status refresh, stale selected-date responses, permission changes, editor-safe key routing, and large/failing diagnostics output. Native restart, focus, screen-fit, and menu bar visibility checks remain QA acceptance tests.

## Availability evidence for QA

Record the installed app path and exact build for each run. On a missing-menu-bar report, first establish whether the process is running, then whether the status item is merely hidden by menu bar overflow. An empty display configuration already falls back to an icon (`Glimpse/MenuBarItemRenderer.swift:36–37`), so all display toggles being off is not evidence that the item was removed.

Test a signed installed build across login, restart, sleep/wake, midnight, and switching displays. Include repeated panel opening, AI edits, settings return, and diagnostics export. Record crash/exit evidence and resource measurements when available. Source review and passing unit tests alone cannot establish days-long uptime; report the observed validation interval honestly.
