# Diagnostics deadline fixture acceptance

2026-11-02. Candidate **v1.4.15/build22**, branch `codex/diagnostics-fixtures`,
based on verified v1.4.14 source
`db6fdc6b411b90a36287fcdd002330a0e2701971`.

**Status: focused implementation and review-fix behavioral verification accepted.
Independent whole-candidate review found one Important cancellation-teardown
gap and two Minor findings. The fixture fixes passed executable regressions and
the inventory wording is corrected. Focused independent re-review accepted
all three corrections with no new Critical, Important or Minor finding.
Integration remains closed. Mandatory staged-source quality, protected
integration and public delivery remain pending.**

The collector accepts two internal scheduling closures for worker submission
and deadline awaiting. Their production defaults remain the existing utility
queue and `Task.sleep`. Timer installation, timeout origin, synchronous reader,
cancellation delivery, exclusive ownership and cleanup are preserved. This
change makes deadline regressions testable without depending on the worker
winning a race against a short real timeout. It does not establish the cause
of the original CI ordering failure or the reported other-machine crash.

[Design](../specs/2026-11-02-diagnostics-fixtures-design.md) and
[plan](../plans/2026-11-02-diagnostics-fixtures.md) define the scope. Evidence is
retained under `build/validation/diagnostics-fixture-implementation.yucljzsb/`.

| Boundary | Observed result |
| --- | --- |
| Compile preparation | Initializer parameters were present but deliberately unwired. The preparatory production diff is retained; this was not unchanged-production RED. |
| Two excluded runs | Both external-storage test hosts stalled in the loader before connecting or executing tests. Disabling the debug dylib did not resolve that stall. No behavioral result is inferred. |
| Executable RED | The same frozen unwired source ran using local temporary DerivedData: 17 names/18 cases, 14 passed and four expected failures across three names. Missing deadline-arm/worker-capture acknowledgements caused explicit fixture failures. |
| Fixture correction | A second teardown drain handles work captured after the first cleanup snapshot. This assertion-preserving cleanup diff is recorded separately before production wiring. |
| Focused GREEN | Exit0, no wrapper timeout, 17 names/18 cases all passed, zero failures/skips/expected failures/xcresult runtime warnings. Source and both lockfiles were unchanged during the run. |
| Blocked provider and iterator | Real background read entry precedes controlled deadline release. Empty timed-out output is delivered before reader release; another collection is rejected until the full worker returns. Fresh collection succeeds without late output. |
| Deadline before queued work | The timeout arrives before captured work runs. The provider is never entered; ownership remains reserved until that work returns, then fresh collection succeeds. |
| Real default timer | A separate smoke test retains timeout0.2 and elapsed `<1s`; the recorded elapsed time was0.203699042s. |
| Failure cleanup | Reader and deadline gates are opened, request tasks settle and captured workers drain. Fixture watchdogs fail explicitly; GREEN contains no watchdog event. |
| Review-fix RED | Exit65 without wrapper timeout: 19 names/20 cases, 18 passed and two new cases failed. Cancellation ended teardown before a separately held actual provider exit, poisoned a subsequent completion observer, and completed captured work retained its collector. These were executable failures, not loader or compiler failures. |
| Review-fix GREEN | Exit0 without wrapper timeout: 19 names/20 cases all passed, zero failures/skips/expected failures/xcresult runtime warnings. Both regression bodies remained unchanged from RED. Production source and dependency pins were unchanged. |
| Cancellation-safe teardown | Producer completion is durable; each observer owns its cancellation and watchdog. An uncanceled bounded drain is joined by the canceled fixture caller. Recorded order and assertions show cleanup and a fresh observer pending until actual worker return, with each observer resumed once. |
| Captured-work release | Captured work is consumed and cleared before completion acknowledgement. The weak collector regression passed; this finding concerned the test fixture rather than an observed production leak. |
| Retained real timer bound | The review-fix run used the unchanged default timeout0.2 and elapsed `<1s` assertion; recorded elapsed time was0.207496041s. |
| Inventory correction | Native v1.4.14 evidence establishes discovery of42 date controls and sampled selection/deselection/outside-month/Today actions. It does not establish activation of every date control. |

The lead independently checked raw receipts, summary and terminal execution
nodes. Parameterized cases are counted once; Failure Message children do not
constitute execution cases. Earlier zero-test runs are excluded.
Review-fix raw receipts, source snapshots, expected failure mapping and event
traces are retained in `review-I1-M1.w7nsh0kz/`. The lead independently parsed
the execution nodes and checked both unchanged regression bodies, tested source
hashes, lockfiles and absence of the owned runner/test host.

Raw autoShortcut/linkd4097 diagnostics are retained. Xcode performed automatic
Launch Services registration despite the build setting requesting otherwise.
Neither observation establishes installed Shortcuts reliability or a crash
cause. No manual registry reset, production UI action, OSLog content access,
calendar permission or preference change was part of these tests.

| Role | Decision |
| --- | --- |
| Product — Lead | Passed at bounded scope: reliable deadline/ownership regressions protect diagnostics availability. No new user-facing workflow is claimed. |
| UX — Lead | Passed at source scope: diagnostics report and UI behavior remain unchanged. Installed interaction is a separate boundary. |
| Code — independent reviewer | Whole-candidate A1–A8 review at tree56ce069e525eeb43120127851fd0fe9db44f1840 found zero Critical, one Important and two Minor findings. Focused re-review at treecace175d0941af5bb9110dc2845bafbb39ebdcc9 resolved all three with no new findings. The lead accepted all eight declined delta boundaries; final quality and delivery remain required. |
| QA — Lead | Final focused19-name/20-case behavioral evidence accepted; full staged-source and hosted quality remain required. |

Latest public/installed distribution remains v1.4.14/build21, with accepted
exact-source Release41489239344/1, signed public verification, recoverable
installation and scoped native date actions. Subsequent autonomous native
About checks reported no newer update; diagnostics saved a970-byte report
through the native save panel and Show in Finder selected that exact file.
The report identifies installedv1.4.14/build21/PID17956, enabled startup and
registered hotkey, with no collection-error/deadline/busy marker. This is
installedv1.4.14 evidence; candidatev1.4.15 is not installed.
Ordinary keyboard traversal,
VoiceOver, macOS14/Intel, constrained displays, sleep/wake and longer endurance
remain open. The other-Mac crash is unexplained and the real restart check is
user-deferred. This slice does not close the whole stabilization goal.
