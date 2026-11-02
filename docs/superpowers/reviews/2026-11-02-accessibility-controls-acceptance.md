# Accessibility control names and targets: scoped prepublication evidence

Candidate: **1.4.11 / build 18**. Base:
`f88197ba9bf68a088f6c4b9c77984024086d07d4`.

Product, UX and focused QA pass at the source/owned-fixture scope described below.
Independent A1–A8 source review is **approved**, with zero Critical, Important
or Minor findings. Code readiness records that scoped source verdict.
Whole staged-source quality, protected integration, terminal exact-main delivery,
public signed artifacts and installed native checks remain separate gates. The
current verified public and installed distribution is v1.4.10/build 17.

This is A11Y-01a under the [accepted design](../specs/2026-11-02-accessibility-controls-design.md)
and [implementation plan](../plans/2026-11-02-accessibility-controls.md).
It does not close A11Y-01b or the broader reliability goal.

## Implemented behavior

Four native controls have meaningful hidden titles: Filled background, AI date
search, Week starts on and AI provider. Native switch and selected-option values
are preserved. Five display pills expose expanded names and On/Off values; each
press changes only its corresponding setting and sends one menu-bar refresh.
Provider selection survives turning AI search off and on.

Three header and five footer actions have disjoint 28-point targets around their
existing glyphs. The rows reserve only the legacy scrollbar width exceeding the
existing 16-point padding, after native geometry and pointer tests exposed a
one-point scrollbar overlap. Today keeps its original color and disabled
predicate. Existing actions, animations and footer ordering are preserved.

Close date search has a named 24-point target and describes clearing the query
and closing search. Dismissal clears query/error and exits editing, keeps the
panel open, and never submits or deactivates panel input. Processing retains its
progress view without a dismiss/cancel action. Actual accessibility observations
showed the parent search label overriding the close label; the label now belongs
to the actual editor and collapsed prompt, with the original parent gesture.

The shared rows are the actual production views. Existing stores, state, focus
activation delay, AI task/submission, input/scroll monitors, pin, Quit confirmation
and external Calendar handoff remain in their original owners. Root/body widths
remain 316/300 points; date-cell and pill geometry are unchanged. No Core,
renderer, updater, diagnostics or permission behavior changes.

## Focused verification

Evidence root:
`/Volumes/xHome/Github/Glimpse/build/validation/accessibility-implementation.xeeb2lu6`.
Complete command/exit logs, source and pin receipts, xcresults, summaries and
frozen RED/GREEN source are retained there.

| Contract | Actual evidence |
| --- | --- |
| Preference names/values, pill actions, provider visibility and isolated effects | Original semantic RED reached wrong names/values. Final `preferences-native-no-warmup`: **5 named tests / 15 cases**, including both native picker selections. Unchanged Core preferences regressions previously passed 17 names. |
| Header/footer targets, real point actions, scrollbar clearance and preserved boundaries | Actual small-target and scrollbar-overlap RED retained. Final `task2-final`: **74 names / 177 cases** across eight suites, including preferences, viewport, layout, geometry, input, scroll and shortcut regressions. |
| Date-search semantics, dismissal and constrained viewport | Actual name/help/size RED and observed parent-label override retained. Final `task3-final`: **6 names / 32 cases**, including direct AX/point activation and legacy/overlay viewport checks. |

These runs overlap; counts must not be summed. Each accepted run reports zero
failures, skips and xcresult runtime warnings, with unchanged source/pins during
the run. Focused runs used build 17 before metadata synchronization; app and test
behavior bytes are preserved while candidate metadata moves to build 18. The
ordinary final hook must verify the complete staged candidate.

Fixtures use per-test stores, memory-only dependency receipts, disposable hotkey
defaults, local notifications, synthetic input and offscreen non-key/main windows.
No production defaults, Carbon registration, EventKit/TCC, AI, native updater,
browser, Calendar, About or Quit action is invoked.

Native picker selection uses the actual owned popup's AX press and public
NSMenu tracking notifications. The full option sequence establishes ownership;
one native item action is dispatched and only that captured menu is canceled.
The selected AX value, reducer state, exact once-only save and notification
counts must agree. No direct store write substitutes for selection.

The earlier inaccessible-menu/timeout gap remains as historical evidence and now
links the narrower passing fixture resolution. An extra picker-local AXWindows
read produced a caught AppKit `NSAccessibilityAttributeValueContainer length`
exception before menu capture/action. Removing only that redundant read preserved
all assertions and produced no recorded exception in the comparison. Its internal
mechanism, production effect and harmlessness are unproven. Independent raw-log
review also found one occurrence in each accepted `task2-final` (line 682) and
`task3-final` (line 402) run. The narrower preference comparison does not explain
those occurrences. Viewport fixtures keep their necessary own-process tree read;
full-quality logs must be checked for recurrence. Empty xcresult runtime-warning
arrays do not establish exception-free logs. Existing OS `linkd.autoShortcut`
diagnostics and Xcode's destination-selection warning are recorded separately.

## Independent source acceptance

The complete frozen candidate tree
`1455d791788a8d2cd35ecc43aa5078da58b4bf7b` was independently reviewed against
the accepted design, plan, A1–A8 checklist, all five review-focus contracts,
owner rulings and raw evidence. All 175 source hashes and all 15 changed/new
paths matched the complete net diff. No required source fix or deferred Minor
was identified; root accepted that grading after checking the source identity
and the newly reported raw-log occurrences.

External immutable records under the evidence root:

- `final-review/report.md`, SHA-256
  `a7b646a42396087a94a56ed37be422da7d356e06571f68a85251ac661231cb7a`.
- `final-review/verdict.json`, SHA-256
  `7da4522d4603661a5b959bb80dafec6225fef83db99553ffd2c5759f687258ea`.

Production behavior bytes remain those reviewed. Scoped records and the bounded
test-only correction below follow the review. The ordinary final hook must
verify the complete staged candidate including those changes.

The review explicitly leaves the following boundaries open: native date default
activation and keyboard focus; VoiceOver, macOS 14 and Intel; signed panel
input/lifecycle and physical reachability; external About/Calendar/Quit,
login-registration and live EventKit workflows; the exception's cause/impact;
external AI availability/privacy and new recovery/cancellation behavior;
actual Sparkle interactions and candidate delivery; unattended startup,
historical crash, endurance and measured production performance.

Filled background is checked for native name/role/true value but not independently
pressed by this fixture suite. Viewport tests preserve seeded preference values;
they do not prove persistence after new edits across signed close/reopen.
Omitted planned parent/AX-hit-test helper selectors do not supply another result:
actual geometry and per-point action receipts establish the claimed pointer
boundary without unused helper APIs.

## Combined-quality correction after source review

The first ordinary staged-source hook failed with four initial fixture settle
timeouts: Preferences native titles, header/footer actions, date-search dismissal
and date-search viewport. Its app run reached 183 names/359 cases, with four
failed names/cases and no skips; Core did not run because the app gate failed.
No commit was created. Source, stage and pins were unchanged during that run.

The helper started a one-second deadline before eight mandatory main-actor layout
passes. Concurrent suites could consume that budget before warm-up finished even
when genuine controls were ready. A deterministic owned-executor contention
characterization reproduced a timeout on a ready native button after 1.173
seconds; the never-ready condition test passed. Complete RED source and results
are retained in `settle-contention-red-source` and `settle-contention-red.xcresult`.

The author corrected only the test host: eight finite layout passes complete
first, then a missing condition receives its one-second deadline. Native nodes,
point delivery, ownership and all functional assertions remain intact. The
characterization verifies a real button press after contention; the second test
still requires a never-ready condition to time out. Queue contention can extend
warm-up wall time; outer Xcode/owned-process deadlines remain.

The corrective `settle-contention-green` run passed **29 named tests / 84 cases**
across host settling, settings, icon/search/viewport, About and panel-layout
suites, with zero failures/skips/xcresult warnings and unchanged source/pins.
One caught container-length exception remains in its raw log, as in the first
whole run; the helper correction makes no exception-resolution claim.
Production and all other test behavior bytes still match the independent review.
This bounded author correction has RED/GREEN evidence and was not independently
re-reviewed. The next ordinary hook must establish complete-candidate quality.

## Remaining requirements and limits

- Ordinary whole quality, protected delivery, public signing/notarization,
  Gatekeeper/Sparkle verification and official installation/launch.
- macOS 14, Intel and VoiceOver execution; current fixture evidence comes from
  one arm64 macOS 27.0.1 host.
- Signed panel keyboard/editing, shortcut recording, hide/reopen, pin and physical
  constrained-screen reachability checks. An owned host is not signed lifecycle
  or assistive-technology acceptance.
- A11Y-01b date default activation, ordinary keyboard traversal and visible focus.
- Earlier installed screen-fit and real updater interactions remain separately open.

The original other-Mac crash remains unexplained; the user deferred the real
restart check. Read-only process presence and passing tests do not establish
unattended startup, zero critical crashes, endurance or performance improvement.
