# Separate Settings window candidate acceptance

2026-11-03 UTC. Candidate **v1.4.20/build27**, branch
`codex/settings-window-next`, based on verified v1.4.19 source
`6f95bd56e8fa3499cb95843229a619b02ee4da24`.

**Product/UX design and all five focused implementation tasks are accepted.
The final whole-source/visual review and its single settled-switch
capture correction are accepted with no open critical/important findings.
At this boundary, exact staged-source full quality, protected integration
and signed public/installed delivery are pending; the candidate is unshipped.**

Opening settings previously expanded the calendar and moved its content.
Gear and the standard ⌘, command now open one retained native Settings
window. Its four sections are General, Menu bar, Calendar, and AI date
search. The selected section is retained, detail content scrolls separately,
and changes apply through the existing setters. No new preferences,
defaults, dependencies or Save step are introduced.

A pinned calendar retains its frame, scroll, month, selection and pin state.
An unpinned calendar explicitly hides, including any editor. Internal
handoff cancels stale editor/cross-screen callbacks and abandons the old
external-app restoration lease. Closing Settings does not reopen or reset
the calendar. Ordinary subsequent calendar reopening retains its Today
reset behavior.

Settings uses a normal window level, 600×480-point content, a 164-point
sidebar and 24-point detail margins. Placement includes native titlebar
height, respects screen bounds/negative origins and avoids a pinned
calendar where space permits. Constrained screens reduce the allowed
minimum size; the detail remains scrollable.

| Boundary | Focused evidence |
| --- | --- |
| Product/UX | Independent PM, UX and builder comparison selected a separate retained window over calendar expansion/replacement. The interactive mockup passed 36 checks. |
| Shortcut owner | Recording requires the exact visible/key Settings window and exact event owner; ⌘, is reserved. Native cancellation/rollback regressions pass. |
| Lifecycle and refresh | Reused Settings explicitly refreshes system login status while preserving pending operations/errors. Close, order-out, key loss, app deactivation and leaving General cancel recording. |
| Calendar handoff | Real gear/menu dispatch, pinned/unpinned state, stale editor/cross-screen callbacks and internal activation boundaries pass. |
| AI bridge | Real Settings setters synchronously invalidate the existing calendar request owner; late cancellation-ignoring providers cannot commit. Existing complete AI suite passes 8 methods/17 cases. |
| Native keyboard | Complete isolated suite passes 28 methods/46 cases, including Tab/Shift-Tab, Space/Return, popup Escape, recorder Escape, close button and exact ⌘W. No failures/skips. |
| Nonkey regressions | 43 methods/86 cases pass across preferences, geometry, calendar accessibility/viewport and renderer suites. |
| Appearance | Same mounted preview passes light/dark/light identity, dimensions and glyph contrast. The dark preview defect was reproduced before its color-scheme correction. |
| Visual captures | All 38 retained images were independently inspected. Four early AI-off captures were rejected for unfinished native animation; the bounded owned-toggle correction passes all four cases, retains 24 new images, and its four settled off states plus on peers are independently accepted. Originals remain preserved. |
| Final source review | Whole branch A1–A8 review found no production-source blocker. The sole important visual-evidence finding is closed by a separately sealed focused correction. |
| Tooling | 10 focused current-manifest/historical-warning tests pass. Current required keyboard graph is 28/46; saved historical graph contracts remain separate. |

Raw failures, source snapshots, terminal exits, original xcresults, strict
summary/method graphs and copied captures are retained outside tracked
source under
`build/validation/diagnostics-fixture-implementation.yucljzsb/settings-window-execution.qjw_06kc/`.
The focused boundary is `task5-root-GREEN-acceptance.json`.
All 79 methods/149 focused cases pass at that bound source.
The explicit sidebar accessibility label and synchronized version/build were
also present in the subsequent four-case native run. The corrected capture
fixture, final documents and complete source still require the normal full
staged-source gate.

The existing native editor QoS diagnostic remains retained. Physical
VoiceOver, macOS14/Intel, live private EventKit/cloud interaction, longer
endurance and actual reboot/login remain separate validation. The user
deferred the reboot. This slice does not establish the cause of the
original other-Mac crash or guarantee zero unattended crashes.
Latest verified public/installed app remains v1.4.19/build26.

The independent whole review is retained in
`settings-window-final-whole-review.kihctzdb/`; its output seal is
`2e6f4a7034d49b0ff863dd6733b7b5409c4bba4ee91ab5c3b8450b31682d1e12`.
The focused I1 closure is retained in
`settings-window-i1-focused-adjudication.gjblu7qq/`; its seal is
`4cc971fbb90a222efd4fc5cdad96173d9d0d2db567eecda63ad09573d9c75c39`.
The full mandatory keyboard manifest remains 28 methods/46 cases. The
one-method/four-case selection is only the focused capture correction;
it does not replace the mandatory full suite.
