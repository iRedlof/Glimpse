# Calendar keyboard acceptance

2026-11-02. Candidate **v1.4.16/build23**, branch `codex/keyboard-focus`,
based on verified v1.4.15 source `d36661d6b78a7236b0aedfc7e05237516000c9f1`.

**Bounded product, UX, code and QA acceptance passed. Mandatory exact staged-source
quality, protected integration, signed public delivery and installed interaction
remain pending. This is not whole-goal completion.**

The calendar now has one stable grid Tab stop, a logical focused date separate
from selection, arrow movement by one day or one week, and Return/Space activation.
The focused date has an inset outline, stays visible in the reused viewport, and
appears in the calendar group's accessible label. All 42 existing native date
buttons retain their names, actions and selected traits. Fixed header/search
controls use their actual local focus callbacks; native editor submission remains
exclusive. Held activation consumes repeats, and eligible disabled Today activation
is consumed without performing an action.

Existing browse shortcuts require a positively observed window-default responder.
Hidden reopen resets owned bindings before presentation, then verifies native
default focus after normal key presentation. Repeated visible Show preserves the
current responder, draft and logical date. No new monitor, focus timer, custom Tab
traversal or global keyboard posting is introduced.

[Design](../specs/2026-11-02-calendar-keyboard-ownership-design.md) and
[plan](../plans/2026-11-02-calendar-keyboard-ownership.md) record architecture,
historical failures and current results. External evidence is retained under
`build/validation/keyboard-ownership-implementation.7t6hl4w0/` and
`build/validation/diagnostics-fixture-implementation.yucljzsb/`.

| Boundary | Accepted evidence |
| --- | --- |
| Routing and disabled activation | The whole pure router plus actual Today correction passed 14 methods/34 cases; the pure router contributes 13 methods/33 cases. Modified/editor/foreign/nonkey/suppressed input still yields. |
| Cleaned real-root ownership | All 14 named methods/16 execution cases passed, zero failures/skips/expected failures; native exit 0 without wrapper timeout. Actual handler/action receipts match owned windows and current events. |
| Focus and constrained viewport | Both 312/812 cases retain all 42 date buttons, exact unique focused-date label from a successful public accessibility query, known focused date bounds, unchanged selection/no movement action, and reverse/month/forward continuation. |
| Durable artifacts | The integrated collector retained six required PNGs. The lead independently compared every source/destination digest, all 84 frozen source/tool inputs, both pins, HEAD and fresh owned-process absence. |
| Report-parser correction | Original checker rejected one legitimate runtime-warning child. Test-first correction admits only narrowly validated warning leaves under passed methods, counts genuine Arguments only, and retains warnings/input hashes/four command exits. Exact saved native metadata is accepted as 14/16 without a native retry. |
| Parser regressions | Original behavioral RED is preserved. Original and normalized final runs each passed 13 focused offline tests, covering warning retention, malformed/unknown children, missing/failed/skipped/duplicate arguments, typed empty-list rules, command failures and legacy exact-source archives. |
| Fixture hosting cleanup | Two unchanged-helper regressions failed their hosting-release assertion. Minimal test-helper content detachment then passed both and 30 original consumers: 32 methods/137 cases. Root integrated the helpers and project registrations. Whole integrated quality remains required. |
| Independent review | Frozen 30-path source review has 18 rulings; product/helper/collector accepted. The known parser finding and stale-documentation finding were resolved by bounded independent re-review. Final checker review has 12 explicit rulings and no actionable finding. |

The native result retains one user-interactive-to-Default QoS runtime warning at
the synthetic editor fixture's nextEvent call. Raw compiler/linkd and historical
window warnings remain recorded. This is not warning-free acceptance or evidence
of a production performance/crash cause. The public regression fixture uses
synthetic machine/source identities; original raw metadata and its exact hashes
remain preserved locally.

| Role | Bounded decision |
| --- | --- |
| Product — Lead | Passed: keyboard date/control access preserves existing date actions and successful browse behavior. |
| UX — Lead | Passed at owned native fixture scope: visible focus, focused-date label, constrained viewport and traversal continuity. Physical keyboard and VoiceOver remain separate. |
| Code — independent reviewer | Passed: full source and exact parser/fixture correction reviewed; all recorded findings resolved. |
| QA — Lead | Passed at focused scope: native 14/16, retained six PNGs, helper 32/137 and parser 13/13 evidence accepted. Ordinary exact staged-source and hosted quality remain mandatory. |

Latest verified public/installed distribution is v1.4.15/build22. This candidate
has not been installed. Physical keyboard/autorepeat, VoiceOver announcements,
macOS 14/other hardware, signed interaction, workload comparisons and longer
endurance remain open. The original other-machine crash is unexplained and the
real restart check is user-deferred. This slice does not establish crash freedom,
optimized production performance or reliable launch after a real reboot.
