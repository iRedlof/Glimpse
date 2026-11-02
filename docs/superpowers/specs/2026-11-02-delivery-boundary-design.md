# CD-01: move release admission to delivery boundaries

Revised design only, 2026-11-01, incorporating `next-delivery-boundary-builder-review.md` A7–A8 and the integrating owner's settled scope. Ready for bounded implementation-plan preparation; implementation and delivery are not accepted by this document. Investigated tooling source against accepted production baseline `302a260e736f8d9cdc14684b1f1281f7768588fa`. No implementation, tests, builds, hook/configuration changes, remote action or production action was performed. This remains a separate iteration after panel screen-fit; its current delivery rules remain active.

## Verified current behavior and proposed boundary

Both local hooks globally consult the health of the canonical repository's latest main Release before allowing development: `tools/scripts/hooks/pre-commit:9` calls `release-control.py gate` before examining staged source, and `tools/scripts/hooks/pre-push:8–9` explicitly ignores Git's push input and gates every push. The installer also consults that gate before installation (`tools/scripts/install-release-hooks.sh:5`). Consequently, a pending Release, unrecovered failure or unavailable GitHub prevents a quality-valid local commit or independent feature-branch push.

Remove remote admission from all local commit, push and installation entry points. Every local commit still needs the existing exact staged-source quality and mutation checks. Server-protected PR integration supplies the main boundary, with the existing required hosted admission executing trusted main's existing `gate`. The owner refreshes that gate and explicitly rechecks current main/run evidence at ordinary protected merge time. Release inspect, signing, draft/public verification and exact Recovery remain mandatory. No client push parser, remote classifier, new tag restriction or admission command belongs in this iteration.

This implements the updated master goal's instruction to block promotion of the affected change without globally blocking unrelated development (`goal-objective.md:344–358`, attachment `/Users/rohit/.codex/attachments/525187ff-4c65-4583-8adc-ab56058ab2d8/goal-objective.md`). Current backlog acceptance requires staged quality, independent feature progress, trusted main admission and scoped Recovery (`docs/stability-roadmap.md:14,24`). Its parser-oriented regression wording must be aligned with the owner's narrower scope when implementation updates the backlog; the no-op push hook makes no ref-admission decision. The instruction to preserve existing enforcement until a separately tested correction is accepted remains in force (`AGENTS.md:11`).

Hosted quality already runs independently of admission. `quality.yml`'s tooling, trusted app/core and fork app/core jobs have no `needs: prior-release` (`.github/workflows/quality.yml:64–129`); the app aggregate waits only for the two runner alternatives (`:131–150`). This design preserves that dependency graph. It scopes the admission job's applicability; it does not propose removing a dependency that does not exist.

## Existing call graph and trust boundaries

| Entry / boundary | Verified calls and consequences |
| --- | --- |
| Commit | `pre-commit:9` → controller `main:626–630` → `verify_previous:402–430`. Then `pre-commit:11–28` rejects unstaged/untracked source, archives `git write-tree`, clears inherited Git environment for nested fixture repositories, tests that exact snapshot and rejects subsequent index/worktree changes. |
| Push / install | `pre-push:9` → the same gate, irrespective of destination. `install-release-hooks.sh:5–17` gates first, preserves a conflicting existing hook path and installs worktree-specific hooks. |
| Remote admission | `verify_previous:403–430` reads canonical main, verifies healthy public distribution, selects the latest Release excluding an explicitly supplied inspector, and requires exact source plus terminal success or exact verified Recovery. `GitHub.command:35–43` fails closed on unavailable requests. |
| Healthy-distribution proof | `verify_healthy_release:144–180` resolves public stable tag/source, manifest, publishing run/attempt, successful original build and final verification, exact asset hashes/sizes and appcast metadata. This metadata/hash proof relies on completed artifact validation; the actual signing and Sparkle checks are executed by `verify-dmg.sh:18–71`. Do not describe a plain gate invocation as a new cryptographic or native UI test. |
| Protected PR | `.github/workflows/quality.yml:20–62` currently runs admission for every non-main ref. It checks out trusted main, selects that controller or the exact pinned first-install fallback, and runs its existing `gate`. The owner's retained protection receipt verifies the main server boundary described below; this agent performed no remote inspection. |
| Main Release | `.github/workflows/release.yml:39–79` checks the push predecessor, excluding its own run, retains previous-distribution identity and classifies internal/app changes. Quality is invoked independently (`:81–82`); build waits on inspect and quality (`:86–88`). Internal-only classification is bounded and examines rename origins (`release-control.py:183–194`). |
| Publication | `publish-release.sh:15–21,35–76` checks main, creates a source/run-owned private draft, uploads, verifies the downloaded draft, rechecks main, publishes, anonymously verifies exact public artifacts/latest feed and rechecks main. The failure trap withdraws only the owned release. `release-control.py:560–602` verifies ownership, manifest/source/attempt/assets, latest feed and downloaded signed DMG when appropriate. |
| Terminal completion | `release.yml:349–401` requires inspect/quality/build/public success as appropriate, rechecks exact main, and retains source-verification evidence. An internal tooling revision can complete without creating an app release; this does not excuse app-source changes. |
| Recovery | `recovery.yml:18–20` shares the non-cancelling Release concurrency group; `:35–47` invokes `recover` and retains the exact record. `recover_release:433–474` refuses active/superseded runs or advanced main, withdraws owned partial publication, verifies the previous healthy distribution and rechecks main. `verify_recovery:204–231` binds completed Recovery, verified job, failed run/attempt/SHA, healthy tag/SHA and record/run identity. |

The repository policy identifies `iRedlof/Glimpse` (`.github/release-policy.json:2`), and the inspected workflows/documentation establish `refs/heads/main` as the protected integration target. This investigation establishes no additional protected branch list. Inventory establishes one macOS release line, a shared Core package and an externally operated proxy; it does not justify inventing another deployment target (`docs/product-inventory.md:9–15,27`).

The owner's live read is retained at `/Volumes/xHome/Github/Glimpse/build/validation/screen-fit-delivery.qojis70m/current-main-protection.json`, timestamp `2026-11-02T06:37:24.996508+00:00`, exit 0. It records strict `App and core tests`, `Release tooling checks` and `Previous release verified`, each bound to GitHub App 15368; administrator enforcement; required PRs with zero required approvals; linear history; conversation resolution; no force pushes or deletion. This establishes the recorded settings at that time, not every possible ruleset or external actor's capabilities. Repository review remains required even though the server's approval count is zero.

## Smallest bounded correction

### 1. Keep local commit quality; remove remote admission

Delete only the remote gate call from `pre-commit`. Retain the source staging requirement, index archive, repository-environment isolation, full quality command and post-test mutation guard. This applies even when the local branch is named main: creating a local commit does not integrate or publish it.

Do not add an environment-variable bypass, cached release success or network-dependent informational query. Missing/offline GitHub must not prevent reaching local quality. A local dependency-fetch failure can still fail local quality; this correction removes the release-health dependency, not actual test prerequisites.

### 2. Remove local push admission

Retain the tracked `pre-push` as a trivial, documented successful no-op. Remove the remote gate and its now-unneeded build/temp setup. Keeping the file avoids changing the installer's hook-file contract and permits existing checkouts to update through ordinary tracked-source delivery.

The hook does not inspect branch names, destination refs, remote URL owners, forks, batches, SHA sentinels or tag names. It makes no admission decision and needs no push-protocol parser. A direct main push is rejected by the server's required-PR protection, not a duplicate client policy. Ordinary branch pushes therefore reach the existing server/quality behavior during pending, failed or offline distribution health; an actually unavailable push destination can still prevent Git's transport.

Do not add a cached success, bypass environment variable or informational distribution query. Existing Release-owned publication continues unchanged. No new client or server tag restriction is introduced.

The pre-commit quality hook remains a checkout-local safeguard; client hooks are not server security authority. Do not weaken protected PR policy or adopt a bypass to deliver this correction.

### 3. Scope hosted admission to protected-main PRs

Change only the `prior-release` job applicability to PR events whose base repository is canonical `iRedlof/Glimpse` and whose base branch is main. Use GitHub's canonical event/base-repository identity, not a local remote URL. Preserve the check name `Previous release verified`, trusted-controller checkout, immutable first-install fallback checks, read-only permissions and invocation of the existing `gate`.

Ordinary feature pushes and PRs targeting an ordinary development branch do not need this job. Canonical-main PRs from forks do need it, but the controller must remain trusted main's. Keep fork app/core execution on a disposable macOS runner and same-repository execution on the existing runner. Keep tooling/app jobs independent of admission so a failed main release still yields useful source-quality evidence.

Do not remove required checks, reduce permissions safeguards, introduce `pull_request_target` execution of untrusted source or rename the three existing required check names. A stale PR remains blocked by strict server up-to-date protection and the owner's current head/base checks. Verify that the required admission actually executes for canonical-main PRs, rather than reporting a skipped outside-boundary check as main admission.

### 4. Preserve current gate compatibility and observed merge-time freshness

No controller command or admission-wrapper change belongs in this iteration. `quality.yml:33–58` loads trusted main's controller, whose current command choices (`release-control.py:607`) include `gate` and do not include `admit-integration`. Calling a newly introduced command while evaluating the same PR that first introduces it would deadlock required admission. Do not resolve this through the PR controller, broader bootstrap fallback, skipped check or hook bypass.

Retain `gate --expected-sha ... --ignore-run-id ...` predecessor semantics (`release.yml:45–48`). The proposed condition change continues to call the already-trusted `gate`, so it can enter main through ordinary protection without a controller rollout dependency.

At the owner's authorized ordinary merge boundary:

1. Verify the current exact PR head, current main/base relation, resolved findings and all three required check results.
2. Run the existing trusted `gate` freshly for current main, retaining its exact accepted Release/Recovery and distribution evidence.
3. Explicitly re-read current main and current Release run/attempt/status; where Recovery supplied admission, recheck the relevant Recovery identity. If source/run evidence changed, became active or is unavailable, pause integration and refresh validation.
4. Request the ordinary expected-head protected merge only with current passing evidence, and retain actual terminal exact-main Release/Recovery/public verification afterward.

These are the owner's coordinated operational checks, not a new automatic admission command or stronger hosted workflow contract. The existing `verify_previous:402–430` has no final main/run re-read; passing an expected SHA or obtaining a successful gate exit alone does not prove all identities stayed unchanged through return.

A fresh query and explicit observations do not make merging atomic. Manual Release dispatch/reruns at unchanged main do not invalidate an already-green PR check (`docs/release-automation.md:151–156`). Preserve the existing coordinated merge pause during those operations and refresh admission afterward. This design makes no absolute freshness or server-lock claim.

### 5. Remove installation deadlock and update operational language

The installer must be usable without distribution admission; remove its first remote gate while retaining the existing conflicting-hook-path refusal, worktree-specific configuration and both tracked hook-file executable contracts. Do not migrate checkouts by manually disabling hooks.

Update installer output, `docs/release-automation.md:119–156,197–210`, the Release queue comment (`release.yml:13–14`) and the publication withdrawal error (`publish-release.sh:28`) so they describe blocked integration/promotion rather than all commits/pushes. Update current AGENTS/backlog wording when the accepted implementation actually passes. Historical delivery plans may retain their dated policy, explicitly identified as historical.

No marketing/build bump is needed for this internal-only tooling change; preserve all four versions/builds, README and readiness consistency. Existing Release classification still decides whether app publication is necessary.

## Recovery and remediation remain scoped

Pending release, failed Recovery or unavailable distribution evidence closes canonical main integration and promotion. It does not prevent preparing, testing, committing or pushing a remediation branch.

After a failure, run the existing Recovery for that exact failed main run and wait for terminal success, `recovery-verified`, the matching failed run/attempt/SHA record and verified restored public distribution. Only then may a current, reviewed, quality-valid remediation PR enter main. Re-running the original failed Release remains the existing transient-failure path.

Do not add “internal-only emergency” admission while Recovery is unverified. Current `internal_only` is a publication classifier, not authorization to weaken security or workflow controls. Recovery must preserve another run's release, retained tags/assets, source history and signing credentials. A tag already created by a failed publication requires the existing new-version/build behavior; same-version draft handoff remains limited to a proven empty, private, tagless draft, exact failed owner/Recovery and internal descendant (`release-control.py:271–327`).

If existing Recovery itself cannot operate, preparation and independent development continue. Changing production state, protected-branch rules or installing an emergency trusted recovery mechanism is a separate authorization boundary. Do not create a broad “recovery” flag to resolve it.

## Existing coverage and required regressions

Existing coverage was inspected, not executed.

| Existing evidence | What it establishes / gap |
| --- | --- |
| `test_release_hooks.py:60–84` | Staged snapshot repository isolation, index mutation rejection, unstaged-source rejection and quality success/failure. Preserve these behaviors. |
| `test_release_hooks.py:86–108` | Both hooks currently reject offline GitHub. Replace this old global-policy expectation with local independence cases. Main denial remains a hosted/server admission contract. No installer coverage was discovered. |
| `test_release_control.py:173–248,312–346` | Pending/failed/stale source, missing verification, asset/manifest/attempt/digest mismatch and network failure remain fail-closed admission contracts. |
| `test_release_control.py:398–519,532–620` | Exact bootstrap identity, revocation, verified Recovery, pending/wrong-source Recovery, internal/app distinction, active-recovery refusal and bounded compare/rename behavior. Historical bootstrap fixtures remain important even though current policy has no legacy-recovery exception. |
| `test_source_revisions.py:64–87,230–258` | Every introduced revision and PR merge result are checked; a bad intermediate source/tooling/monitoring/version/pin revision cannot hide behind a green head. Preserve this requirement. |
| `test_quality_gate.py:97–198` | Private cleanup, durable evidence, unsigned fixture build contracts and archived lockfile-mutation failure. Do not replace exact-source quality with a hook-only smoke check. |
| `test_publish_release.py:204–261`, `test_draft_identity.py:93–297` | Partial uploads, corrupt/unsigned artifacts, public-health failure, main advancement, draft/run/source/recovery ownership and race failures cannot promote. Keep publication/draft contracts intact. |
| `.github/workflows/quality.yml:80–150` | Fork runner separation exists in source. No behavioral admission event/base/fork matrix tests were discovered; add focused workflow contract coverage. |

| Required regression / validation | Expected bounded result |
| --- | --- |
| Commit independence | Missing `gh`, pending/failed Release and offline API never invoke admission; a valid staged snapshot reaches local quality. Failing quality, unstaged/untracked source and index/worktree mutation still reject the commit. Record zero distribution queries. |
| Push independence | The retained no-op succeeds without distribution queries for ordinary invocation and empty/non-empty stdin, independent of missing `gh` or pending/failed/offline health. No ref parser, alias resolver, protected-ref or tag-policy test suite is introduced. |
| Installer safeguards | Offline fixture installation succeeds without admission; conflicting hooks are preserved; repeated installation is safe; worktree configuration does not take over another checkout. Fixtures preserve both tracked executable hook paths. |
| Hosted event/base/repository matrix | Ordinary push, reusable main Release quality and development-base PR do not execute prior-release admission. Canonical-main PRs, including fork heads, do execute existing trusted admission. Another repository's main is not canonical admission. Preserve independent app/tooling jobs, fork runner separation and aggregate result semantics. |
| Trusted caller compatibility | Every command called by the changed workflow exists in the trusted controller version evaluating that PR. The admission call remains `gate`; immutable first-install fallback and predecessor semantics remain unchanged. |
| Main admission failure | Existing gate fixtures still reject unavailable, pending, failed/unrecovered or wrong-source evidence. The eventual integrating owner observes the required canonical-main PR check executing and rejecting unhealthy/unavailable evidence; skipped or merely named checks do not establish this. |
| Recovery/publication preservation | Keep exact failed run/attempt/SHA/healthy identity, active/superseding-release refusal, shared non-cancelling concurrency, original build/attempt, draft ownership, public-feed and signed-artifact contracts. Preparing/committing/pushing a remediation branch does not need Recovery, while main integration still does. |
| Ordinary protected merge procedure | Retain current server protection receipt; refresh exact PR head/base, root gate and explicit current main/run observations before the ordinary expected-head merge. Record manual-rerun merge pause and no atomic freshness claim. This is operational evidence, not a new wrapper regression suite. |

Implement fixture tests with fake GitHub and temporary repositories; do not exercise real hooks/configuration, signing, UI, production signals or remote mutation during development. Run focused Python contracts and shell syntax first. The eventual integrating owner must then run the ordinary whole exact-source quality and protected hosted/Release validation required by the repository; this design supplies no substitute for those results.

## Acceptance

| Boundary | Required evidence |
| --- | --- |
| Local development | Commit, push and installer make no distribution request. Staged snapshot quality/mutation and installer collision/isolation safeguards remain intact. No cached admission or bypass switch exists. |
| Hosted quality | Existing app/tooling independence remains; forks use the disposable runner; canonical-main PR admission executes trusted main's existing gate under the unchanged required check name. |
| Main integration | The recorded server-protected required-PR/check policy is preserved and refreshed before adoption. Owner verifies exact head/base, fresh gate and explicit main/run rechecks at ordinary protected merge time. Unhealthy/unavailable admission denies integration. |
| Promotion and Recovery | Existing exact source/version/readiness, build/attempt, signed/notarized/Sparkle/public feed, ownership, terminal completion and Recovery identity controls remain enforced. |
| Remediation | Branch preparation and source quality continue independently; main integration follows exact proven Recovery or the existing verified success path. No broad emergency exception is added. |
| Freshness limits | Unchanged-main manual reruns retain coordinated merge pause and refreshed admission. Neither static green checks nor explicit observations are claimed to be atomic. |
| Review and evidence | Bounded fixtures, caller compatibility, workflow review and ordinary whole-source/hosted/terminal validation pass before acceptance. Reports distinguish fixtures, hosted outcomes, cryptography and native validation. |

## Migration and delivery

| Stage | Required action / consequence |
| --- | --- |
| Implementation planning | Prepare the separate bounded tooling plan after panel delivery. Preserve current enforcement. Only hooks, installer, admission condition, focused contracts and corresponding operating language need changes; no controller API change is required. |
| Correction's own protected PR | Deliver through current ordinary hooks and existing trusted admission. Its hosted condition still calls the command already available on trusted main, avoiding the builder's rollout deadlock. Do not execute PR controller code or relax the pinned fallback. |
| Exact-main acceptance | Run ordinary full exact-source quality and verify protected hosted checks and terminal exact-main Release/Recovery evidence. Existing internal-only classification may complete the tooling revision without publishing an app release. Preserve version/readiness consistency. |
| Existing checkout update | Checkouts whose worktree-specific hook path points at tracked scripts acquire the no-op push hook and corrected commit hook when their source updates. Confirm each checkout; older/archived worktrees and custom hook integrations do not automatically migrate. |
| New installation | Installer can proceed without GitHub distribution health, preserving custom-hook refusal and worktree isolation. Do not overwrite custom hooks or manually disable enforcement. |
| Operating documents | Align current AGENTS/backlog and release documentation with local quality plus server-protected admission. Remove parser-oriented acceptance for this scope and global commit/push-block language. Leave dated historical plans explicitly historical. |
| Protection continuity | The owner refreshes the supplied read-only protection receipt and verifies required canonical-main PR admission still runs after the condition change. No ruleset/check binding, bypass, runner or tag policy change is part of migration. |

This design's document revision is the only mutation in this task. The eventual implementation requires its own focused tests, independent review and normal delivery evidence; none is asserted here.

## Deferred architecture options and authorization limits

The client push parser, remote identity classifier and new tag restrictions from the earlier proposal are removed from this iteration. They are unaccepted architecture/policy options, not hidden acceptance requirements. The owner has verified origin `https://github.com/rlchandani/Glimpse.git` redirects to canonical `iRedlof/Glimpse`; unequal owner spelling cannot prove a fork. Eliminating client classification avoids imposing an alias-policy migration. If identity classification is ever justified separately, it must use verified stable repository identity/canonicalization or explicit trusted aliases without credentials exposure.

A stronger freshness wrapper is deferred to a separately scoped controller-first change: first introduce and test a compatible command through an ordinary protected delivery while the workflow still calls `gate`; verify that exact main's terminal Release outcome; only then deliver a second PR whose workflow consumes the now-trusted command. Preserve predecessor semantics and tie observed identities to the evidence actually accepted by verification. No new wrapper, workflow invocation or manifest schema is accepted here.

A dynamic coordinator or administrator-managed lock could enforce stronger unchanged-main operation controls, but needs separate scope and applicable authorization. Live additional rulesets, external actor capabilities, fork permissions and runner administration are not exhaustively established by the supplied branch-protection receipt. Remote settings changes, expanded production Recovery actions or emergency trusted-policy installation remain separate boundaries. Existing authorized Release/Recovery operations do not imply permission to alter those policies.

The external proxy, app behavior and original other-device/restart reliability limits remain unaffected. Current panel delivery continues under its current accepted plan; this next tooling iteration must not be used to bypass that delivery.
