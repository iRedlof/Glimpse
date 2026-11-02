# CD-01 fresh builder review

Design review only, 2026-11-01. **Important contradictions remain in the proposal as written.** The correction is suitable for bounded implementation-plan preparation once the unnecessary client policy expansion is removed and the trusted-controller rollout is made executable. This review neither accepts implementation nor authorizes delivery.

## Basis and review limits

Read the proposed design first, including its renamed-origin clarification; then the binding master goal, `AGENTS.md`, `CLAUDE.md`, and the applicable A1–A8 review checklist. The master goal requires independent development to continue through release failures while retaining integration, promotion, and deployment gates.

The supplied protection evidence, `build/validation/screen-fit-delivery.qojis70m/current-main-protection.json` in `/Volumes/xHome/Github/Glimpse`, records a successful read at `2026-11-02T06:37:24.996508+00:00`: strict required `App and core tests`, `Release tooling checks`, and `Previous release verified`, all bound to GitHub App 15368; administrator enforcement; required PRs with zero approvals; linear history; resolved conversations; no force pushes or deletion. That is evidence of those settings, not an inventory of every possible ruleset or external actor.

Source checks were limited to the load-bearing questions: the hook/installer calls, admission workflow and CLI compatibility, existing predecessor semantics, and current admission/rollout documentation. No panel implementation files were inspected. No tests, builds, UI, installation, signals, remote actions, secrets, or production changes were performed.

## A7 — scope and architecture findings

### 1. Remove the proposed push parser and tag-policy expansion from CD-01

The proposed parser duplicates part of a server-protected PR integration boundary while introducing destination parsing, sentinel/ref validation, ancestry checks, remote canonicalization, rename policy, fork identification, batch semantics, and a new publication-tag prohibition. Its complexity is disproportionate to removing a global development lock. Client admission remains bypassable and cannot repair the acknowledged unchanged-main rerun race.

The smallest defensible correction is:

- Remove remote release admission from `pre-commit`, preserving its complete staged-source quality and mutation checks.
- Remove remote release admission from `pre-push`; retire the hook or retain a trivial documented no-op, with the installer kept consistent.
- Remove the installer's remote gate while preserving custom-hook refusal and worktree-specific configuration.
- Scope the existing required hosted admission to canonical-main PRs, preserving its name, trusted controller, permissions, and independent quality jobs.
- Preserve the ordinary protected merge procedure and all Release, Recovery, and public-artifact gates.

A rejected direct main push should remain the server's decision. Local branch names, ref batches, SSH aliases, and a remote URL's owner spelling need not become a second authority system. The verified rename from `rlchandani/Glimpse` to `iRedlof/Glimpse` is real coordination evidence; unequal owner names are not fork evidence. Eliminating the classifier also eliminates the need to encode that rename into new client policy.

Do not introduce version-tag prohibitions as part of this correction. They are explicitly unaccepted policy additions. Preserving the existing Release-owned publication procedure does not establish new server-side tag protection, and the implementation must not claim otherwise.

The design's acceptance requirement for malformed push input and the roadmap's parser-specific cases must be revised with this scope decision. A hook that makes no admission decision need not validate Git's push protocol.

### 2. The new trusted admission command cannot be introduced and consumed in one ordinary PR

This is a concrete rollout contradiction, not a hypothetical test concern:

- `quality.yml:33–58` checks out trusted main, then selects its controller. The immutable bootstrap fallback applies only when the controller file is absent.
- The current controller's command choices at `release-control.py:607` do not include `admit-integration`.
- The proposed workflow would invoke that new command from trusted main while evaluating the very PR that first adds it.

That required check would fail before the new controller could enter main. Do not resolve this by executing the PR's controller, loosening the fallback, skipping the check, or using a hook bypass.

**Recommended bounded choice:** deliver the boundary correction using the existing trusted `gate` and the existing coordinated fresh check at ordinary merge time. Document its current freshness limits. Treat the stronger observation wrapper as a separately scoped enhancement.

If the wrapper is retained as a CD-01 requirement, explicitly use two protected deliveries: first add and test the compatible controller command while the workflow still calls `gate`; after that exact main source completes its required Release verification, update the workflow to invoke the now-trusted command. The plan must name this dependency and preserve `gate --expected-sha ... --ignore-run-id ...` predecessor behavior.

### 3. State freshness at the boundary actually enforced

Fresh trusted admission remains required for canonical-main PRs and immediately before the orchestrator's ordinary protected merge. Retain exact PR head/base and required-check verification. The existing `gate` queries current distribution and run evidence; its optional expected SHA does not by itself prove that main and all run identities remained unchanged through return.

The proposed before/after wrapper can strengthen observed freshness, but cannot make a static green check or a subsequent merge atomic with a manual dispatch/rerun. Preserve the existing coordinated merge pause during unchanged-main Release operations and refresh afterward. A dynamic coordinator or administrator lock is separate scope and authorization.

If implementing the wrapper later, tie the reported run/attempt/Recovery identities to the evidence actually accepted by verification; independently captured identities alone are insufficient. Do not change the publication-manifest contract merely to report admission observations.

## A8 — bounded verification expectations

For the smaller correction, retain focused fixture coverage for:

- Quality-valid staged commits reaching local quality without `gh` or any distribution request, including pending/failed/offline scenarios; quality failures, unstaged source, and index/worktree mutation still reject commits.
- Ordinary pushes and offline installation making no distribution query; installer conflict preservation, repeated installation, and checkout isolation.
- The hosted event/base/repository matrix: canonical-main PRs, including forks, execute required trusted admission; ordinary pushes and development-base PRs do not require it; independent app/tooling work and fork runner separation remain.
- Preservation of existing exact Release predecessor, Recovery identity, non-cancelling concurrency, draft ownership, and public artifact contracts.
- A rollout test or explicit compatibility check showing every workflow command exists in the trusted controller version that will evaluate the PR.

Do not build parser, alias-resolution, unsupported-ref, or tag-policy test suites for behavior removed from scope. Do not report a skipped outside-boundary check as main admission. The integrating owner must verify the required hosted main-PR check actually runs and rejects unavailable/unhealthy evidence; named status checks alone are not a substitute for this behavior.

The eventual implementation still requires ordinary exact-source quality and protected hosted/terminal Release verification. None was run or supplied by this review.

## Remaining checklist and decision

A1–A3, A5–A6: no app behavior is proposed or reviewed. A4: preserve the existing signing, Sparkle, public-feed, and downloaded-artifact gates; no new artifact-security claim is made here. A7–A8 findings are above.

The owner can resolve the remaining choices without a broad product discovery exercise: adopt the smaller hook/installer removal, omit new client/tag policy, and either defer the wrapper or specify its two-delivery rollout. With those explicit revisions, **ready for bounded implementation-plan preparation**. Current enforcement remains active until the separate correction is accepted and delivered through the existing process.

## Scoped recheck of revised design

Rechecked only the three findings above against the revised `next-delivery-boundary-design.md`. No broader discovery, source reads, tests, code/configuration changes, remote/UI actions, or agents were used.

- **A7.1 — ADDRESSED.** “Remove local push admission” now retains a trivial documented no-op, removes all client ref/remote classification, and introduces no tag restrictions. The revised regression, acceptance, and migration sections consistently remove parser-specific obligations while retaining staged quality, installer safeguards, and server-protected trusted admission.
- **A7.2 — ADDRESSED.** “Preserve current gate compatibility” leaves the hosted caller on trusted main's existing `gate` and makes no controller API change. The stronger wrapper is explicitly deferred; its future controller-first, two-delivery dependency is documented. The correction no longer needs a command unavailable in the controller evaluating its own PR.
- **A7.3 — ADDRESSED.** The revised merge procedure distinguishes owner observations from automatic enforcement, retains the coordinated pause for unchanged-main manual dispatch/reruns, requires refreshed admission afterward, and expressly disclaims atomic freshness. A dynamic coordinator or administrator lock remains separate scope.

No new load-bearing contradiction was identified in those revised sections. **Ready for bounded implementation-plan preparation.** This verdict supersedes the earlier design-readiness reservation only; it is not implementation acceptance, evidence that tests passed, or authorization to bypass current delivery enforcement.
