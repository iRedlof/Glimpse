# CD-01 Delivery Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for authorized implementation, task by task. Steps use checkbox (`- [ ]`) syntax for tracking. The lead accepted the separate owner handoff under the autonomous master goal on 2026-11-02.

**Goal:** Allow quality-valid local development through pending, failed or unavailable release health while preserving server-protected integration and exact Release/Recovery/public verification.

**Architecture:** Remove remote admission from local hooks and installer, retaining exact staged-source quality and installation safeguards. Restrict hosted prior-release admission to canonical-main PRs and invoke trusted main's existing `gate`. Preserve the owner's fresh gate, explicit source/run observations and coordinated manual-rerun merge pause; no atomic freshness claim.

**Tech Stack:** Existing Bash hooks, Python standard-library `unittest` fixtures, Git worktree configuration and GitHub Actions. No dependency, app, controller API or release-manifest change.

**Spec:** [Revised design](../specs/2026-11-02-delivery-boundary-design.md). Read [builder review and scoped recheck](../reviews/2026-11-02-delivery-boundary-design-review.md), especially A7.1–A7.3 and A8. Its design verdict does not substitute for implementation/source/delivery acceptance.

**Status:** Owner handoff accepted from verified public v1.4.9/build16/main `7b1f18155f42007087733bed149ab0fc9cae6c58`, whole Release41415776521/2. Tasks1–3 are implemented with focused contracts passing; independent combined review, full exact-source quality and protected delivery remain pending. The installed v1.4.9 panel check remains pending independently; no startup/endurance/other-Mac result is inferred from delivery. Work uses `codex/delivery-boundaries` in the existing isolated managed checkout.

## Global Constraints

- Implement CD-01 as a separate tooling iteration from the verified v1.4.9 public delivery baseline. Continue safe local implementation while the lead completes the installed panel check; preserve that check as open. Any newly found critical app defect takes priority and can stop affected main integration without globally blocking independent preparation.
- Preserve pre-commit's exact staged tree archive, inherited-Git-environment isolation, mandatory whole-source quality, unstaged/untracked-source rejection and post-test index/worktree mutation guards.
- Remove distribution-health queries from `pre-commit`, `pre-push` and installer. Retain `pre-push` as a trivial successful no-op. Do not add a cache, bypass switch, client push parser, remote identity classifier or tag restriction.
- Canonical hosted admission is for PRs whose base repository is `iRedlof/Glimpse` and base branch is `main`, including fork heads. Preserve check names `Previous release verified`, `Release tooling checks` and `App and core tests`.
- Preserve trusted-main controller selection, immutable first-install fallback, read-only admission permissions, disposable fork runner and existing independent app/tooling jobs.
- Continue calling existing `gate`. Do not add or consume `admit-integration`; trusted main evaluating this PR does not expose that command.
- Preserve `gate --expected-sha ... --ignore-run-id ...`, exact Release predecessor, source/version/readiness, original build/attempt, draft ownership, signed/notarized/Sparkle/public-feed, terminal completion and Recovery identities.
- Preserve strict protected PR integration and owner expected-head merge with fresh gate plus explicit current-main/run rechecks. Pause merging during unchanged-main manual dispatch/reruns, then refresh admission. No atomic server-lock claim.
- Keep fixture Git/config changes inside temporary repositories only. Clear inherited Git repository variables and isolate fixtures from global/system Git configuration. Never install test hooks into the real checkout.
- Use no signing/private credentials, production data, native UI/installation, process signals, protection mutations or new infrastructure. Deferred identity/tag/freshness options are not acceptance requirements.
- This is internal tooling: no marketing/build bump. Preserve existing four marketing versions, four build numbers, README and readiness consistency; keep both immutable dependency graphs unchanged.
- Retain evidence outside tracked source. Red test iterations remain uncommitted; the owner creates only accepted source revisions after combined verification, because every introduced revision must pass quality.

## Review Focus

1. An editor changes the worktree or adds untracked source while quality runs: commit proof must be invalidated even when the index itself is unchanged — Task 1.
2. Existing custom hooks or a sibling linked worktree: offline installation must not overwrite or redirect the other checkout's hooks — Task 1.
3. Fork-head PR into canonical main: trusted admission must still execute, while untrusted app source stays on the disposable runner — Task 2.
4. Push, reusable Release quality or development-base PR: skipping admission must leave independent source checks intact and must never be reported as main admission — Task 2.
5. The correction evaluates its own PR using old trusted main: every called controller command must already exist, so admission cannot deadlock itself — Task 2 and owner rollout in Task 4.

## File map and ownership

One implementer owns the small tooling change set; do not overlap edits with panel workers.

| Files | Responsibility / current boundary |
| --- | --- |
| `tools/scripts/hooks/pre-commit:9,11–28` | Remove the one remote `gate` call; preserve the staged-source quality and mutation block. |
| `tools/scripts/hooks/pre-push:1–9` | Replace remote/build setup with a documented successful no-op; keep tracked executable hook path. |
| `tools/scripts/install-release-hooks.sh:5–17` | Remove remote gate, retain conflicting-hook refusal, worktree config and both hook executable checks; correct output language. |
| `tools/scripts/tests/test_release_hooks.py:13–108` | Extend existing local quality fixtures and replace the old “both hooks offline fail” policy test; add isolated installer contracts. |
| `.github/workflows/quality.yml:21–62` | Narrow only prior-release applicability. Keep existing trusted controller and `gate` invocation. Jobs `:64–150` remain independent with existing fork routing. |
| New `tools/scripts/tests/test_admission_workflow.py` | Focused event/base/repository matrix against the actual job condition, required trust/runner contracts and current CLI compatibility. Standard library only. |
| `AGENTS.md:11`, `docs/stability-roadmap.md:14,24`, `docs/release-automation.md:119–156,197–210` | Replace current global-development-block descriptions with local quality plus protected integration and scoped Recovery; retain manual-rerun limitation and dated history. |
| `.github/workflows/release.yml:13–14`, `tools/scripts/publish-release.sh:28` | Correct obsolete global-hook queue comment and withdrawal message only; no executable release logic change. |

Unchanged reference boundaries: `release-control.py` `verify_previous:402–430`, `verify_recovery:204–231`, `recover_release:433–474`, CLI `main:605–653`; Release inspect/build/final verification `release.yml:39–88,314–321,349–401`; shared Release/Recovery concurrency; `verify-dmg.sh:18–71`; exact-source `quality-gate.sh:20–43` and `test-source-revisions.sh:15–53`.

---

### Task 1: Remove local admission while preserving quality and installer safeguards

**Files:** Modify the three scripts and `test_release_hooks.py` above.

**Interfaces:** Retain existing hook invocation contracts and installer script path. Extend `ReleaseHookContracts.hook_fixture(staged, fail_quality=False, mutate_index=False, foreign_repository=False, *, admission_state="verified", mutate_worktree=False) -> tuple[subprocess.CompletedProcess[str], bool]`; preserve the current two return values. Fixture-only admission marker is available as `self.admission_marker`, with cleanup. For installer tests, use `make_installer_fixture(*, collision=False, linked_worktrees=False) -> tuple[pathlib.Path, pathlib.Path | None, dict[str, str], pathlib.Path]` returning target checkout, optional sibling, isolated environment and admission marker; `run_installer(root, env) -> subprocess.CompletedProcess[str]`.

- [ ] **Step 1: Extend the local fixture and write failing behavior tests.** A sentinel controller records any invocation and returns the requested pending/failed/offline status; quality is stubbed and records execution. Add `test_staged_commit_never_queries_distribution` across those states, and `test_staged_commit_does_not_require_gh` using a private PATH containing the fixture's required executables but no `gh`. Assert `result.returncode == 0`, `tested is True` and `self.admission_marker.exists() is False`. Replace `test_both_hooks_fail_closed_when_github_is_unreachable`; do not leave its obsolete global policy in history that must pass.
- [ ] **Step 2: Add preservation and installer cases.** Retain existing quality-failure, unstaged-source, index-mutation and inherited-Git-environment tests. Add `test_worktree_changes_during_quality_require_retest`: mutate tracked source or create untracked source without staging during the quality stub; assert nonzero exit and “Source changed during tests.” Add `test_pre_push_is_independent_of_distribution` for missing/unusable `gh`, empty and nonempty stdin: exit 0 and zero controller/network calls. Add installer tests `test_offline_install_and_repeat_preserve_hook_contract`, `test_existing_custom_hook_path_is_preserved`, and `test_linked_worktree_install_does_not_redirect_sibling`. Assert zero admission calls, correct worktree hook path/executable files, preserved collision state and unchanged sibling hook configuration.
- [ ] **Step 3: Run the focused tests before changing the scripts.** Run `python3 -m unittest discover -s tools/scripts/tests -p test_release_hooks.py -v`. Expected: the new independence cases fail because current scripts invoke admission; existing quality guards still behave correctly. Failures caused by a malformed fixture do not count as the expected regression.
- [ ] **Step 4: Make only the bounded script correction.** Delete `pre-commit`'s current line 9. Make `pre-push` a Bash no-op with a concise comment assigning admission to protected PR integration. Delete installer's current line 5, preserve lines 6–16 behavior, and print `Local quality hooks installed for this checkout: $ROOT`. Add no production Python helper.
- [ ] **Step 5: Run focused contracts and syntax checks.** Rerun the command from Step 3; require all tests passing, including the preserved quality/mutation cases. Run `bash -n` separately on pre-commit, pre-push and installer. Retain results in the iteration's ignored evidence directory; keep source uncommitted for combined review.

### Task 2: Restrict hosted admission without changing trusted caller or quality jobs

**Files:** Modify `.github/workflows/quality.yml:21–25`; create `test_admission_workflow.py`.

**Interfaces:** The job remains named `Previous release verified`; execution remains `python3 trusted-controller/tools/scripts/release-control.py gate`. Test helper `evaluate_admission_condition(expression: str, github: dict[str, object]) -> bool` evaluates the actual observed job condition with only equality, inequality, conjunction and field access needed by the old/new condition, using standard-library `ast` and rejecting unsupported constructs. Supply actual-shaped `github.ref` values for push and PR fixtures so pre-change failures prove wrong applicability, not an unsupported evaluator operator. Do not duplicate the production admission predicate as a separate Python function.

- [ ] **Step 1: Write a condition matrix using the actual configured `prior-release.if`.** Extract the job's single-line condition between the observed `prior-release` and `tooling` boundaries. Assert these exact cases; unknown/missing PR fields on non-PR events must short-circuit safely:

  | Event / repository / PR base / head | Admission |
  | --- | --- |
  | `pull_request`, canonical repository, canonical `main`, same-repository head | true |
  | `pull_request`, canonical repository, canonical `main`, fork head | true |
  | `pull_request`, canonical repository, canonical `develop` | false |
  | `pull_request`, another repository with its own `main` | false |
  | `pull_request`, inconsistent noncanonical base repository | false |
  | `push` on a feature ref | false |
  | reusable main Release quality with triggering `push` | false |
  | `workflow_call` context | false |
  | `workflow_dispatch` | false |

- [ ] **Step 2: Add load-bearing trust and compatibility tests.** `test_admission_uses_trusted_controller_and_existing_gate` verifies both trusted checkout selections, credential persistence disabled, existing pinned fallback, read-only admission permissions and observed command `gate`; confirm that command is among current CLI's declared choices without executing release operations. `test_quality_jobs_do_not_depend_on_admission` checks existing tooling/app/fork jobs have no prior-release dependency and aggregate needs remain the runner alternatives. `test_fork_execution_stays_on_disposable_runner` verifies the existing opposite head-repository predicates, fork `macos-latest` and same-repository runner boundary. These assertions protect integration behavior; do not snapshot unrelated YAML.
- [ ] **Step 3: Run the new focused contracts before changing the condition.** Run `python3 -m unittest discover -s tools/scripts/tests -p test_admission_workflow.py -v`. Expected: the matrix rejects current broad applicability; preservation/CLI cases pass. Use no YAML/evaluator dependency or installation.
- [ ] **Step 4: Replace only the job condition and its applicability comment.** Use one line: `github.event_name == 'pull_request' && github.repository == 'iRedlof/Glimpse' && github.event.pull_request.base.repo.full_name == github.repository && github.event.pull_request.base.ref == 'main'`. Preserve job/check name, trusted-controller steps, existing `gate` and all source-quality job dependencies and runner selection. Do not add new predecessor/current-source behavior.
- [ ] **Step 5: Run the focused contracts.** Require the matrix, trust boundaries, independence and caller compatibility passing. Retain evidence. Verify through review that no controller command, fallback, workflow permissions or runner behavior changed; keep source uncommitted.

### Task 3: Align current operating language with the accepted boundary

**Files:** Only the operating documents and two comment/message locations in the file map.

**Interfaces:** Documentation describes Tasks 1–2's behavior and existing `gate`, Release, Recovery and merge procedures. No new execution command or policy.

- [ ] **Step 1: Update current local-development instructions.** Explain exact staged-source commit quality, no-op pre-push, offline-capable installer, custom-hook collision/isolation safeguards and per-checkout migration. Remove global release-health commit/push-block claims. Update CD-01 acceptance to the bounded fixture matrix; remove parser/alias/tag obligations.
- [ ] **Step 2: Preserve protected delivery and recovery procedure explicitly.** Keep three required check names, strict protected PR integration, fresh owner gate/current head/base/run observations, exact failed run/attempt/SHA Recovery and unaffected signed/public terminal validation. Keep unchanged-main manual dispatch/rerun merge pause and refresh, without implying static admission is atomic.
- [ ] **Step 3: Correct the two obsolete descriptions.** Release concurrency comment should attribute ordinary main admission to protected PR integration, while preserving the shared non-cancelling group. Publication withdrawal failure should say integration/promotion remain blocked pending verified operator Recovery; preserve the error's visibility and `operator recovery is required` phrase used by existing contracts.
- [ ] **Step 4: Review current versus historical text.** Read the changed paragraphs and dated historical requirements together. Mark historical global-policy descriptions as dated where needed; do not rewrite old plans or unrelated product inventory. Verify no required-approval/protection/production-access expansion is asserted.
- [ ] **Step 5: Validate the affected message contract.** Run `python3 -m unittest discover -s tools/scripts/tests -p test_publish_release.py -v` once after the message change; require publication/withdrawal failures remain visible and ownership/public-source behavior remains unchanged. No prose-only tests are required.

### Task 4: Owner verification and separate protected delivery

**Files:** Retained evidence and accepted source only. This task is root-owned during the accepted execution handoff; preparing the design/plan alone supplies none of its delivery evidence.

**Interfaces:** Consume Tasks 1–3's passing receipts. Keep current trusted `gate` and server protection; no new controller API or protection setting.

- [ ] **Step 1: Independently review the combined change against A1–A8.** Concentrate on A7 policy/trust scope and A8 contract coverage; A4 confirms release/public controls unchanged. Verify no product changes, parser/tag policy, bypass flag, freshness wrapper or new permissions. Recheck that every command the modified PR workflow invokes exists on trusted main.
- [ ] **Step 2: Freeze, stage and identify the accepted source for owner integration.** Complete focused regressions and combined review, stage the accepted source, record the exact staged-tree/dependency identity and confirm no unstaged/untracked source remains. Prepare the configured external/ignored evidence root for the ordinary commit hook's retained logs and xcresults. Do not run a standalone whole quality command.
- [ ] **Step 3: Commit accepted source with the single mandatory full quality checkpoint and open the separate protected PR.** For this correction's own commit and push, the owner freshly runs trusted existing release admission before each operation to preserve the current delivery policy even if edited tracked hooks are already visible in that checkout. The normal mandatory pre-commit hook archives the exact staged source, runs full quality and enforces mutation guards; retain that run's source/dependency identity, complete logs and xcresults as the one local full checkpoint. Repeat full local quality only if new source or a failure requires it. Do not commit failing intermediate revisions, disable hooks or use `--no-verify`. Attach any created PR. Verify the separately required hosted introduced-source/head/synthetic-merge quality receipts; require actual executed canonical-main `Previous release verified`, tooling and appropriate app/core results. A skipped check outside this boundary is not main admission.
- [ ] **Step 4: Refresh protection and owner admission before ordinary expected-head merge.** Start with `/Volumes/xHome/Github/Glimpse/build/validation/screen-fit-delivery.qojis70m/current-main-protection.json` as prior evidence, not a permanent authorization cache. Refresh strict required checks bound to App 15368, PR/admin enforcement, linear history, conversation resolution and no force/deletion. Verify current exact PR head/base, fresh trusted gate and explicit current-main/Release-run/attempt/status observations; include accepted Recovery identity when relevant. Stop integration if those observations change or fail. Keep merge pause during unchanged-main manual dispatch/reruns.
- [ ] **Step 5: Verify actual terminal exact-main delivery and migration.** Internal-only tooling may require no app publication; verify the entire exact-main Release outcome and retained source identity anyway. If Release fails, keep preparation independent and use only existing exact verified Recovery before remediation integration. Verify public signed artifacts if publication occurs. Record checkout update/new-installer migration limits and update CD-01 status only from completed evidence.

## Handoff readiness and remaining limits

This plan covers the revised design's local quality/installer safeguards, hosted matrix/trust, caller compatibility, current-language migration, scoped Recovery and ordinary protected delivery. It defines four bounded deliverables and introduces no production helper or dependency.

The separate owner handoff is now accepted from verified public v1.4.9. Source line references are from the investigated tooling baseline and must be reconciled without broad product rediscovery. The retained protection receipt proves its recorded settings at its timestamp; later protection, external actors or additional rulesets require current evidence. Fixtures cannot establish actual hosted required-check execution, signed artifact acceptance or native health. The installed screen-fit interaction check remains open independently.

No automated atomic freshness guarantee is added. Stronger controller observations would require the deferred controller-first delivery before changing its trusted caller; dynamic merge locking and tag policy need separate scope/authorization. If current release evidence is unavailable, independent preparation continues while integration/promotion stays closed.
