# Calmer calendar grid candidate acceptance

2026-11-03 UTC. Candidate **v1.4.19/build26**, branch
`codex/calendar-grid-next`, based on verified v1.4.18 source
`19f56c36e3efab8ff2bac6b30a633f4631fa57ff`.

**Product, UX, focused QA and bounded independent source checks passed at
these boundaries. Complete candidate review, exact staged-source full quality,
protected integration and signed public/installed delivery remain pending.
This candidate is unshipped.**

The calendar uses lighter workday shading and an outer frame that recedes
behind the dates. Adjacent-month dates and week numbers use the native
secondary foreground. Today/selection/focus precedence, the current-month
contour, 42 date buttons and all native target geometry stay intact. The
visible Today button from v1.4.18 is retained.

Only AppDesign tokens, calendar view styling and owned visual observations
in the existing keyboard fixture change. Shared agenda borders, event
queries, panel geometry, editor/keyboard routing, settings defaults,
permissions, startup, shortcuts, AI and updater behavior are unchanged.

| Boundary | Accepted evidence |
| --- | --- |
| Product and UX | Accepted calmer-grid design reduces decorative emphasis without adding controls or changing date behavior. All 28 combined captures were inspected at uniform native point scale. |
| Combined source | Preserved grid A1–A8 review accepted its three-file source. Independent Today/grid reconciliation reconstructed the complete three-file union from the common base; all actual bytes matched, with zero reconciliation findings. The canonical Today action-aware target helpers and every original assertion remain. |
| Keyboard/root behavior | Exact combined CalendarKeyboardOwnershipTests passed 14 methods/16 cases, with zero failures or skips and a strict manifest/graph receipt. Eight Today roots, ten grid roots, four focus viewports and six original viewport/date crops were retained with matching hashes. |
| Focused regressions | Exact combined date accessibility, persistent viewport, AppDesign and native icon-target suites passed 18 methods/40 executed cases, with no failures or skips. This includes existing localized heading/edge-action coverage. |
| Appearance and configuration | Actual owned Aqua/DarkAqua roots cover Today and other selections, no selection, an away month, and Monday-start/weekend-workday settings. Appearance is confined to owned panels; settings and capped-viewport appearance are restored. No production preferences or permissions change. |
| Capped viewports | Both 312/812 native viewports retain reachable logical focus, separate selection/focus contours and unchanged owned scroll/document behavior. |

Evidence stays outside tracked source under
`build/validation/diagnostics-fixture-implementation.yucljzsb/`.
Current combined execution is `ux-grid-canonical-integration.devjja8w/`,
including `root-combined-native-acceptance.json` and
`root-source-reconciliation-acceptance.json`. The independent reconciliation
packet is `ux-grid-today-reconciliation.rtyycmze/`; its runner-name correction
is retained separately in `ux-grid-today-reconciliation-erratum.ejqy0rpw/`.
Original grid source/native evidence remains immutable in
`ux-grid-source-review.vsiq84nr/` and `ux-grid-execution.9j1z15oe/`.

The focused source was checked before this version/readiness-only update;
all three changed Swift files remain byte-identical to that acceptance.
The ordinary exact-source full quality/commit gate remains mandatory.

The native editor QoS warning is retained. Increased contrast, physical
keyboard/VoiceOver, macOS14/Intel, live EventKit/cloud interaction and
longer endurance remain separate. This change does not explain the held
maintenance PR24 failures or original other-Mac crash. A real machine
restart is still user-deferred. Latest verified public/installed app is
v1.4.18/build25; agenda context/refresh and grouped settings are separate
follow-on candidates.
