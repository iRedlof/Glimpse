# Release and commit gates

Every pushed branch runs tooling contracts, app tests, and core tests for every
introduced commit, using immutable Git archives. Pull requests also test the
merge result. Main pushes run the same quality workflow and the serialized
Release workflow. Fork pull requests run app tests on a disposable hosted macOS
runner. Each batch preserves requested/tested SHA lists, its predecessor and
head identity, per-revision logs, and the first failed SHA. A failed intermediate
commit blocks the batch even if its head would pass. The batch timeout is 120
minutes; timeout fails the required check rather than dropping revisions.

The current quality runner owns orchestration and cleanup. Its tooling and
monitoring suites, version checker and dependency-pin checker execute from the
same archive as the app/core source. This prevents a later tooling fix from
masking an intermediate revision's failure.

Quality builds use a private temporary workspace below `RUNNER_TEMP` in CI, or
`/tmp` locally. This contains DerivedData, core build scratch and child-process
temporary files; ordinary exit removes only that generated workspace. Logs,
result bundles, dependency hashes and the SwiftPM download cache stay in selected
build storage. The Glimpse runner's configured temp directory is on its internal
disk. GitHub manages that directory at job boundaries; callers using local
`/tmp` must account for leftovers after a forced kill that cannot run shell traps.
Inherited external `TMPDIR` settings do not select the quality workspace.

Each app release needs a higher marketing version and Sparkle build number,
synchronized in all four project settings and the README badge. It also needs
`.github/release-readiness.json` for that version/build, with passed product,
UX, code, and QA reviews pointing to checked-in evidence. Passing automated
tests means all executed tests passed; this is not a claim of complete code
coverage or coverage of another Mac that was unavailable.

Internal changes limited to documentation, CI, and developer tooling may retain
the current version/build and skip publication. They still run quality checks
and the final `release-verified` job. The gate independently compares their
exact main source against the healthy published source, so unshipped app or
dependency changes cannot masquerade as a documentation-only revision.

The workflow:

1. Verifies the previous public release's tag, source SHA, successful workflow,
   final `release-verified` job, manifest, asset digests, and feed metadata.
2. Runs app/core tests with checked-in immutable package pins, pipe failure
   propagation, full logs, and an app result bundle.
3. Builds with the source SHA embedded in the signed app, signs and notarizes
   the app and DMG, and signs the feed enclosure with the existing Sparkle key.
4. Checks bundle/version/build/source/team/feed identity, hardened runtime,
   notarization tickets, Gatekeeper acceptance, and the Ed25519 signature.
5. Creates an empty draft at the exact SHA, uploads all required artifacts,
   downloads the draft, and repeats artifact verification.
6. Confirms main still points to that SHA, publishes, and anonymously downloads
   the public DMG, manifest, exact feed, and latest Sparkle feed. A bounded retry
   handles CDN propagation. The final job rechecks public hashes, identity, and
   latest feed even when retried independently. The gate anchors the manifest
   to a successful artifact-producing build attempt and a successful latest
   final verification job. The whole workflow must succeed.

DMG packaging uses create-dmg's supported `--skip-jenkins` mode to avoid Finder
AppleScript on a CI runner. The image still contains the app and an Applications
shortcut; custom Finder icon positioning is omitted. App/DMG notarization,
stapling, Sparkle signing and local/draft/public verification remain mandatory.

The latest pre-existing v1.4.3 was independently audited on 2026-11-01:
source/tag/main SHA `1eaae2643625f435c3a5b176b7f63b5de1ebcd21`,
workflow run `30221537836`, version 1.4.3/build 10, matching GitHub digests,
valid Developer ID signature, app/DMG notarization tickets, and Gatekeeper
acceptance. `.github/release-policy.json` pins this one legacy release because
it predates the verification manifest and final verification job. New releases
do not receive that exception.

The repository has since moved to `iRedlof/Glimpse`. New artifact/feed URLs and
the embedded updater feed use that name. Only the exact pinned v1.4.3 release
may retain its original `rlchandani/Glimpse` enclosure URL.

## Install local blocking

Run `tools/scripts/install-release-hooks.sh` in each checkout. The installer
first verifies the previous release and configures a worktree-specific hook
path. Both pre-commit and pre-push fail closed if GitHub is unreachable, the
latest remote main revision is unreleased, or its release workflow is pending,
failed, cancelled, or missing exact artifact verification. Hooks make no cached
success decision. Pre-commit requires all source changes staged, archives the
exact index tree, runs the complete quality gate against that snapshot, and
rejects index/working-tree changes made during testing. Ignored files are
excluded from the tested snapshot; dependency lockfiles must be tracked.
Existing custom hook paths require explicit integration so
they are not overwritten.

`python3 tools/scripts/release-control.py gate` is the same read-only check.
Each normal commit/push is blocked from the moment main advances until the
release workflow has completed successfully in GitHub, or a failed release has
a completed, verified recovery bound to that exact failed revision.

This enforces the policy in configured checkouts. `--no-verify`, a changed Git
configuration, direct API writes, and other clones can bypass client hooks.
For hosted enforcement, require pull requests with strict up-to-date branch
checks, the GitHub Actions checks `Previous release verified`, `Release tooling
checks`, and `App and core tests`, and no direct-push/admin bypass. The admission
job runs the controller from trusted main and fails while main's latest release
or recovery is pending. Merging one PR advances main and makes other PRs stale;
updating them invalidates earlier head checks and reruns admission. This
serializes protected main merges around verified release completion for the
normal automated main-push path.
Workflow/controller changes require trusted review to preserve the check's
meaning. Client hooks still only control configured checkouts.

Coordinate manual Release dispatches/reruns with a pause in merging. Starting
a run at unchanged main does not invalidate an already-green PR's check proof,
so strict branch protection alone cannot impose an absolute lock during those
manual operations. Refresh admission after they finish. Enforcing that lock
against arbitrary manual operations requires a dynamic merge coordinator or
an administrator-managed merge lock; the local hooks re-query on every operation.

First installation uses an explicit administrator-pinned exception because
legacy main lacks the controller: `ADMISSION_BOOTSTRAP_BASE_SHA` must equal
trusted main's full SHA and `ADMISSION_BOOTSTRAP_SHA` must be the exact independently
reviewed implementation commit in the same repository. Only that immutable
commit supplies the controller. Missing/mismatched values fail closed. Delete
both variables after main contains the controller; ordinary PR/head input is
never a fallback controller source. GitHub concurrency alone retains only one
pending run and cannot enforce these admission restrictions.

The first-install base is
`eb4fc447be5491f2e665b3bde005c622b5083853`. Its legacy Release run
`41364245310`, attempt 1, failed before build and predates Recovery installation.
The `legacy_recovery` policy block admits only this audited case. The read-only
`bootstrap-record --output FILE` command checks its exact identity, skipped
build, absence of the proposed release/tag and unchanged healthy distribution.
An authenticated administrator records that exact request as a distinct
`glimpse/bootstrap-recovery/41364245310/1` commit status; the policy pins its
returned ID and creator ID. Every gate rechecks all evidence and the newest
matching status, so revocation, a newer run or changed publication closes it.
This status does not change the failed workflow conclusion or replace its tests.
The first modern Release may consume this predecessor only during an active main
push whose commit has that failed revision as its sole parent. Remove
`legacy_recovery` after the first normal Release completes successful public
verification. Subsequent failures require the automated Recovery workflow.

The recorded first-install status is `57802094024`, created by administrator
`891898` at `2026-11-02T00:55:30Z`. The original Release run remains failed.

## Failure recovery

A failed build or draft verification leaves the previous release public.
A failed publication or public health check re-drafts only the release whose
body contains the current workflow ID and SHA. It never deletes release assets
or tags, reverts Git history, changes signing keys, or modifies an installed app.
Re-drafting makes the previous public release latest again; the controller
checks that identity. Clients that already installed a published build cannot
be downgraded by withdrawing its feed. Ship a corrected higher build for those
clients.

Failures retrieving or changing GitHub state remain visible and keep the gates
closed. If GitHub is unavailable during withdrawal, an operator must verify the
draft/latest state when service returns; automation cannot promise a remote
mutation during an outage. The error identifies this required recovery.

The Release Recovery workflow runs automatically after a failed/cancelled main
release. It refuses an active or newer release, verifies ownership before
re-drafting any partial publication, verifies the previous healthy release and
its assets, and uploads a record binding failed run/attempt/SHA to healthy
tag/SHA. Only a completed successful recovery workflow and matching record
unlock a remediation commit. No running release, arbitrary divergence, or
unverified rollback can use this exception. GitHub/API failure leaves the gate
closed until a recovery rerun completes. Recovery evidence retains 90 days;
rerun recovery if its evidence has expired before remediation.

For a transient build failure, rerun the same failed workflow. Its draft may be
reused only when the owning workflow and source match. For a source fix after
verified recovery, use a new version/build if a failed draft already retained
the proposed version's tag; automation never retargets that retained tag.

## Metrics and evidence

Every release run uploads `release-metrics.json` with source/run/attempt identity,
elapsed time, quality/build/verification results, and individual job durations.
Successful runs also preserve `source-verification.json`, distinguishing
published app revisions from verified internal revisions.
The workflow summary presents those timings. Test logs/result bundles retain
30 days; metrics retain 90 days. Across runs, these support release frequency,
failure rate, and time to recovery calculations. They do not claim runtime
health on machines that were not exercised.

Required secrets remain `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PWD`,
`SPARKLE_PRIVATE_KEY`, `APPLE_ID`, `APPLE_ID_PASSWORD`, and `TEAM_ID`. The
automation imports the existing certificate and Sparkle key; it generates no
distribution key. A trusted self-hosted runner must have Xcode, Swift, Python,
`gh`, and `create-dmg` available.

CI selects exactly one valid `Developer ID Application` identity for `TEAM_ID`
from the temporary signing keychain. A disposable executable signing probe
checks private-key access before archive. Archive and export both use manual
signing with that certificate's SHA-1; archive signing explicitly names the
temporary keychain. This avoids automatic archive signing selecting a different
development identity from the runner's login keychain. The original keychain
search list is restored and the job keychain is deleted during cleanup.
The first modern Release exposed this distinction: its imported distribution
identity was valid, but automatic signing chose a login-keychain development
identity and failed before publication. Ordinary automated Recovery verified
v1.4.3 and permitted the signing correction.

Set the optional repository Actions variable `GLIMPSE_BUILD_ROOT` to a storage
directory writable by that runner. Quality archives, dependency build caches,
release archives, exported apps, and DMGs use unique directories there. Without
it, quality uses the checkout's ignored `build` directory and release uses
runner temporary storage. Fork tests use hosted runner storage. For local
quality/release preparation, the same environment variable or worktree Git
configuration `glimpse.buildRoot` selects storage; no machine path is hardcoded.
Hooks use that storage for archived source and their temporary files. Quality
builds and their child-process temporary files use the separate internal workspace
described above; release jobs route their temporary files through selected storage.
Public-download verification uses system curl with TLS verification, HTTPS-only
transfers/redirects and a 60-second transfer deadline, ignoring custom curl
configuration. Failed or partial downloads cannot produce verification success.
