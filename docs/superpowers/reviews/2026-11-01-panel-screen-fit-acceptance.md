# Panel screen fit: scoped prepublication acceptance

Target: **1.4.9 / build 16**. Base:
`302a260e736f8d9cdc14684b1f1281f7768588fa`.

Product, UX, task-scoped code review and independent QA have passed for the
accepted source under the
[binding design](../specs/2026-11-01-panel-screen-fit-design.md), including the
two-file indicator correction. The four passed checks in
`.github/release-readiness.json` refer to this scoped prepublication acceptance.
Fresh metadata and whole-branch A1–A8 review, whole exact-source quality,
ordinary protected delivery, exact-main Release/Recovery, public signed
artifacts and installed native acceptance remain required. Latest accepted
production remains v1.4.8/build 15; this document does not close the wider
stability goal.

## Confirmed regression and accepted behavior

Released placement arithmetic could request a panel below the visible screen.
For status `(1000,876,100,24)`, visible frame `(0,48,1440,828)` and desired
height 900, the extracted prior policy returned `(892,42,316,828)`. The accepted
policy returns `(892,58,316,812)`. This is executable numeric regression evidence,
not a recorded installed panel frame.

`PanelGeometry` keeps width 316, body width 300, caret height 12, menu gap 6,
side/bottom margins 10 and caret inset 16. It derives the available height from
the status anchor and visible bottom, clamps centered horizontal placement and
caret offset, and rejects nonfinite or nonpositive geometry, visible widths
below 336 and total height budgets below 13. `CalendarPanel` uses that policy
for initial placement, resize and anchor refresh. Finite measurement guards,
four-component frame comparison below 0.5 points and the existing 0.05-second
resize debounce bound layout feedback.

The persistent `PanelViewport` measures the natural 300-point padded child
independently of its constrained height. Preferences, header, AI input/errors,
calendar, selected-day events and recovery states, and footer remain in that
child. Overflow enables vertical scrolling; fitting content stays compact.
The 12-point caret and material/rounded viewport boundary stay stationary.
Preference transitions and explicit reopen reset to the top; AI activation
requests its input anchor. Screen, wake and status-width refresh update
placement without reopening or resetting selection.

`CalendarScrollRouter` gives a phased gesture one owner through momentum.
Overflow and ineligible contexts pass to the viewport; calendar-owned input
is consumed, including after navigation or later suppression. Hidden/foreign
events reset and pass. Eligible discrete input retains the strict magnitude
threshold above 5 and contribution cap of ±1.5. Existing buttons, keyboard
handling, pin, text activation/restoration and explicit show/hide hooks remain.

The initial Task2 native indicator fixture omitted the production rounded
clip. Independent UX review correctly failed that boundary: the native thumb
extended beyond the 300-point body. The amended production viewport uses a
public macOS 14 indicator-only trailing margin from the native legacy width
metric and leading alignment. It preserves document width and the persistent
subtree without setting production scroller style or changing global settings.

## Independent acceptance and retained evidence

| Role | Verdict and scope |
| --- | --- |
| Task1 spec/code reviewer | Approved pure geometry and wheel policies; no critical, important or minor finding. Native integration was outside that task. |
| Task2 spec/code reviewer | Approved measured viewport, native integration and lifecycle/input wiring; no critical or important finding. Existing activation deprecation and AppIntents startup noise remain disclosed. |
| Product/UX/QA reviewer | Product PASS retained; final revision-bound UX PASS and QA PASS for amended source/controlled-host evidence. The earlier indicator FAIL remains historical evidence for the original bytes. |
| Fix-only spec/code/UX/QA reviewer | Finding ADDRESSED; scoped spec/code/UX/QA PASS, no remaining fix finding. Independently read all four actual fix bundles and verified frozen/run-start/current identities. |

The ignored authoring workspace is
`.superpowers/sdd/2026-11-01-panel-screen-fit/`. The controller's durable
accepted records are retained at
`/Volumes/xHome/Github/Glimpse/build/validation/screen-fit-delivery.qojis70m/accepted-prepublication-records`.
All twelve original Task1/Task2 reports, reviews and manifests, amended
acceptance/review records and Task3 metadata receipts were copied with identical
SHA-256 identities, recorded in `accepted-prepublication-record-retention.json`
in the parent delivery directory and independently verified by the Task3 reviewer.
Record retention is complete; authoring-workspace cleanup and later gates remain
pending.

Actual logs, command/exit receipts, xcresults, source snapshots and manifests:

| Evidence root | Recorded final result |
| --- | --- |
| `/Volumes/xHome/Github/Glimpse/build/validation/screen-fit-task1.ueuiixer` | `final-green.xcresult`: exit 0; 34 named tests / 112 device or parameter runs passed. |
| `/Volumes/xHome/Github/Glimpse/build/validation/screen-fit-task2.js4c9bh2` | Original `final-green.xcresult`: exit 0; 54 named tests / 132 runs passed, including Task1's 34 names. |
| `/Volumes/xHome/Github/Glimpse/build/validation/screen-fit-task2-fix1.faoc3q69` | Amended `final-green.xcresult`: exit 0; 8 named layout tests / 9 runs passed, including fresh legacy/overlay arguments. |

All three final results report zero failures, skips, expected failures and
xcresult runtime warnings. Counts overlap and must not be added into a distinct
test total. The original 54/132 run describes its original revision; the amended
8/9 layout run covers the two-file correction and retained layout regressions.
No amended whole-suite run or new whole-source quality run is claimed here.
Independent QA read the actual Task1/Task2 summaries and Task2 test tree, then
the fix summaries; reviewers did not rerun those suites.

Behavioral RED is retained separately from compile and infrastructure failures.
Task1's actual policy RED had 26 failed names; its external startup cancellation
executed no real tests. Task2's compiled assertion RED had 8 failed names.
The fix's `indicator-production-red.xcresult` failed one name in two style runs
on thumb containment; `document-containment-red.xcresult` failed one name in two
runs on document minX −0.5 versus required 8. The passing one-name/two-run inset
hypothesis was a fixture experiment, not final production acceptance.

Hidden hosting fixtures observed natural 900, viewport 800 and root 316×812,
and wrapped natural height 48→1632→48 with root 316×60→316×312→316×60.
Child appearance and model draft survive reflow; bounded repeated fitting and
unchanged-frame passes establish measured convergence. The real hidden panel
applies `(892,58,316,812)`, reanchors to x1092, shrinks/grows with measurement
and immediately restores height when its budget expands. These fixtures use
generic content and injected dependencies, never show or activate their windows.

The amended fixture includes the production stationary material and rounded
clip. Fix final log lines 430–434 record document x8…308, legacy knob x294…305
and overlay knob x299…305 at both scroll ends. Assertions establish the full
knob/body intersection, rounded-mask corners/center, native NSScroller hit
geometry, clip y0→100 and floatValue 0→1. This closes the measured clipping and
horizontal document alignment finding for the amended bytes.

Tests ran on arm64 macOS 27.0.1 with Xcode 27.0; the deployment floor is 14.0.
The original covering build logs retain the existing
`activateIgnoringOtherApps` deprecation, and earlier full compilations retain
the Sparkle nil-coalescing warning. The amended incremental GREEN has no
compiler-warning lines. Known AppIntents/linkd startup IPC errors remain;
zero xcresult runtime warnings does not mean diagnostic-free startup output.

## Frozen source and compatibility

| Accepted file | SHA-256 |
| --- | --- |
| `Glimpse/PanelGeometry.swift` | `5ef6d8aa06d66958ec113aee97e162aaf9740d1ec6a2fea7ed6c2ceec08a3426` |
| `Glimpse/CalendarScrollRouter.swift` | `b58c78300ecf663558258a1a4c3ece7ed312a4bc3fe2c1ddc7572a508547fe57` |
| `Glimpse/PanelLayoutState.swift` | `6f70b42a8b72d801f42ee53a1d01b7859f19fc250bdaebfc57188411246d5ea0` |
| `Glimpse/PanelViewport.swift` | `c9474e2f9d2c10e84e013cad1bbf2a37ef7bd75c0e5add146c0bb235e7be0929` |
| `Glimpse/CalendarPanel.swift` | `68a161018496d0cec72546061b201d0e5e521994c7c612e3217088e8265d8daf` |
| `Glimpse/CalendarStatusItem.swift` | `bc310108274f4b0872b0042afaf980c38db33807fe133f956d5d85a942b8294b` |
| `Glimpse/CalendarPopoverView.swift` | `746564b131c433c3ca7b34fca9de2ea937b5bcc6819c634b44c44d5b2f56db92` |
| `GlimpseTests/PanelGeometryTests.swift` | `b91171ee52c62b0499f0e43f5a0578bbf05447c3489749ff0bd65c30954c2758` |
| `GlimpseTests/CalendarScrollRouterTests.swift` | `37aeeac103c6a95fe81bdaca56bd0cd85c42991e0210d2ca4cac1d126858d94e` |
| `GlimpseTests/PanelLayoutTests.swift` | `74816b7b171bf4967197a5e2aea57262c3f67dee0f5e29e3e6d40f33e254a54b` |
| `GlimpseTests/CalendarInputTests.swift` | `681eceb02d45fb6fa484af22f82cbf8021069d88d43823ed5dff65018b05bd0e` |

Task1's review manifest and the amended Task2 review manifest bind these
identities. The accepted premetadata project hash is
`089f7fea8247bb8d07326d1485c842bb9dd61364b0d49c02f21fc2ea9d9084bf`;
Task3 changes only four marketing versions to 1.4.9 and four build numbers to 16,
preserving all 28 added source/test registration lines. The README badge and
readiness version/build/evidence are synchronized.

Both lockfiles retain all 15 matching immutable pins and their base hashes:
Core `ffeaf49b65ce3dd7b6a95db730357b03546883dc7fd20ba8e05cdb9aed529e6d`,
app `5a5b283530b0e02190ce66eb50ac5817f037e0d2ac7ab99af10cdc6e931e54b7`.
The whole `GlimpseApp.swift` hash remains
`7092c3b3bfd80b1c5ac8631f5daf9131d3c51285e5e4aea4a78de405d60e83e4`;
its existing `XCTestBundlePath` guard bypasses production status/Sparkle setup
in app tests. macOS 14, Swift 6 complete concurrency, entitlements, signing
policy, feed/key and production permission/persistence behavior are preserved.

## Remaining gates and limits

After protected delivery and verified public publication, installed acceptance
must exercise real expanded preferences and lower event/error/retry/footer
controls, AI scroll/focus/editing, shortcut recording during reflow, compact
month navigation versus overflow scrolling with physical phased momentum and
discrete wheel input, pin/reopen/top reset, caret/material/normal indicators,
display/wake/status-width changes and settled CPU/memory responsiveness.
Generic hidden fixtures do not establish actual controls, pointer dragging,
rendered pixels, VoiceOver/keyboard scroll reachability or signed native
permission behavior.

Physical small/scaled/multiple displays, side/bottom Dock configurations,
macOS 14 execution and Intel were not separately exercised. Numeric screen
rectangles and owned legacy/overlay styles are controlled fixtures, not
physical configuration or real user-setting validation. Bounded convergence
does not establish indefinite absence of redraw loops or future crashes.

The other-Mac termination remains unexplained; real reboot/login testing is
user-deferred, and broader endurance/live EventKit behavior remains open.
Process monitoring proves neither menu-item visibility nor unattended startup.
No machine restart/logout, production permission/data/configuration change,
installation or native interaction is established by this source acceptance.
Cask retirement and CD-01 admission-boundary correction remain separate
iterations; existing release checks remain in force.
