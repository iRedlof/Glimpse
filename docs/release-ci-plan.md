# Release automation implementation plan

Goal: test each pushed source revision, publish only a reviewed and verified
main revision, and block local commits and pushes while the previous remote
release is unverified.

The release workflow owns one non-cancelling concurrency group. A Python
controller reads GitHub through `gh`, checks exact tag/workflow/source identity,
validates artifact hashes and appcast metadata, and creates a draft before
publication. macOS tooling verifies the downloaded app signature, notarization,
Sparkle signature, and bundle identity. Publication failure withdraws only the
release owned by that workflow and restores the previous latest release.

Implementation:

- [x] Write fixture tests for missing/failed workflows, changed hashes, wrong
  tag/source identity, wrong appcast, network failure, and scoped rollback.
- [x] Implement the fail-closed controller and bootstrap the independently
  audited v1.4.3 release using its exact source and artifact digests.
- [x] Add macOS artifact verification and quality scripts; retain full logs and
  test result bundles, resolve only checked-in dependency pins.
- [x] Replace immediate publication with draft verification, public download
  verification, rollback, a final verification job, and per-run metrics.
- [x] Add checkout hooks and document hosted enforcement limits.
- [x] Add exact-source recovery proof so a safely withdrawn failed release
  permits remediation; verify internal-only main commits without publishing.
- [x] Test every introduced commit and PR merge snapshot, preserve exact SHA
  records, reject dependency changes, and test the exact staged tree locally.
- [x] Add trusted-main admission with an immutable administrator-pinned
  first-install exception and configurable external build storage.
- [x] Run fixtures, shell/Python syntax checks, workflow validation, and a live
  read-only previous-release gate. Leave commit/push/publication to the parent.

Validation on 2026-11-01: 58 release/script contract tests passed both in the
working checkout and an archived source tree with inherited snapshot settings.
The 27 health-monitor tests, actionlint, shellcheck, dependency pin check,
version/build check, and live previous-release gate passed. Failure coverage
includes partial upload, corrupt draft, public-health failure, GitHub outages,
wrong-source withdrawal, rerun attempts, verified recovery, and intermediate
commit failure. Actual signed release publication awaits the parent's reviewed
source and completed release-readiness evidence.

The parent's first real staged-hook attempt additionally exposed Git hook
repository variables leaking into fixture repositories. The hook now clears
those variables within its archived-quality subprocess; the added nested-repository
regression brought the passing tooling suite to 59 contracts. Repository rename
fixtures then brought it to 61; the current controller and new artifact/feed URLs
use canonical `iRedlof/Glimpse`, with the old URL allowed only for the exact pinned
legacy publication.

The canonical main revision `eb4fc447be5491f2e665b3bde005c622b5083853`
has a failed legacy Release run `41364245310`, attempt 1. Its build was skipped,
no proposed v1.4.4 release/tag exists, and the Recovery workflow was not yet
installed. A narrowly pinned first-install recovery attestation preserves this
failure and verifies the still-public v1.4.3 distribution. It requires the exact
authenticated status ID/creator and a fresh audit on every gate call; a later
status revocation, rerun, publication or changed main invalidates it.
The first modern Release may inspect this predecessor only as an active push
whose source is its direct child. Remove the exception after that release passes.

That snapshot passed 74 contracts and 27 monitoring fixtures, including ten
bootstrap contracts and three public-download regressions. Public downloads use
system curl with certificate verification, HTTPS-only redirects and bounded
timeouts; the live pinned DMG/tagged/latest feed audit also passed. Local hooks,
quality runs and release jobs place temporary files in their selected build
storage. Actionlint, warning-level shellcheck, dependency and version checks pass.
The normal staged hook subsequently passed 57 app tests, 62 core tests, 74
contracts and 27 monitoring fixtures for commit
`1125158df09bf9dc6ab3f1e31465d6961d920938`. Push Quality run `41370154800`
passed. PR Quality run `41370175946` attempts 1 and 2 failed before app entry:
the test host stalled in dyld's dependency open and never connected to XCTest.
Neither failed attempt tested the merge revision. Attempt 3 used fresh internal
scratch storage with unchanged source and passed both that commit and merge
revision `a781f5dcea1cd4dcb9e598e83403f9d8e500b6ac`; each passed 57 app and
62 core tests with unchanged dependency hashes.

The PR review also identified persistent `quality.*` build directories. Complete
this follow-up before merge:

- [x] Put each quality run's DerivedData, core scratch and temporary files in a
  private workspace below the runner's internal `RUNNER_TEMP`, or local `/tmp`.
- [x] Retain logs, result bundles and dependency hashes separately in selected
  build storage; remove only the temporary workspace on ordinary exit.
- [x] Exercise success and failure cleanup, supplied result paths and inherited
  external temporary settings.
- [x] Verify the actual split with external archived source/results/cache and
  internal build/temp, then rerun exact-source hosted checks.

The temporary comparison's repository build-root override was restored after
its evidence was preserved. Its pass narrows the loader issue to storage/path or
per-file state; it does not establish that every external-volume build fails.
Independent QA passed 77 tooling contracts and 27 monitoring fixtures after the
cleanup change. Scoped ShellCheck and Bash syntax checks passed. The runner's
internal temp directory provides job-boundary cleanup; local forced kills can
leave `/tmp` workspaces. The normal staged hook then passed 57 app, 62 core,
77 tooling and 27 monitoring tests for commit
`4b41fbb489bf38fd941e79dc4c730e9f6bc36a62`. Its external source archive and
internal `/tmp` workspace were removed; external logs, hashes and result bundles
were retained. Push Quality `41372558066` passed that commit. PR Quality
`41372562579` passed both introduced commits and merge revision
`801adb28c8724f621e29e345f069e83f3eb31eb9`, with 57 app and 62 core tests per
revision, unchanged pins and cleaned internal scratch.

PR #5 merged as `75b68685b2de1690cb4b78f71150d654ed17e359`, whose tree
matches the reviewed head. Its first modern Release, `41373019433` attempt 1,
passed inspection and quality, including 57 app and 62 core tests. Archive
failed while signing the embedded Sparkle framework: Xcode selected a development
certificate from the login keychain instead of the valid Developer ID certificate
imported into the job's temporary keychain. Export, notarization and publication
were skipped. No v1.4.4 release or tag exists.

Automatic Recovery `41373225077` attempt 1 succeeded. Its retained record binds
the exact failed run, attempt and source to healthy v1.4.3, with
`rollback_verified: true`. The independently refreshed gate passed for main
`75b68685b2de1690cb4b78f71150d654ed17e359`; this uses ordinary Recovery,
not the first-install exception. The signing follow-up selects a single valid
Developer ID identity for the expected team from the job keychain, checks that
key with a disposable signing probe, and uses the same identity for manual
archive/export signing. Actual signed publication remains a separate gate.
Independent QA found no new signing blocker under A4/A7/A8. All 91 tooling
contracts and 27 monitoring fixtures passed, including fourteen signing and
cleanup regressions, with workflow/shell checks clean. Exact staged-source
integration and hosted signing remain separate requirements.

The signing correction's normal staged hook passed 57 app, 62 core, 91 tooling
and 27 monitoring tests for `ee60a1f1b1fa3e2be014f0be6a865a3adbe11fdb`.
Push Quality `41374134552` and PR Quality `41374141578` passed; the PR artifact
records that source and merge snapshot `3232ed225b4ceeb8488d48dffe62cbc3707e30c8`.
PR #6 merged as `b9017a70b1f09142755cd988af180884b4e3e321` with the
reviewed tree.

Release `41374516171` attempt 1 passed source quality, exact identity/private-key
validation, Archive, Export and app notarization. Packaging then failed because
create-dmg's Finder customization AppleScript timed out (`-1712`, exit 64);
DMG notarization and publication never ran. Automatic Recovery `41374986732`
attempt 1 verified the unchanged v1.4.3 distribution and retained proof binding
the exact failed run/attempt/source. Root and the release specialist independently
verified the record and refreshed the remediation gate. No v1.4.4 publication
or tag was created.

The packaging follow-up uses create-dmg's supported `--skip-jenkins` option to
avoid Finder customization in CI. A real harmless DMG fixture built successfully
with this option; read-only mounting verified its app contents and `/Applications`
shortcut, then removed only the generated fixture. This proves packaging, not
signed publication. The first-install policy exception remains until a normal
new release completes public verification; both admission bootstrap variables
were already removed after the modern controller reached main.

The same follow-up corrects tooling provenance in historical quality runs.
Current orchestration continues to own private scratch cleanup, while tooling
tests, monitoring tests and version/pin validators run from each exact archive.
Real Git-history regressions reject a broken intermediate revision even when
the head is fixed, and verify archive paths, retained results and workspace
cleanup. Xcode/Swift build commands are stubbed in these path regressions;
full staged and hosted app/core checks remain independent requirements.

Five extracted-workflow packaging regressions passed after four expected RED
failures, bringing the tooling suite to 100 contracts. They preserve mandatory
notarization/stapling checks and reject packaging, notarization, exhausted staple
retries and validation failures. The command fixtures do not contact Apple.
Independent final QA passed all 100 tooling contracts and 27 monitoring fixtures,
scoped shell checks, actionlint and whitespace checks, with no A4/A7/A8 blocker.
Exact staged app/core and hosted/public verification remain required.

The headless/provenance follow-up's normal staged hook passed 57 app, 62 core,
100 tooling and 27 monitoring tests for `0254d13646eb485fd46dc902207b69b508bb508f`.
Push Quality `41375591195` and PR Quality `41375608038` passed; downloaded
artifacts record that source and merge `de287b3906bb369acb71d3ebbac199ad9929f12c`,
matching requested/tested SHAs, immutable pins, retained results and removed
scratch. PR #7 merged normally as `d0914230771993ee039ca4e5dfbe91f1d4504be0`
with the approved tree.

Release `41376023212` attempt 1 passed source quality, signing, app and DMG
notarization, Sparkle signing and local artifact verification. It created draft
`431002599`, then a tag-based REST lookup returned 404 because GitHub had not
created the unpublished tag. The failed lookup's JSON entered `RELEASE_ID`;
the EXIT trap could not parse it as an integer. No upload or publication ran.
Automatic Recovery `41376385603` attempt 1 succeeded and bound the exact failed
source/run/attempt to unchanged public v1.4.3. Root and the release specialist
independently verified the record and refreshed the gate.

The retained draft is private, empty, never published and targeted at the exact
failed source, with its run/source ownership marker; no v1.4.4 tag exists.
The publisher correction captures a validated numeric ID from structured
creation/update output and uses that ID for draft verification. Reusing the
retained empty draft requires exact failed-run and successful-Recovery proof,
no public history/tag, a freshly verified healthy distribution and an
internal-only descendant source. Same-run retries also require never-public,
tagless drafts. Current main and the draft identity are rechecked before
updating its target and ownership marker together. Arbitrary draft adoption
is forbidden. Public verification continues to use actual tag/latest URLs.

Expected failing fixtures reproduced the original 404/error-JSON failure and
a subsequent receipt-retention cleanup gap. The frozen correction passes
28 focused, 123 full tooling and 27 monitoring tests plus Bash syntax,
ShellCheck and whitespace checks. Independent review, normal staged/hosted
checks and signed public verification remain open.

Independent frozen-diff A4/A7/A8 QA found no blocker and passed all 123 tooling
contracts, 27 monitoring fixtures and scoped static checks. Root's refreshed
exact-main Recovery gate passed before staging. Normal staged and hosted
checks and signed public verification remain mandatory.

PR #8 passed staged and hosted source/merge checks and merged normally as
`b37a4d4bc8f67bff728dd75b581fc0fc6849dd3a` with the approved tree.
Release `41378309147` attempt 1 succeeded completely, including real handoff
of draft `431002599`, public downloads, final verification and metrics
(`release_verified=true`, 255.12 seconds). The public manifest binds source/run
and artifact digests; latest-feed bytes match. Root and the release specialist
independently refreshed the live admission gate.

The independent macOS artifact audit then exposed a missing container-signature
gate: the app is correctly signed/notarized and accepted by Gatekeeper, and the
DMG ticket validates, but the DMG itself is unsigned and its direct Gatekeeper
assessment rejects it. Root and QA reproduced the exact result on anonymous
downloads. Full artifact acceptance and retirement of the first-install policy
exception remain open. A higher-version correction will sign the DMG using the
already selected identity before notarization and reject unsigned/wrong-team or
Gatekeeper-rejected containers before publication.

The v1.4.5/build 12 correction passed independent frozen-diff A4/A7/A8 review,
129 tooling contracts, 27 monitoring fixtures and static checks. Failure
fixtures precede production changes and reject signing/strict verification
before notarization and downloaded identity/ticket/Gatekeeper failures before
mounting/publication. Existing signing credentials and Sparkle keys are reused.
Root confirmed unchanged app/Core behavior and carried forward bounded
product/UX acceptance; scoped readiness now matches all four versions/builds
and README. Staged/hosted and actual signed public-container gates remain open.

Constraints: no signing-key generation, no installed-app mutation, no destructive
source reverts. Product, UX, code,
and QA readiness require explicit evidence. GitHub concurrency retains only
one pending run; a server policy is needed to prevent bypassing local hooks.
