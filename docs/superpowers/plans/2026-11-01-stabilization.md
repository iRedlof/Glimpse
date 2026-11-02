# Glimpse stabilization implementation plan

> **For agentic workers:** Use the assigned specialist ownership; root integrates and verifies. Steps use checkbox syntax for tracking.

**Goal:** Deliver truthful startup UX, bounded diagnostics, safer preferences/input,
correct event dates, and verified continuous delivery.

**Architecture:** Preserve TCA reducers and dependency clients. Keep AppKit at the
application boundary. Release scripts validate exact source/artifact identities
before publication; runtime monitoring collects local evidence.

**Tech Stack:** Swift 6, Swift Testing, TCA, AppKit, ServiceManagement, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-01-stabilization-design.md`

## Global constraints

- macOS 14+, current Swift/TCA architecture, no new signing keys.
- No claims about the other Mac's crash or unperformed restart checks.
- No commits/pushes until the previous GitHub release is verified.
- No installed-app settings changes during isolated QA.

## Review focus

- Registration succeeds but macOS still requires approval.
- Large or stalled diagnostics output cannot freeze export.
- Malformed persisted values cannot trap on app launch or calendar rendering.
- Hidden panel and text editors retain normal keyboard behavior.
- A late event result cannot overwrite a more recent selected day.

## Task 1: Startup state — Developer

Files: LaunchAtLoginClient, PreferencesFeature, PreferencesView,
PreferencesFeatureTests.
Interface: `LaunchAtLoginClient.status() -> Status`, Sendable status raw value;
`setEnabled(Bool) async throws`; pending state guards concurrent operations.

- [x] Reproduce optimistic false→true state before actual system completion.
- [x] Cover enabled/approval/missing/failure/refresh and duplicate operations.
- [x] Implement authoritative status and recovery UI.
- [x] Run complete core and app suites (62 core; 57 app after the final save-flow change).

## Task 2: Diagnostics, preferences and input — Tech Lead

Files: DiagnosticsExport, AboutWindow, GlobalHotkey, PreferencesClient,
CalendarPopoverView, tests and Xcode project test membership.

- [x] Regress large log output and deadline, invalid weekday/hotkey values,
      hidden/wrong-window input and text arrows.
- [x] Collect subprocess output without pipe backpressure; report failures.
- [x] Validate loaded values and scope input before consuming events.
- [x] Run complete app/core suites and the isolated startup/closed-panel idle smoke test.
- [ ] Complete the native interaction matrix, including signed save-dialog permissions.

## Task 3: Selected-day event correctness — Developer/Tech Lead

Files: EventKitClient, CalendarFeature, CalendarPopoverView, CalendarFeatureTests.
Interface: selected local date query; response date or identity guards stale data.

- [x] Regress selected-day query, latest response, revoked permission and Today/AI.
- [x] Implement cancellable queries and honest loading/date labels.
- [x] Verify local-day intervals across DST; run complete suites.

## Task 4: Delivery and monitoring — DevOps/QA/Tech Lead

Files: workflows, release scripts, policy/readiness evidence, pinned lockfiles,
health sampling tool, release/QA documentation.

- [x] Audit prior release v1.4.3 against exact SHA and asset integrity.
- [x] Align the app/core dependency graph to the app's compiling graph.
- [x] Test CI/gate/verification/recovery against passing and failing fixtures (74 contracts).
- [x] Implement signed-artifact verification and ownership-scoped failed-publication withdrawal.
- [ ] Verify the first new signed publication through the hosted release workflow.
- [x] Install scoped commit/push hooks and establish quiet monitoring.
- [x] Record independent review, suite and bounded live QA evidence.
- [ ] Pass exact staged-tree quality checks and hosted checks before merging.
- [x] Bump all version/build locations before any user-facing push.

## Delivery ledger

Baseline source: `1eaae2643625f435c3a5b176b7f63b5de1ebcd21`.
App baseline: 42 passing tests. Core baseline failed to compile TCA 1.25.2 on
Xcode 27; synchronized lock graph uses TCA 1.26.1, matching passing app baseline.
Implementation branch: `codex/stability-ux`, isolated managed worktree.

Scoped product and UX source acceptance: `docs/product-acceptance.md` and
`docs/ux-acceptance.md`. Independent A1–A8 review: `docs/code-review.md`.
The review found and tracked dispatch/rerun/recovery gate defects before delivery.
Final app verification passed 57 tests in nine suites; core passed 62 in five.
Release tooling passed 74 contracts and monitoring passed 27 fixtures.
Bounded QA acceptance is recorded in `docs/qa-acceptance.md`; real restart,
native interaction and signed Powerbox verification remain open.

The first real staged-hook attempt exposed inherited Git repository variables in
temporary test repositories before compilation. The commit was rejected.
The hook now clears Git's repository variables only inside the archived-quality
subshell; a regression proves nested repositories resolve to their own source.
The 59-contract rerun passes. Exact staged-hook verification remains required.

GitHub metadata resolves repository ID 1186432839 to `iRedlof/Glimpse`; API writes
through its former name returned HTTP 307. Current policy, workflow download URLs,
local artifact URLs and the new app's Sparkle feed use the canonical name.
Only the exact audited legacy release retains its original feed URL.
Both rename regressions pass in the 61-contract suite. Main protection was applied
and read back: strict required checks, enforced administrators, required PRs,
linear history, conversation resolution, no force pushes or deletions.

Canonical main subsequently advanced to
`eb4fc447be5491f2e665b3bde005c622b5083853`. Its legacy release run
`41364245310`, attempt 1, failed compiling the old core dependency graph; build
was skipped and no v1.4.4 publication/tag exists. The first-install recovery
controller now checks a narrowly authenticated/pinned GitHub attestation while
preserving the failed conclusion. Ten bootstrap fixtures and three strict
public-download fixtures pass, bringing the suite to 74. The release specialist
independently downloaded the pinned v1.4.3 DMG/tagged/latest feeds through the
strict curl helper and confirmed their hashes/identical feeds.

Root created the freshly audited status `57802094024` and pinned creator `891898`.
The live gate passed for verified remote main `eb4fc447be5491f2e665b3bde005c622b5083853`;
the original run remains failed. Independent review confirmed the exact status.
The implementation branch was fast-forwarded to that main revision before
reapplying the externally backed-up implementation patch. Conflict resolution
retained the reviewed inspect outputs/canonical dynamic download prefix and
1.4.4 README badge. Main's About link, embedded feed, CLAUDE note and cask URLs
remain intact; all four project versions are 1.4.4/build 11. Dependency and
workflow checks pass. Final staged app/core tests and hosted publication remain
required.

Isolated runtime evidence: `docs/qa-live.md`. Startup and an enabled menu extra
were observed; thirteen closed-panel samples over 60.47 seconds showed no
cumulative CPU increase at `ps` precision. This copy retained earlier version
metadata and preceded the final About change. CUA could not reach its native panel
after documented fallback attempts, so the interaction matrix remains unperformed.

An hourly Codex heartbeat, `glimpse-stability-and-release-health`, is active.
It observes the installed executable and GitHub outcomes, stays quiet on unchanged
state, and reports meaningful availability, crash-report, release or observation
changes. It does not relaunch the app, alter login settings or publish code.
