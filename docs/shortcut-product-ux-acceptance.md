# Shortcut recovery: product and UX acceptance — 1.4.6 / build 13

Date: 2026-11-01. Scope: A3 P2 shortcut registration recovery in the
[UX audit](ux-audit.md), specified in
[the approved design](superpowers/specs/2026-11-01-shortcut-recovery-design.md).

**Scoped product and UX review passed for HK1–HK10 at source and
injected-contract scope.** The frozen 1.4.6/build 13 implementation satisfies
the bounded behavior below. Native interaction acceptance remains open. This
review does not set release readiness, replace code/QA/integration gates,
amend historical public v1.4.5 acceptance, or complete the reliability goal.

Reviewed against base source
`e0096f0e381fed6a55b8a72b26eac76afbb9704b`. The final tested files match the
11 hashes in the developer's final receipt; the before/after test snapshots are
identical. The private
[product/UX review receipt](/Volumes/xHome/Github/Glimpse/build/validation/shortcut-regression.YvSxPH/product-ux-review-receipt.json)
retains the exact source identity and criterion-by-criterion disposition.

## Required behavior

| ID | Acceptance | Evidence needed |
| --- | --- | --- |
| HK1 | A successful replacement advances the active, saved, and displayed combination together. The new callback handles activation and the previous registration is retired successfully. | Injected transaction tests and source review; native delivery separately. |
| HK2 | A rejected candidate preserves the previous usable registration, callback, saved combination, and displayed combination. Recording stays active for another attempt. Messages distinguish a reported collision from other failure and promise the prior shortcut works only when that is established. | Collision and generic failure regressions; UI decision/copy checks; native rejection exercise when reproducible. |
| HK3 | Requesting the same usable active combination succeeds without unregistering it. An inactive saved combination still attempts native registration. | Native-operation trace assertions for both states. |
| HK4 | Failed first enable leaves the switch off and the configured combination unchanged, introduces no saved enabled=true value, and keeps actionable failure copy and the recorder accessible. | Failed enable and returned-nil-handle regressions; native recovery UI. |
| HK5 | Failed startup registration retains the saved opt-in for a later launch, while preferences show actual inactive status and recovery copy. When inactive/requested=true, “Keep shortcut off” provides explicit opt-out despite the switch already being off. No silent combination substitution occurs. | Startup initialization/status, opt-out visibility and intent regressions; source review; signed app startup interaction separately. |
| HK6 | Escape, a second click on the recorder, panel hide, and preferences close cancel recording without changing requested state, saved/active combination, or callback. Cancellation alone never opts out of future startup retry. A rejected candidate is never displayed as the accepted shortcut. The recorder monitor is removed and calendar handling resumes. | Cancellation/state regressions and lifecycle source review; native monitor/focus cycles. |
| HK7 | Disabling during recording, including explicit “Keep shortcut off,” cancels capture before native teardown and saves the user's off intent without changing the configured combination. Successful disable reports inactive. Teardown/cleanup failure never claims successful disable or replacement; known usable state is retained or uncertainty is explicit, with recovery copy. | Ordering, inactive opt-out, unregister failure, rollback and cleanup regressions; native disable/re-enable checks. |
| HK8 | While inactive, “Set and enable shortcut” opens recording without enabling it. Success enables and persists the chosen combination; rejection stays recording and preserves prior intent/configuration. Cancellation remains inactive. “Keep shortcut off” appears only when inactive/requested=true, has an accessible name and existing styling, and cancels recording before saving requested=false; actual remains off unless native cleanup leaves reported uncertainty. Successful retry clears the failure; cancellation preserves a still-applicable unavailable state. If recorder monitor installation returns nil, recording remains inactive, settings/native registration stay unchanged, and “Glimpse couldn’t record a shortcut. Try again.” is shown; there is no recording=true notification or dangling “Press shortcut...” state. | Inactive recorder, explicit opt-out, monitor-acquisition failure, retry, persistence and cancellation regressions; native visible state transitions. |
| HK9 | `isRegistered` is true only when registration, native handles, event-handler installation, and callback are usable. Failure releases acquired candidate resources; missing handles and install/unregister failures are surfaced and cannot produce false success. | Independent injected-operation failure/cleanup tests and A3/A7 review. |
| HK10 | Diagnostics distinguish saved requested state from actual registration. Product copy makes no promise of exclusive ownership or detection of every cross-app shortcut conflict. | Diagnostic output/copy regressions and review of Carbon options=0 semantics. |

## Reviewed implementation and evidence

| Criteria | Inspected source and regression evidence |
| --- | --- |
| HK1–HK3 | `GlobalHotkey.register` prepares a candidate before retiring the previous key, commits accepted state and saves the combination only after native success, and keeps the active same-combination fast path. Tests cover successful replacement, preserved registration/callback/persistence on rejection, same-combination callback updates, and stale/foreign event suppression. |
| HK2, HK7, HK9 | Failed retirement rolls back the candidate while retaining the old registration. Failed cleanup remains owned for retry and blocks another transaction until resolved. Missing references, registration failure, handler installation/removal failure, failed unregistration, and pending candidate/handler cleanup have regressions. Native failure cannot silently publish success. |
| HK4–HK5 | `HotkeyPreferencesModel` derives enabled state from usable registration. A failed enable does not save success; startup failure remains visible when preferences reopen while retaining saved opt-in. “Keep shortcut off” changes requested intent without replacing the configured combination. The observed requested value has a regression proving a view notification when that alone changes under a repeated identical cleanup error. |
| HK6–HK8 | Recorder installation precedes recording state/notification. Owned visible/key-panel guards and modifier checks preserve pass-through; Escape and repeated cancellation remove the fixture monitor once. Hide/disappear share that cancellation path in source. Tests cover reserved rejection, inactive enable-on-success, failed recording/retry, explicit off, and nil monitor without recording=true notification. |
| HK2, HK8 | Consumer regressions verify exact contextual conflict, generic replacement, inactive enable, disable, cleanup, reserved-input, and monitor-failure messages. Failed old-key retirement uses replacement-specific copy during recording, after cancellation, and on preferences reopen, with the prior combination and requested intent preserved. |
| HK8 | Preferences retain the existing card, mini switch, recorder typography and AppDesign tokens. The inactive recorder and conditional opt-out remain visible. Explicit accessible names and dynamic recording/enable/change hints are present in source. Their actual spoken output and visual fit remain unverified. |
| HK10 | Diagnostic output has separate requested, registered, saved-combination, active-combination and error lines. Tests distinguish failed startup from requested-off/failed-native-teardown. Carbon registration retains options=0; the UI reports a collision only for a native collision result. |

Fresh inspection of
[App-Acceptance-GREEN.xcresult](/Volumes/xHome/Github/Glimpse/build/validation/shortcut-regression.YvSxPH/App-Acceptance-GREEN.xcresult)
through `xcresulttool` confirms **93 passed tests in 11 suites**, with zero
failures, skips, expected failures or runtime warnings. The retained log says
`TEST SUCCEEDED`; its 105 parameterized executions are not 105 distinct tests.
The
[final developer receipt](/Volumes/xHome/Github/Glimpse/build/validation/shortcut-regression.YvSxPH/developer-final-receipt.json)
and
[independent root audit](/Volumes/xHome/Github/Glimpse/build/validation/shortcut-regression.YvSxPH/root-final-green-audit.json)
match that result and all 11 current app/test/project/pin hashes.

Earlier 87-test and 92-test snapshots remain historical evidence. They are not
the final acceptance run. The final receipt records failing regressions before
the contextual-copy, requested-value Observation, and replacement-retirement
message corrections; the last correction reproduces incorrect copy during
recording, after cancellation and on reopen before becoming green.

Independent QA's
[recorded final runs](/Volumes/xHome/Github/Glimpse/build/validation/shortcut-independent-qa.x52oj3w0/acceptance-runs.json)
passed **37 focused tests in 3 suites**: 34 production coordinator/model tests
copied byte-for-byte from the frozen files and 3 supplementary tests. PM/UX
verified the four production/test copies and the successful log. A separate
[production Carbon adapter probe](/Volumes/xHome/Github/Glimpse/build/validation/shortcut-independent-qa.x52oj3w0/abi-native.log)
passed bounded process-local installation, EventRef decoding/dispatch and
handler removal. It rejected foreign-signature and missing-parameter events,
suppressed queued/post-removal callbacks, released six owned events, and left
no handler. It made zero native global-hotkey registration calls and did not
touch shared defaults, local recorder monitors, app activation or installed
state. Accepted-ID/generation filtering remains supported by injected
coordinator tests.

## Targeted UX checks

Retain the current Features card, mini switch, recorder typography and
AppDesign tokens. Verify that enabled, deliberately off, failed enable,
failed startup, recording, rejection, cancellation and successful retry each
have a clear visible state. The inactive action must make enabling explicit.

The switch has an explicit accessible name. The recorder's accessible name and
hint identify recording and cancellation. Inline copy remains readable when
wrapped; it does not expose OSStatus values. VoiceOver output and panel fit
require actual native inspection. Broader accessibility and small-display
audit findings stay open.

The current Carbon options=0 registration can permit sharing a combination
with another app. An accepted registration is evidence of Glimpse's usable
registration, not exclusive desktop ownership. QA must not manufacture a
conflict expectation from another app's shortcut alone.

## Native checks still required

On an authorized signed installed build, exercise successful replacement,
same-combination recording, reserved-input rejection, cancel, disable,
inactive “Set and enable shortcut,” and repeated hide/reopen/About transitions.
Verify delivery of the active shortcut and no delivery from a retired
registration. Exercise a native rejection when it can be reproduced reliably;
otherwise report that coverage as missing.

Repeat capture/cancel/retry and panel transitions without accumulating
monitors, changing the calendar unexpectedly, intercepting About keys, or
breaking AI text editing. Inspect actual VoiceOver names/state/hints and
wrapped error messages on a small/scaled display.

Unit and fixture tests establish only the paths they exercise. They do not
establish native event ownership/delivery, live conflict recovery, monitor
lifetime, accessibility, restart reliability, crash elimination, or sustained
performance.

## Integration gates and broader limits

The scoped PM/UX acceptance above covers the frozen implementation and recorded
source/injected-contract evidence against HK1–HK10. Final QA disposition,
independent A1–A8 code review, staged checks, checks for every introduced commit
and merge source, previous-release verification, and signed artifact/public-feed
verification remain separate integration gates. A passing process-local
adapter check does not close desktop shortcut or native UI acceptance.

The crash on the other Mac remains unexplained. Installed-build login/restart,
sleep/wake, multi-display, date rollover, diagnostics Powerbox, endurance, and
performance criteria remain open. This scoped recovery work does not complete
the broader reliability goal.
