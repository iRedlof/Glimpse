# Shortcut registration recovery

Date: 2026-11-01. This bounded iteration addresses the A3 P2 finding in
[the UX audit](../../ux-audit.md). The Tech Lead approved the behavior below as
implementation judgment within the user's reliability goal. Approval of this
design does not establish implementation, native QA, or release readiness.

## Problem and intent

The current recorder saves a proposed combination before macOS accepts it.
`GlobalHotkey.register` removes the previous working registration and publishes
the proposed combination and instance before knowing whether registration or
event-handler installation succeeded. The preferences switch persists an
enabled request independently of the native result.

A rejected replacement can therefore remove a usable shortcut, display an
unusable combination, and give the user no recovery path. Fix this transaction
and make the existing preferences row report actual availability.

Keep the current Features card, mini switch, monospaced recorder, inline caption
messages, AppDesign spacing, and deliberate focus policy. Do not redesign the
calendar, change AI behavior, or broaden shortcut reservation rules.

## State and transaction contract

Treat these as separate facts:

- **Requested:** the saved `hotkeyEnabled` preference, including the existing
  default of true when the preference is absent.
- **Configured:** the validated saved combination, or the existing default.
- **Usable now:** a valid native hotkey registration with a working event
  handler and callback.

The switch reflects usable registration. A saved opt-in alone cannot put the
switch on. `isRegistered` can be true only for a usable registration.
Diagnostics distinguish requested and actual registration state rather than
calling the stored preference proof of availability.

Prepare and validate a candidate before replacing a working registration.
Publish the new active combination and callback, save the combination, and
persist enabled=true only after the required native operations succeed. A
failed candidate must not alter the previous saved, displayed, or active
combination, or its working callback.

Registering the already active combination succeeds without tearing it down.
This shortcut applies only when the existing registration is usable. An
inactive saved combination must still undergo real registration.

Native success status with a missing returned handle is failure. Failed
registration or handler installation releases any candidate resources that
were acquired. Failures retiring an old registration or cleaning up a candidate
must not be reported as successful replacement or disablement. Preserve known
usable resources and expose failure; if usability cannot be established, report
that uncertainty instead of claiming the shortcut works or is off. Retain
native failure details in logs, without exposing OSStatus codes in UI.

## Existing preferences flow

With a usable shortcut, the recorder button shows the active combination.
Clicking it begins recording and displays **Press shortcut...**. A successful
replacement ends recording and shows the newly active combination. A rejected
candidate keeps recording active so another combination can be attempted.

Begin recording only after acquiring its local event monitor. If monitor
installation returns nil, remain inactive, preserve saved settings and native
registration, and show the recording-setup retry message below. Do not publish
a recording=true notification or leave **Press shortcut...** displayed.

While inactive, keep a visible **Set and enable shortcut** action. This includes
deliberately disabled and failed-startup states. Clicking the action only begins
recording; it does not enable or persist anything. Successfully recording a
usable combination both configures and enables the shortcut. Escape, clicking
the recorder again, hiding the panel, or closing preferences cancels unchanged.
If an inactive combination is shown, identify it as configured rather than
working.

Turning the switch on attempts the configured combination. Failure leaves the
switch off, leaves the combination unchanged, and does not introduce a saved
enabled=true value. Keep the failure message and recorder action visible when
the switch is off. Turning the switch off first cancels recording and removes
its event monitor, then attempts native unregistration and records the user's
off intent. A native teardown error remains visible and must not falsely imply
that a still-usable shortcut was removed.

Startup still attempts registration when the saved preference requests it.
Startup failure preserves that opt-in so a later launch can retry, but
preferences must show the actual inactive state and recovery message when
opened. Do not silently substitute the default or a different combination.

When actual registration is inactive but the saved request is true, show a
small **Keep shortcut off** action in the shortcut recovery area, alongside
the status and recorder. The already-off switch cannot emit an off request,
so this action explicitly opts out of retry on future launches. Use the
existing plain button styling and an explicit accessible name.

The action first cancels recording, then uses the same disable operation to
save requested=false while preserving the configured combination. Actual
registration stays off when cleanup is confirmed. A native cleanup failure
still displays its uncertainty or known usable status rather than reporting
false success. Show the action only for inactive/requested=true; ordinary
recording cancellation alone does not change the saved request.

On a successful retry, clear the previous failure message. Starting another
recording attempt may clear the previous attempt's message; cancellation must
restore any still-applicable unavailable-startup/enable state. Cancellation of
a rejected replacement must not leave the rejected combination displayed.

Keep the existing panel/window guards and recording-priority notification.
Recording operates only for the visible key calendar panel. Hiding the panel,
closing preferences, or disabling the shortcut removes the recorder monitor
and restores calendar handling. Normal calendar input, AI editing, and About
window handling retain their existing contracts.

## Copy

Use short inline captions in the existing error style. The context determines
whether a previous working shortcut can be promised.

| Condition | Message |
| --- | --- |
| macOS rejects the candidate as already registered; prior shortcut usable | “That shortcut is already in use. Choose another combination. Your previous shortcut still works.” |
| Same rejection without a usable prior shortcut | “That shortcut is already in use. Choose another combination.” |
| Other replacement failure; prior shortcut usable | “Glimpse couldn’t use that shortcut. Try another combination. Your previous shortcut still works.” |
| Enable, startup, or handler-installation failure without a usable shortcut | “Glimpse couldn’t enable this shortcut. Try again or choose another combination.” |
| Existing reserved-combination validation rejects input | “[combination] is a reserved shortcut. Choose another combination.” |
| Recorder event-monitor installation returns nil | “Glimpse couldn’t record a shortcut. Try again.” |
| Disable fails while the prior shortcut remains usable | “Glimpse couldn’t turn off this shortcut. Try again.” |
| Cleanup leaves native state unconfirmed | “Glimpse couldn’t confirm the shortcut’s status. Try again.” |

Carbon registration retains the current options=0 behavior. That behavior does
not guarantee exclusive ownership across apps, and macOS may accept a
combination used elsewhere. Report a collision only when macOS rejects it; do
not claim that all competing app shortcuts are detected or prevented.

Give the existing switch and the recorder explicit accessible names and an
appropriate recording hint. Wrapped messages must remain readable in the
current panel. This targeted treatment does not close the broader screen-fit
or accessibility audit.

## Acceptance and verification boundary

[Shortcut product and UX acceptance](../../shortcut-product-ux-acceptance.md)
defines HK1–HK10, test evidence, and native checks. Developer and QA must
reconcile native failure/cleanup behavior before declaring those criteria met.

Injected native-operation tests can prove transaction order, rollback
decisions, callback and persistence preservation, and status/copy decisions.
They do not prove Carbon event delivery, real desktop conflicts, monitor
lifetime, VoiceOver output, or visual fit. Signed native validation remains
separate and requires authorization to replace/restart the installed app.

The other-machine crash, machine restart/login reliability, sleep/wake,
long-term availability, and sustained performance remain open. This change
must pass the existing product, UX, code, QA, exact-source, CI, and artifact
gates before publication; it does not independently authorize release.
