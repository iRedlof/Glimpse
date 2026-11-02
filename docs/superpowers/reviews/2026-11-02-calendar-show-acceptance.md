# Explicit calendar Show acceptance

2026-11-02. Candidate **v1.4.13/build20**, isolated branch `codex/calendar-show`, starting at pending PR18 candidate `808f690fbd052646c537a97de52bcaf490786cf1` / tree `2b88186d4765852027fe3839f7e832b9514b619b`.

**Status: implementation, affected fixture verification and independent review adjudication accepted. The revised candidate whole-quality hook passed475 names; the subsequent Important review fix passed33 affected names/41cases. Product, UX, Code and QA decisions below accept this scope. The final ordinary staged-source hook, protected integration, signed delivery and native navigation remain required.**

## Resulting behavior

Explicit Show uses an owned main-actor command instead of casting the SwiftUI application's delegate. Missing registration and unavailable/invalid hidden-panel geometry throw a localized error. Already-running reopening requests Show for either window-visibility flag.

An ordered-in calendar is raised without hiding, resetting, replacing the panel or sending prepare/show hooks. Valid changed placement is applied; unavailable/invalid placement retains the existing frame. Hidden reopening keeps the existing reset-to-today, preference reload and authorized-event behavior. Click/hotkey toggle, pin, text activation, reusable-panel hooks, quiet startup and the test-host guard are preserved.

The existing delayed cross-screen completion now also uses explicit Show. A newer explicit Show or toggle invalidates its request identity. The stale completion therefore cannot reset newer visible state or reopen after a newer close; an unsuperseded request retains the existing50ms presentation behavior.

[Design](../specs/2026-11-02-calendar-show-design.md) and [plan](../plans/2026-11-02-calendar-show.md) record the chosen scope and interfaces. No Core code, dependency lock, permission, startup preference, signing or update transport changes.

## Observed verification

Evidence is retained outside tracked source under `build/validation/update-guidance-implementation.bpo8vktn/open-show-implementation/`.

| Gate | Actual result |
| --- | --- |
| Unchanged-source intent RED | One executed test failed because actual `ShowCalendarIntent.perform()` returned success without delivery. Exit65, no timeout, source/pins unchanged. The real guarded test-host delegate was `SwiftUI.AppDelegate`; the concrete cast was false. This is a host observation, not a claim about every signed runtime. |
| Presentation/routing RED | Ten names executed against the injected old toggle path and absent reopen callback. Visible state, lifecycle, geometry/error propagation and both reopen flags failed. Raw34 issues include two fixture hide-count expectations subsequently corrected for actual AppKit reentrancy. |
| First focused GREEN | 31 names/39 cases across Show, status, panel-layout and input suites passed. One owned editor fixture hierarchy warning required correction. |
| Corrected focused GREEN | 31 names/39 cases passed; zero failures, skips or xcresult runtime warnings. Source/pins unchanged during the bounded run. Actual native field editor draft, selected range and first responder were preserved. |
| Initial ordinary whole-source hook | 474 named tests passed: App212/529cases, Core70, tooling165, monitor27. Source tree2abf3a5ce998c47a3dbf3c5958ee1251af6c6312; pins unchanged, zero failures/skips/xcresult runtime warnings. |
| Interleaved display completion RED | Eleven Show names executed; the added regression alone failed because the delayed completion reset the newer date/preferences, reloaded preferences and emitted an extra show notification. Exit65, source/pins unchanged. |
| Interleaved display completion GREEN | 32 affected names/40cases passed after the completion-path fix. Zero failures/skips/xcresult runtime warnings; source/pins unchanged. Actual native editor and existing toggle/cross-screen regressions also passed. |
| Revised ordinary whole-source hook | 475 named tests passed: App213/530cases, Core70, tooling165, monitor27. Treeac77f5d5d8bc2b7a6953018d8b51cdfb751d33b6; pins unchanged, zero failures/skips/xcresult runtime warnings. Identical tree transplanted onto canonical v1.4.12 main61a09d518b85385ec4b7217c489fbdedc55da611. |
| Independent whole-branch review | One fresh-context A1–A8 review found no Critical, one Important stale cross-screen completion and one Minor fixture-input precision issue. All five Review Focus conditions and every declined boundary were adjudicated. |
| Important I1 behavioral RED | Twelve actual Show names executed; only the new newer-hide regression failed, with four issues: reopening, state reset, preference reload and extra show. Exit65; source/pins unchanged. An earlier fixture compilation failure is excluded. |
| Important I1 affected GREEN | 33 names/41cases across the four affected suites passed after request invalidation. Zero failures/skips/xcresult runtime warnings; source/pins unchanged. Tests execute the actual stale callback and retain the real default delayed-path regression. |
| Candidate metadata | Four marketing versions1.4.13, four build numbers20 and README badge synchronized. Readiness records the actual scoped decisions below; final ordinary hook and delivery remain separate. |

The final Show suite contributes twelve named tests and nineteen parameterized cases. Focused suites overlap whole-product verification and must not be summed as unique coverage. An initial single-function selector ran zero tests and is explicitly excluded from regression acceptance; the corrected suite ran the failure before its fix.

The first expanded fixture attempt failed to compile due to incomplete PreferencesClient initialization; it is not counted as behavioral RED. Corrected fixtures inject complete relevant dependency behavior, fixed time, `.notDetermined` authorization and inert content. Unexpected status rendering, permission requests or event fetches record test failures. No real status item or production calendar/preferences are exercised.

The native editor now sits beside its hosting view in a common NSView parent, avoiding unsupported subview insertion into NSHostingView. Existing Sparkle/linkd/activation diagnostics remain separately retained; zero xcresult runtime warnings does not mean no raw system diagnostic ever appeared.

## Acceptance boundaries

- Real owned offscreen CalendarPanel, actual AppIntent execution and real delegate callback invocation are verified at fixture scope.
- Production route registration is behind guarded status setup; the startup fixture verifies no registration/presentation under the actual test guard.
- Visible state and hook invariants, hidden reset/allocation, valid/invalid reanchoring, pin/editor preservation and unchanged toggle/cross-screen behavior are covered.
- Actual system AppIntent delivery, SwiftUI callback forwarding, signed Finder reopening, duplicate Shortcuts registration identity, Spaces/display changes and user focus restoration remain native-open.
- CUA successfully selected/opened `/Applications/Glimpse.app` through Finder, but subsequent Glimpse UI reading timed out. Shortcuts completions without an observed calendar remain unaccepted.
- Cold Finder launch versus login launch is outside this slice. Cold intent ordering may report not-ready and needs actual native verification.
- Latest independently verified public/installed app is v1.4.12/build19. PR18 update guidance merged through ordinary protected integration as61a09d518b85385ec4b7217c489fbdedc55da611; exact-source Release41474446148/1, public signing/notarization/Gatekeeper/Sparkle verification and recoverable official installation/launch passed.
- Original other-device crash is unexplained; actual restart is user-deferred; performance/endurance success has not been established.

## Readiness and delivery

| Role | Actual scoped decision |
| --- | --- |
| Product — Lead acting PM | Passed: explicit Show and already-running reopening address failed delivery without changing quiet login policy. Missing routing/geometry reports failure. Original crash, restart and performance outcomes remain open. |
| UX — Lead against accepted design | Passed: repeated Show preserves selected date, Preferences, pin and native editor; hidden reopening retains established reset behavior. Latest open/close wins across delayed display movement. Signed system dispatch and physical focus remain unaccepted. |
| Code — independent review adjudicated by Lead | Passed with I1 fixed by executed behavioral RED→GREEN and source inspection of request creation/invalidation/guard. No unresolved Critical/Important finding. Minor M1 is deferred: the NaN integration fixture also uses invalid visible bounds; pure geometry tests independently cover malformed anchors. No second review or claim that reviewer reviewed later source. |
| QA — Lead against retained receipts | Passed at source/owned-fixture scope: revised whole gate475 and subsequent affected gate33/41, unchanged dependency locks, actual intent/delegate/panel/editor execution and retained negative results. Final staged-source hook is mandatory before integration; hosted/main/artifact/installed-native boundaries require their own evidence. |

All review scope rulings remain explicit: retain quiet cold/login policy (D1), existing occluded toggle semantics (D2), existing hide-notification deltas (D3), unresolved crash/restart/endurance outcomes (D4), and separately scoped AI/update transport/event/keyboard work (D5). Their cost is that those behaviors and outcomes remain open, not implicitly accepted by this slice.

Source/fixture success does not establish signed installation or native navigation. Final gate and delivery receipts are retained outside tracked source, preserving exact-source identity without claiming future outcomes.

Use ordinary protected integration with current canonical admission, exact head/base/checks and current main/run observations. Preserve all recoverable official-app installation evidence and the existing sensitive-access/restart boundaries.
