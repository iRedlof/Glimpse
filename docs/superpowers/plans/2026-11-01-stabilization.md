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
- [x] Verify the first new signed publication through the hosted release workflow.
- [x] Install scoped commit/push hooks and establish quiet monitoring.
- [x] Record independent review, suite and bounded live QA evidence.
- [x] Pass exact staged-tree quality checks and hosted checks before merging.
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

The initial stability source and scratch-cleanup follow-up passed normal staged
hooks and exact-source push/PR checks before PR #5 merged as
`75b68685b2de1690cb4b78f71150d654ed17e359`. Release `41373019433` failed
archive signing; Automatic Recovery `41373225077` verified healthy v1.4.3.
The signing follow-up passed its normal hook (57 app, 62 core, 91 tooling,
27 monitoring tests) and push/PR checks before PR #6 merged as
`b9017a70b1f09142755cd988af180884b4e3e321`.

Release `41374516171` passed source quality, Archive, Export and app
notarization, then failed in create-dmg's Finder AppleScript before DMG
notarization/publication. Automatic Recovery `41374986732` verified the exact
failed source/run/attempt and unchanged public v1.4.3. The next follow-up removes
the Finder dependency using supported headless packaging and tests tooling from
each commit archive. Real harmless headless DMG packaging/mounting passed;
signed publication remains open. The first-install exception stays until that
publication succeeds. Native restart, interaction, signed Powerbox and soak
acceptance remain unperformed; the crash reported on the other Mac is unknown.

PR #7's headless/provenance correction passed its staged hook (57 app, 62 core,
100 tooling and 27 monitoring tests), exact-source push checks and source/merge
PR checks, then merged as `d0914230771993ee039ca4e5dfbe91f1d4504be0`.
Release `41376023212` passed both notarizations, Sparkle and local artifact
verification, then failed looking up a newly created draft by its unpublished
tag. Automatic Recovery `41376385603` succeeded and verified public v1.4.3;
empty private draft `431002599` is retained, with no v1.4.4 tag or publication.
The next correction tracks drafts by validated numeric IDs and requires exact
recovery/ownership proof for retained-draft handoff. First signed public
publication remains an open deliverable.

The frozen publisher correction uses structured numeric draft IDs and verifies
private drafts by ID while retaining public tag/latest verification. Recovered
handoff is limited to empty never-public tagless drafts, exact failed-run and
Recovery proof, fresh healthy distribution and internal-only descendants.
Its RED/GREEN fixtures cover the original failure and receipt-retention cleanup;
28 focused, 123 tooling and 27 monitoring tests pass. Independent review,
staged/hosted checks and first signed public verification remain pending.

Independent frozen-diff QA passed all 123 tooling and 27 monitoring tests
with static checks and no A4/A7/A8 blocker. Root refreshed the exact-main
Recovery gate successfully. Staged/hosted and public gates remain open.

PR #8 merged normally as `b37a4d4bc8f67bff728dd75b581fc0fc6849dd3a` after
staged and hosted checks. Release `41378309147` succeeded completely and
published v1.4.4; real draft handoff, anonymous hash/feed/source verification and
the admission gate passed. Independent macOS QA confirms the contained app's
signature/notarization/Gatekeeper/entitlements, but found the DMG itself unsigned
and rejected by direct Gatekeeper assessment. Full artifact acceptance remains
open. The v1.4.5/build 12 follow-up signs the container before notarization and
adds downloaded signature/team/Gatekeeper gates. The first-install exception
stays until those public checks pass; native restart, UI and soak remain open.

Independent frozen-diff QA accepts the packaging correction with no A4/A7/A8
code blocker: 129 tooling, 27 monitoring tests and static checks pass.
Root/QA confirmed unchanged app/Core behavior and synchronized 1.4.5/build 12
metadata; scoped readiness matches. Existing product/UX acceptance carries
forward with native limits unchanged. Staged/hosted and real public checks
remain required.

## Verified public milestone and internal follow-up

PR #9 passed its real staged hook and hosted exact-source/merge checks, then
merged normally as `6ffae9e5396f3e5274d000bcae8e7a2947abb3f0` with the
approved tree. Release `41379941334` attempt 1 completed successfully and
published v1.4.5/build 12. Root and independent QA passed actual public DMG
and app strict signatures, team identity, notarization tickets and direct
Gatekeeper checks, Sparkle Ed25519, exact source/tag/run/attempt, public hashes
and tagged/latest feed identity. All four signed entitlements match source;
read-only mounts are detached. Delivery metrics record 254.28 seconds and
`release_verified=true`.

The first signed public-artifact milestone is satisfied. The policy's
first-install `legacy_recovery` entry has been removed, preserving the separate
legacy distribution audit. The fresh exact-main gate passes without that
exception. The final internal-only follow-up aligns local artifact preparation
with explicit identity/keychain selection, manual archive/export signing and
signed DMG verification. It retains v1.4.5/build 12 and requires offline failure
contracts, independent review, normal staged/hosted checks and whole final
verification. It does not publish another app build.

The helper correction passed expected RED failures before implementation,
then 13 GREEN tests/41 script fixture executions, all 142 tooling and 27
monitoring tests. Independent applicable A1–A8 review found no actionable
blocker and passed focused signing/verifier/helper contracts and static checks.
Normal staged and hosted source/merge checks and whole final verification
remain mandatory. The offline helper commands and verifier callback are fakes;
no native helper cryptographic validation is claimed.

Native UI, SavePanel/Powerbox, login/reboot, sleep/wake and sustained runtime
acceptance remain open. The reported other Mac's crash cause is still unknown.
