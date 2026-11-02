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

The current suite passes 74 contracts and 27 monitoring fixtures, including ten
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
- [ ] Verify the actual split with external archived source/results/cache and
  internal build/temp, then rerun exact-source hosted checks.

The temporary comparison's repository build-root override was restored after
its evidence was preserved. Its pass narrows the loader issue to storage/path or
per-file state; it does not establish that every external-volume build fails.
Independent QA passed 77 tooling contracts and 27 monitoring fixtures after the
cleanup change. Scoped ShellCheck and Bash syntax checks passed. The runner's
internal temp directory provides job-boundary cleanup; local forced kills can
leave `/tmp` workspaces. Actual split-path integration and hosted publication
remain open.

Constraints: no signing-key generation, no installed-app mutation, no destructive
source reverts. Product, UX, code,
and QA readiness require explicit evidence. GitHub concurrency retains only
one pending run; a server policy is needed to prevent bypassing local hooks.
