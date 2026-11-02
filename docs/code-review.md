# Production review — 2026-11-01

Current artifact gate: public v1.4.5/build 12 at exact source
`6ffae9e5396f3e5274d000bcae8e7a2947abb3f0`, Release `41379941334` attempt 1,
passed the whole workflow and separate root/QA actual macOS artifact checks.
The DMG's own signature and direct Gatekeeper assessment now pass along with
the app, tickets, Sparkle, hashes, feed and signed entitlements. This permits
retiring the narrowly pinned first-install `legacy_recovery` policy. The
historical review below does not extend unperformed native runtime acceptance.

An initial internal-only helper/policy/doc snapshot passed independent applicable
A1–A8 review against accepted source `6ffae9e5396f3e5274d000bcae8e7a2947abb3f0`
with no actionable P1/P2 finding. The helper requires an explicit existing
absolute keychain and selects the policy team's exact Developer ID SHA.
Manual archive/export and final post-icon DMG signing use that identity;
strict container verification precedes notarization. Quoting, paths with
spaces, valid headless/default packaging, retained app/link, failure propagation
and local-only output boundaries passed offline actual-script contracts.
Root retired only `legacy_recovery` after accepted public artifact evidence.
Independent verification passed 13 helper, 14 signing and three downloaded-DMG
contracts plus Bash, Python parsing, ShellCheck and whitespace checks; the
complete implementation suites passed 142 tooling and 27 monitoring tests.
No native helper cryptographic operations were performed. Actual staged,
hosted source/merge and whole final verification are separate mandatory gates.
Receipt in original checkout storage:
`build/validation/internal-review-eurgcdbv/review-receipt.json`.

Hosted review subsequently identified an adjacent preflight mismatch: its
optional default-keychain check could approve a machine the corrected helper
rejects. Preflight now uses the same explicit keychain/policy-team selector
and fails for missing notarization, executable Sparkle tools, packaging or
authenticated GitHub CLI. It checks Sparkle metadata without reading the
private key and limits success to machine prerequisites. Twelve regression
contracts cover 29 actual-script fixture executions; all 154 tooling and
27 monitoring tests pass. Independent correction review, staged-source,
hosted source/merge and final delivery checks remain separate gates.

**Bounded source and delivery review passed.** The startup, input, event,
diagnostics and release corrections passed review, including the narrow
first-install recovery, strict public downloads and temporary storage routing.
The canonical repository's failed legacy run requires the pinned recovery
attestation described below; integrated staged tests and hosted execution remain
independent gates. This conclusion includes the limits below; it does not
establish the cause of the crash reported on another Mac or certify unperformed
native interaction and restart scenarios. This reviewer did not change release
readiness settings.

Reviewed actual tracked and untracked worktree source, tests, monitoring, hooks,
controller and workflow files against baseline
`1eaae2643625f435c3a5b176b7f63b5de1ebcd21`, following `CLAUDE.md`,
`.claude/rules/pre-production-review.md` A1–A8, applicable Swift rules,
`known-issues.md`, and the stabilization design/plan. Product, UX and QA evidence
was inspected separately from implementation and test results.

## Findings and correction assessment

The initial review found five concrete delivery defects. All are resolved in
the final reviewed script snapshot, with independent regression verification.

| Section / priority | Initial finding | Final behavior and evidence |
| --- | --- | --- |
| A7/A8 — P1 | A successful same-source dispatch replaced the latest run identity and permanently closed admission despite unchanged healthy distribution. | `verify_previous` accepts a successful newer exact-source run only with its successful `release-verified` job. The public manifest retains the original artifact-producing workflow identity. Same-source success and missing-final-verification fixtures pass. |
| A7/A8 — P1 | A failed same-source internal dispatch could not recover an unchanged earlier publication because source equality was rejected. | `recover_release` distinguishes the failed workflow's owned publication from an earlier verified publication of the same source. Failed-run recovery records bind the exact failed run/attempt/SHA. Same-source failure/recovery fixtures pass. |
| A7/A8 — P1 | A downstream rerun invalidated the manifest's unchanged publishing attempt. | `verify_healthy_release` verifies the successful original artifact-producing `build` attempt, the latest successful final verification job and whole run. A manifest from a failed build attempt remains rejected. Retained-publication and transient-final-job retry fixtures pass. |
| A7/A8 — P1 | Recovery assumed inspect ran in the latest attempt, although “rerun failed jobs” can retain inspect's earlier artifact. | Inspect exposes the actual previous-record artifact name; recovery locates the retained nonexpired record for the failed workflow before scoped withdrawal. The attempt-2 recovery fixture uses attempt-1 inspection evidence and verifies restored distribution. |
| A7/A8 — P2 | Repeating the documented local quality command reused an existing `.xcresult` path and failed. | `quality-gate.sh:11` creates a unique run directory. Two consecutive local fixture runs produce distinct result bundles and succeed. |

Correction review also caught and resolved three related problems:

- A retried final verification job could report success using a carried-over
  build output after recovery had withdrawn the publication. The final Ubuntu
  job now anonymously re-downloads the public DMG, manifest and exact/latest
  feeds, rechecks hashes, source/run identity and latest status, and rejects a
  withdrawn release. The separate original build attempt remains the evidence
  for macOS signing/notarization checks.
- Pre-commit previously tested a mutable working tree. It now archives the exact
  staged tree, tests that snapshot, and rejects index, tracked working-tree or
  untracked source changes made during testing. A concurrent index-change
  fixture requires a new test run.
- Nongit staged archives and inherited `GLIMPSE_SOURCE_ROOT` exposed real test
  fixture failures. Offline hook fixtures now own their temporary Git
  repository; nested quality fixtures clear inherited source/build/result/output
  overrides. All contracts pass again in that archived environment.

These assessments inspect the final implementation and execute its fixtures.
They do not claim that a GitHub publication, withdrawal or recovery mutation was
performed during review.

### A1/A7/A8 — P1 resolved: sandboxed diagnostics lacked a chosen-file grant

Integration review found that `Glimpse/Glimpse.entitlements` enables app sandboxing
without a filesystem grant, while the earlier `DiagnosticsExport.swift:72`
constructed and wrote a Desktop path directly. Collector-only tests did not
exercise report export. The final correction uses an asynchronous `NSSavePanel`
with plain-text output and a filename/Desktop suggestion, adds
`com.apple.security.files.user-selected.read-write`, and writes only the returned
destination through `export(to:)`. Cancellation restores idle before collection;
write errors remain observable with Retry, and success retains Show in Finder
and Export again. The source and three report-destination regressions were
reviewed; all three pass in the final app suite. Native save-panel/Powerbox
behavior remains a separate unexecuted QA scenario.

### A7/A8 — P1 resolved: Git hook environment contaminated nested test repositories

The first actual commit-hook integration attempt failed before compilation:
Git-exported repository/index variables reached archived tests, and nested
fixture Git commands operated on the hook's repository rather than their own.
The parent reported eight fixture errors/two failures and restored only the
introduced shared local configuration; no commit resulted from that attempt.

The corrected `tools/scripts/hooks/pre-commit:18` runs archive quality in a
subshell that clears every repository variable named by
`git rev-parse --local-env-vars`. The outer hook retains those variables for
archive creation and the final index/working-tree comparison. The regression
exports `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE` and `GIT_PREFIX`, then checks
that a nested test repository owns its configuration and commit. Temporary paths
are canonicalized to avoid `/var` versus `/private/var` alias failures.

This reviewer independently reproduced a failing previous hook and passing
corrected hook using only temporary fixture repositories. The complete current
59-test suite passed both in the checkout and a nongit archive context. The
actual staged commit-hook retry remains an integration step.

### A4/A7 — P1 resolved in source: embedded feed and canonical artifact identity

Repository metadata identifies ID `1186432839` as `iRedlof/Glimpse`. The controller
and generated new feeds now use that canonical repository, and the old
`rlchandani/Glimpse` feed is accepted only for the exact pinned legacy release.
This review caught the remaining old `Glimpse/Info.plist:30` feed while
`tools/scripts/verify-dmg.sh:38` expected canonical `SUFeedURL` for a new artifact.
That mismatch would fail downloaded app identity verification. The source feed
is now canonical as well. The 61 contract tests include accepting the exact
pinned legacy feed and rejecting the old alias for a newer release.

### A7 — P1 resolved in source: canonical main predates Recovery installation

Independent read-only API checks found canonical main at
`eb4fc447be5491f2e665b3bde005c622b5083853`, a newer repository-transfer/version
commit. Release run `41364245310` completed with failure in `Test (GlimpseCore)`;
its build was skipped. The pinned v1.4.3 source/run remain unchanged and healthy,
but canonical `recovery.yml` lookup returned HTTP 404. The controller's live gate
therefore remained closed before the first-install recovery attestation.

The controller now admits only this exact pre-installation failure after fresh
verification of its skipped build, absent v1.4.4 publication/tag and unchanged
healthy distribution. A distinct status binds the exact failed run/attempt/SHA,
healthy tag/full SHA, canonical target URL and completion timestamp. The policy
pins its numeric status ID and authenticated creator. The newest matching status
wins, so revocation cannot leave an older green status effective. Reruns, another
release, build success, publication, changed healthy identity or ordinary main
advancement remain closed. Only the active first main Release push whose source
has the failed revision as its sole parent may inspect that predecessor.

Independent review passed all 74 contracts in both the checkout and a nongit
archive with inherited snapshot settings, plus actionlint, shell syntax and
warning-level ShellCheck. The read-only live bootstrap request passed and its
109-character description binds the full healthy SHA. The strict download helper
independently retrieved the pinned 795-byte feed with matching SHA-256. No new
actionable source blocker was found. The reviewer made no remote mutation.

Root subsequently created status `57802094024` with creator ID `891898` at
`2026-11-02T00:55:30Z` using that freshly verified exact request and pinned its ID.
The failed workflow conclusion remains failure. The exception must be removed
after the first normal successful public release; future failures use Recovery.
The repository-transfer changes were retained and independently verified after
source integration. The independently rerun live gate exits 0, recording
`verified_remote_sha` equal to `eb4fc447be5491f2e665b3bde005c622b5083853`.

### A7 — public verification and selected temporary storage

Public downloads use `/usr/bin/curl --disable` with certificate verification,
HTTPS-only transfer/redirect protocols, a 60-second curl deadline and 70-second
subprocess deadline. Certificate or other transfer failure removes partial output
and fails verification; no insecure TLS option is present. The public final job
checks tagged and latest feed bytes in addition to manifest/DMG integrity.
Local hook temporary files, quality-run temporary files and release-job temporary
files use their selected build storage, avoiding internal-disk exhaustion while
external storage is available. Both changes passed independent scope review.

## A1–A8 checklist

| Section | Review result |
| --- | --- |
| A1 — Permissions and accessibility | Event reads require full access at the reducer and actor boundary. Permission requests originate from an explicit user action; denied/restricted/write-only states clear prior events and present recovery controls. Diagnostics now asks for a file through NSSavePanel and includes the matching user-selected read/write entitlement. Existing calendar/date accessibility structure remains intact, and new startup/retry controls have accessible text. Native VoiceOver, TCC/Powerbox changes and small-screen fit have not been verified. |
| A2 — Panel and menu bar | Re-show collapses preferences and resets transient store state. Explicit hide notification clears pending resize/input state, removes monitors and restores prior-app activation. Pin behavior, existing screen/caret clamping, single-image menu rendering, midnight refresh and resize convergence are retained. Repeated native focus, Space, multi-monitor and menu overflow scenarios remain unexecuted. |
| A3 — Carbon and input | Persisted hotkeys are range- and modifier-validated before unsigned conversion. Routing requires the visible originating panel; text arrows and modified navigation pass through. Monitor setup is idempotent, and hide explicitly removes key/scroll monitors. Recorder lifecycle suspends calendar handling and cancels on hide/Escape. Automated checks exercise routing decisions rather than delivered native events or lifetime. Existing shortcut-registration conflict feedback remains deferred. |
| A4 — Sparkle | The new embedded/generated HTTPS feeds now use the canonical repository; the old feed is accepted only for the pinned legacy release. The EdDSA public key and updater callbacks remain intact. Local/downloaded DMG verification checks team/bundle/version/build/source, hardened runtime, notarization, Gatekeeper and cryptographic Sparkle signature. Publication begins as an empty draft; withdrawal requires workflow/SHA ownership. Corrected retry/recovery paths retain artifact identity and recheck public distribution. |
| A5 — AI | Existing proxy protections and FoundationModels compile/runtime guards remain intact. Intentionally deferred automatic-provider behavior is preserved. Hide cancels the retained query task; completion checks cancellation before UI mutation. Error text names Cloud AI recovery. Native caret, Return and Escape behavior remains untested. |
| A6 — Preferences and EventKit | Startup UI derives its switch from observed macOS status, preserves approval/not-found/unavailable distinctions, serializes registration changes, re-reads success/error status and refreshes after activation. Weekday/workday values are sanitized at load. EventKit owns its store on a serial actor, uses selected local calendar-day boundaries, and rejects stale responses with date plus request UUID. Loading, empty, error, retry, revocation and access states are distinct. |
| A7 — Quality, performance and security | Reviewed exact SHA/run/attempt checks, ownership, drift classification, external storage and temporary processes. No newly exposed source secret or user-derived subprocess argument was found. Diagnostics avoid pipe backpressure, enforce a ten-second child deadline and read at most a 1 MiB log excerpt into memory; the report also contains its header/settings, and temporary disk output may exceed 1 MiB during that interval. About retains Show in Finder, Export again and Retry. Hosted admission and client-hook limits are stated below. |
| A8 — Tests | Regression coverage includes startup status/operations, malformed settings, selected-day/DST conversion, stale responses, cancellation/revocation, diagnostics volume/deadline/failure and chosen-destination/partial-report/write-failure paths, release identity/recovery, staged-source changes, batched commits, archived test execution and Git hook repository-environment isolation. The history harness tests every introduced source commit and the PR merge result, records requested/tested/failed SHAs, and fails on an intermediate bad commit. Fork app/core tests use a disposable hosted macOS runner; the required aggregate fails unless the appropriate runner succeeds. |

## Verification evidence

This reviewer independently ran the prior rename snapshot:

- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/scripts/tests -v`:
  **61 tests, zero failures, exit 0**. Log: `/tmp/glimpse-review-tooling-rename.log`.
- The preceding 59-contract snapshot also passed from a nongit copied tools/policy snapshot with inherited
  `GLIMPSE_SOURCE_ROOT`, external build storage and `GITHUB_OUTPUT`:
  **59 tests, zero failures, exit 0**. Log: `/tmp/glimpse-review-archived-hook-env.log`.
- Monitoring fixtures: **27 tests, zero failures, exit 0**.
  Log: `/tmp/glimpse-review-monitoring.log`.
- `actionlint` for all three workflows, shell syntax, `shellcheck --severity=warning`
  for scripts/hooks, `git diff --check`,
  dependency-pin consistency and version synchronization: **exit 0**.
  The app/core have 15 matching pins and version **1.4.4/build 11**.
- The earlier old-alias read-only gate exited 0 for public v1.4.3 at baseline
  `1eaae2643625f435c3a5b176b7f63b5de1ebcd21`. At the pre-attestation
  snapshot, the canonical gate **exited 1** because the newer failed main had
  no verified recovery.
  Log: `/tmp/glimpse-review-rename-livegate.log`.
- Separate live `verify_healthy_release` through canonical API **exits 0**:
  v1.4.3, baseline source, publishing run `30221537836`, release `360125950`.
  This distinguishes healthy distribution from the failed-main admission issue.

This reviewer inspected, rather than duplicated, the app/core build results:
`/tmp/glimpse-core-green.log` records **62 passing tests in five suites**.
The latest About/save-panel/metadata app rerun in `/tmp/glimpse-app-final.log`
records **57 passing tests in nine suites** and `TEST SUCCEEDED`, with result
bundle `/Volumes/xHome/Github/Glimpse/build/validation/app-validation-final-4.xcresult`.
It preceded the canonical feed URL change. Core source was unchanged after the recorded core run. Complete staged-hook
verification remains the final integration check after review documents are
staged.

The subsequent bootstrap/TLS/storage snapshot passed **74 contracts** independently
in both the checkout and nongit archive, plus all workflow and shell checks.
Independent QA additionally passed **74 contracts and 27 monitoring fixtures**.
The release specialist used the strict helper for the public DMG/tagged/latest
feed audit and confirmed pinned hashes and identical feed bytes. These supplement,
and do not replace, the final integrated staged app/core check.

## Quality workspace follow-up

The initial staged hook subsequently passed 57 app, 62 core, 74 tooling and 27
monitoring tests for commit `1125158df09bf9dc6ab3f1e31465d6961d920938`.
Push Quality passed; PR Quality attempts 1 and 2 stalled in dyld before app entry
and did not test the merge revision. Attempt 3 used fresh internal scratch with
unchanged source and passed the source and merge snapshots. This is evidence
about loader path/state, not a demonstrated application failure.

PR review correctly identified that `quality.*` directories retained whole
DerivedData and core scratch trees. The follow-up separates durable result paths
from a private `RUNNER_TEMP` or `/tmp` workspace and removes only that generated
workspace on ordinary exit. The dependency cache and archived source stay outside
cleanup. Root reviewed the bounded diff; independent QA passed 77 contracts and
27 monitoring fixtures, scoped ShellCheck and shell syntax. Regression fixtures
cover success and app failure with default/supplied results, private permissions,
partial result retention, unrelated sibling files and inherited external temp
settings. The full staged hook passed 57 app, 62 core, 77 tooling and 27
monitoring tests for `4b41fbb489bf38fd941e79dc4c730e9f6bc36a62`.
Independent QA inspected the exact tree, retained results and dependency hashes,
and confirmed removal of the source archive and temporary workspace. Push
Quality `41372558066` and PR Quality `41372562579` passed; the latter tested
both introduced commits and merge snapshot
`801adb28c8724f621e29e345f069e83f3eb31eb9`. No forced-kill guarantee is
claimed for local `/tmp`; CI additionally
uses runner-managed temp cleanup.

## A4/A7/A8 — release signing follow-up

The first modern Release `41373019433` attempt 1 passed source quality for
merged main `75b68685b2de1690cb4b78f71150d654ed17e359`, then failed at
archive signing. The temporary job keychain contained a valid Developer ID
identity, but Xcode's automatic archive signing selected a different development
identity from the login keychain and failed while signing Sparkle. No export,
notarization or publication ran; no v1.4.4 release or tag was created.
Automatic Recovery `41373225077` attempt 1 verified the unchanged v1.4.3
distribution and bound its record to that exact failed run, attempt and source.
Root, QA and the release specialist independently verified the recovery; the
live gate passes for the failed main source.

The bounded correction selects exactly one valid Developer ID Application
identity for the expected team from the job keychain. Missing, malformed,
wrong-team, ambiguous and unreadable identity results fail closed. Archive uses
manual signing with the exact SHA and explicit keychain; export uses the same
SHA and manual style with the existing job-first keychain search list. A private,
disposable executable probe checks signing and strict verification before archive.
It has no timestamp so it tests key access separately from notarization.

Review additionally found that an early import/selection failure could skip
certificate-file removal. The install step now creates files under `umask 077`,
and the always-cleanup step has an EXIT backstop removing only the known job
certificate/CA paths, even if original-keychain restoration fails. The saved
original list survives a restoration failure for diagnosis. No login-key ACL or
distribution key changes.

Root reviewed the helper and workflow against A4/A7/A8 and inspected the
developer's fourteen passing regressions. They cover identity selection and
timeouts, absence of raw error output, spaces in keychain paths, archive/export
consistency, signing/verification failures stopping archive, probe cleanup,
certificate mode 0600, original-list restoration, restoration failure and
unrelated-file preservation. The prior automatic-signing workflow and certificate
cleanup failed their regression fixtures before correction. Actionlint passes
all three workflows. Independent QA found no blocker under A4/A7/A8 and passed
all 91 tooling contracts, 27 monitoring fixtures, Bash syntax, ShellCheck on
all five changed workflow blocks and actionlint. Full staged-source checks and
real signed publication remain independent gates.

The signing correction's normal staged hook passed 57 app, 62 core, 91 tooling
and 27 monitoring tests. Exact-source push and PR checks passed before PR #6
merged with its reviewed tree as `b9017a70b1f09142755cd988af180884b4e3e321`.
Release `41374516171` attempt 1 passed the private-key probe, Archive, Export
and app notarization. Its later Finder packaging timeout is separate from
signing; Automatic Recovery `41374986732` verified unchanged v1.4.3 and the
exact failed run/attempt/source. No new public artifact was accepted.

## A4/A7/A8 — archived tooling and headless packaging follow-up

Root reproduced a historical-quality gap: app/core used exact archives, but
tooling and validators came from the latest checkout. A broken intermediate
signing helper could therefore be recorded as tested after its head was fixed.
Four quoted paths now use archived `ROOT` for tooling tests, monitoring tests
and version/pin validators. Current orchestration still owns private workspace
creation and cleanup; archived runner scripts are not executed.

Independent QA passed 95 tooling and 27 monitoring tests, shell checks and
whitespace checks, with no A4/A7/A8 blocker. The regressions use actual Git
history/archive operations and the real signing selector to reject the exact
broken intermediate SHA before builds. Clean-history checks cover per-archive
paths, requested/tested SHA records, private workspaces, ordinary-exit cleanup,
retained logs/result bundles/hashes/cache and unrelated-file preservation.
Validator/monitoring failures include synthetic fixtures; build commands are
stubbed, so full staged and hosted app/core tests remain independent gates.

The packaging failure occurred while Finder arranged the installer window,
before DMG notarization. The supported create-dmg `--skip-jenkins` option
avoids that cosmetic AppleScript and retains app contents and the Applications
shortcut. Root verified this behavior with a real harmless DMG and read-only
mount; its generated workspace was removed. Signed public verification remains
required.

Five extracted-workflow packaging regressions passed after four expected RED
failures. They verify headless option/drop-link/app staging, unchanged app/DMG
notarization and ticket checks, and failure propagation at packaging, notary,
stapling and validation boundaries. Commands for those checks are fakes; root's
real harmless DMG supplies separate packaging evidence.
Independent final QA passed all 100 tooling contracts and 27 monitoring fixtures,
extracted app/DMG shell syntax and ShellCheck, actionlint and whitespace checks.
No A4/A7/A8 code blocker remains; exact staged and hosted/public checks are
independent requirements.

The follow-up's normal hook and push/PR checks passed before PR #7 merged with
the approved tree as `d0914230771993ee039ca4e5dfbe91f1d4504be0`.
Release `41376023212` passed both app and DMG notarization, Sparkle signing
and local signed-artifact verification. It then exposed a publication fixture
gap: the offline model allowed a draft lookup by tag before publication, while
GitHub returned 404 for the unpublished tag. Creation left empty private draft
`431002599`; the lookup's JSON was incorrectly captured as `RELEASE_ID`.
Automatic Recovery `41376385603` verified the exact failed source and unchanged
v1.4.3 distribution. The next correction must use validated structured numeric
draft IDs and prove recovery/ownership before handing a never-public tagless
draft to an internal-only descendant workflow. No public release is accepted.

The frozen correction uses structured REST creation/update receipts and explicit
numeric IDs for private verification. Receipt validation is pure, so a later
read failure retains the ID for withdrawal. Same-run retries require
never-public/tagless state; different-run handoff additionally requires an empty
draft, freshly verified distribution, exact failed run and source-scoped newest
Recovery proof, internal ancestry and pre-mutation source/candidate checks.
Ordinary admission retains its global newest-Recovery rule. Expected RED
fixtures now model tag lookup returning 404 before publication and subsequent
request failure. The developer reports 28 focused, 123 tooling and 27 monitoring
tests passing with shell/whitespace checks; independent acceptance is pending.

Independent frozen-diff A4/A7/A8 review found no scoped blocker and reran all
123 tooling contracts and 27 monitoring fixtures successfully. Publisher
Bash/ShellCheck, all-workflow actionlint, Python syntax and whitespace checks
passed. These fixtures do not replace real GitHub handoff/publication or
signed artifact acceptance.

PR #8 merged as `b37a4d4bc8f67bff728dd75b581fc0fc6849dd3a` after exact staged
and hosted checks. Release `41378309147` attempt 1 completed successfully and
published v1.4.4 with the recovered draft's exact new identity. Independent public
hash/feed/source checks and app signature/notarization/Gatekeeper/entitlement
checks passed.

### A4/A7/A8 — resolved in source: DMG container signing and acceptance gate

Root and QA independently reproduced codesign exit 1 (`code object is not signed
at all`) and direct DMG Gatekeeper exit 3 (`no usable signature`). DMG stapling
and the contained app's Developer ID/Gatekeeper checks pass. The release workflow
signs the app but not the final container, and `verify-dmg.sh` omits container
signature/team/Gatekeeper checks. Whole-workflow success therefore did not
establish full container acceptance. The fix must sign the final bytes with the
selected Developer ID/keychain before notarization, fail before publication on
signature/identity/Gatekeeper errors, and advance to v1.4.5/build 12 without
rewriting the public v1.4.4 assets or tag. Native runtime limits remain open.

Independent frozen-diff review finds no code blocker in the correction.
Selected identity/keychain and secure timestamp sign the final bytes before
strict verification/notarization. Downloaded strict signature, exact team and
Developer ID authority, ticket and direct Gatekeeper checks precede mounting.
Existing app/runtime/source/feed/Sparkle checks remain. All 129 tooling
contracts, 27 monitoring fixtures and static checks pass; additional temporary
failure probes confirm detach/cleanup. App/Core behavior is unchanged, and all
four versions/builds plus README are synchronized to 1.4.5/build 12.
Actual hosted signing and independent public-artifact acceptance remain open.

## Enforcement and native limits

The applied canonical main protection was independently read through GitHub API:
strict up-to-date
checks `App and core tests`, `Release tooling checks` and `Previous release
verified`, each bound to GitHub Actions producer 15368; enforced administrators;
required PRs with zero required approvals and no bypass allowances reported; no
force push or branch deletion; required linear history and conversation
resolution. This reviewer did not apply settings.

For normal protected merges, advancing main makes competing PRs stale; their
updated heads must rerun admission against current main until its release or
exact recovery succeeds. Admission runs for every PR using the trusted main
controller, with an explicit full-SHA administrator-pinned bootstrap when legacy
main lacks that controller. Missing/mismatched bootstrap values fail closed.
The main reusable quality call skips self-admission because Release.inspect
verifies its predecessor.

Static required checks cannot revoke a green PR's earlier admission proof when
a manual dispatch/rerun starts Release at unchanged main. Such manual operations
require coordinated merge pause and a fresh gate before the owner's merge, as
documented in release automation. Absolute locking across arbitrary same-source
manual runs would need dynamic admission. Configured local hooks re-query state
but `--no-verify`, other clones and changed hook configuration can bypass them.
Workflow/controller changes rely on trusted maintainer review.

The isolated QA copy established startup/menu presence and 60.47 seconds of idle
closed-panel behavior. Its older copied version metadata and native UI tool
window limitation are recorded in `docs/qa-live.md`. It did not exercise final
About/save-panel/Powerbox actions, delivered keyboard events, repeated panel
lifetimes, real EventKit permissions/errors, multi-monitor behavior or login/restart. Product
and UX acceptance are limited to the bounded source contract. No installed-app,
login registration, TCC or restart mutation was performed by this reviewer, and
the original other-Mac crash root cause remains unproven.
