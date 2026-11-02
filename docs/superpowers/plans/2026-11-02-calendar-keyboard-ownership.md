# Calendar Keyboard Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement inline. Root owns later independent review/release; do not spawn agents or commit.

**Goal:** Give the stable calendar grid safe local keyboard ownership while retaining native date actions and normal browse behavior.
**Architecture:** Stable SwiftUI editing-focus grid and separate logical date; intrinsic fixed Button focus, local callbacks/native editor onSubmit, guarded existing browse monitor and read-only FocusedValue hierarchy.
**Tech Stack:** Swift6, macOS14+, SwiftUI/AppKit/TCA, current15 immutable matching pins.
**Spec:** docs/superpowers/specs/2026-11-02-calendar-keyboard-ownership-design.md

## Global Constraints

No new native windows beyond owned fixtures, activation/global posting/monitors/timers/installed app operations; no private settings/calendar/network. Preserve previous uncommitted probes/workspaces and immutable Phase1/Phase2 evidence. No commit/push/version/full quality. Local DD, unsigned arm64 Debug, skipMacroValidation, parallel testing NO,30s tests,1200s wrapper; exact-source receipts external.

## Review Focus

Requested focus vs actual owner; stale owner withdrawal; open AI draft while grid/header focused; exact normal-open ownerless browse; native Tab reverse/currentEvent fidelity.

Earlier implementation sections below preserve their original stage checklists and hypotheses as historical records. Their later accepted outcomes are recorded in the final acceptance section; unchecked historical entries do not describe the current candidate.

### Task1: Prove production-root RED and deterministic routing contract

Files: GlimpseTests/CalendarKeyboardOwnershipTests.swift; test-project registration. First native assertions exercise real root actions with owned queue delivery, not AX actions. Write routing expectations before implementation; an unavailable API/compiler correction is excluded infrastructure, then minimal interface scaffold must reach behavior RED.

- [x] Write normal-open browse and queued forward grid/Space real-root tests; guards/currentEvent/cleanup and literal expected dates/actions.
- [ ] Run bounded actual selectors. Expected: browse baseline retained; date local-focus mechanism fails before implementation. Preserve logs/xcresult/source/process receipt.
- [x] Write pure CalendarKeyboardRouterTests covering ownership/guard/repeat/modified/anchor boundaries. API absence excluded; minimal stub then executed12 names/46 expectation failures before minimal logic.

### Task2: Implement accepted local ownership

Files: Glimpse/CalendarKeyboardRouter.swift; CalendarPopoverView.swift; CalendarPanel.swift; AppDesign.swift; scoped swiftui rule; necessary project registration. No Core change.

- [x] Implement policy/anchor logic to pass deterministic RED.
- [x] Grid editing-focus wrapper, actual environment ring and readonly owner publication; fixed native Buttons with local activation handlers; explicit Space once/repeat suppression and the Today enabled guard subsequently passed their bounded native/policy checks; native editor submit exclusively. Coherent modifier-chain correction preserves one grid.
- [ ] Existing monitor guards CmdG/Escape and positively ownerless browse; exact window-default reopen responder, immediate freshness gate. Existing editor activation seam retained/injected for owned acceptance, no new activation/timer.
- [x] Run deterministic focused GREEN. All12 selected routing/anchor names pass; no native acceptance inferred.

### Task3: Gate mechanism at actual root

Files: CalendarKeyboardOwnershipTests.swift and owned fixture utilities only.

- [ ] Run actual queued production-root tests including immediate anchor/action, normal browse, hierarchy publication/withdrawal and both traversal directions. Expected native action/currentEvent/owner receipts match actual scope; preserve RED if premises fail.
- [ ] Run affected input/date AX/viewport/scroll/recorder/reopen regressions after source is stable. Expected selected regressions pass; no full gate.
- [ ] Check source/index/HEAD/pins and owned process absence; write recommendation with raw failures and exhaustive rulings. Do not claim release-ready if native bridge/traversal/browse gate fails.

Historical evidence before the accepted lifecycle correction: actual queue-delivered root was 6 methods/9 issues after the documented BackTab fixture correction. Native immediate grid Right→Space and reverse target action/currentEvent pass; immediate hierarchy remains delayed and hidden reopen breaks browse. The original failed assertions remain; external mechanism-report.md is the bounded handoff for independent bridge/lifecycle review. No new production correction or unchanged native retry before source-supported adjudication. Affected regressions remain required after architecture stabilizes.

### Authorized lifecycle correction after independent review

- [x] Freeze original coherent and shift-preserved source/results; acquire before identity excluding ProxyConfig entirely.
- [x] Keep all original immediate Tab sequences; add exact per-event owner/key/phase/route/count/owned currentEvent/responder checks and actual action/date checks. Measure cached publication separately.
- [x] Add optional stable controls/grid focus binding used for lifecycle dismissal only; coordinate existing editor binding. Owned reset precedes native post-key reset.
- [x] Add CalendarPanel.completeReopenPresentation Boolean/default-responder verification and explicit hidden CalendarStatusItem call. Notify successful completion only to request real hierarchy observation; preserve visible Show and previous-app restoration.
- [x] Execute one bounded actual-root suite; capture completion Boolean, before/after/currentEvent receipts, actual selectors, raw failures and process absence. No broadened browse fallback or extra mechanism attempt.
- [x] Reconcile result with R1–R4; source identity/pins preserved; remaining native product gates explicit.

### Canonical15 bounded acceptance extension

- [x] Root canonical reconciliation receipt read;16 files byte-exact except versioned pbx merge, stash/index/artifacts preserved.
- [x] Write six meaningful wiring/lifecycle functions using the existing owned queued dispatcher, plus repeat/modifier/peer metadata and read-only rendering/submit/completion receipts.
- [x] Add only necessary UI boundaries: editor presentation/query-submit spy and injected preferences hotkey model; original installed defaults unchanged, no service refactor/activation/timer.
- [x] Remove four obsolete prototype project registrations; retain source/docs/evidence.
- [ ] Receive runtime allocation, execute exact opt-in suite on canonical15/local DD/pins/unsigned arm64/serial30s/1200s controls; retain actual parameter IDs/counts, raw failures and process absence.
- [ ] Only source-supported failure diagnosis/correction under TDD; no unchanged retries or narrower acceptance.
- [ ] Supply final native method/case IDs to tooling owner and run affected meaningful regressions after wiring stabilizes.
- [ ] Root independent review/integration/release; no commit/full gate/version/index/ref changes by this owner.

### Bounded explicit fixed-control Space follow-on

- [ ] Retain actual policy RED and minimal Space implementation/editor run as exact historical evidence; no failed temporary yield probe relabeled GREEN.
- [ ] Add explicit default-enabled local policy input/Today argument and ignored-input scaffold solely to reach meaningful disabled-policy RED; then enable the guard and verify pure GREEN.
- [ ] Add heldHeaderSpaceActivatesOnceAndConsumesRepeat plus todayBecomingDisabledHasNoExtraTodayAction. Each is one actual-root owned case; current12/14 becomes proposed14/16, requiring tooling-owner manifest reconciliation before routine gate.
- [ ] Keep editor behavior body unchanged except Space contract comment; run actual prompt/editor lifecycle after approval.
- [ ] Measure disabled Today callback or valid native withdrawal without requiring retained focus or fabricating an owner. No missing-callback proof; no extra Today action from Space while disabled; another actual enabled owner may act normally.
- [ ] Record local phase/owner/route/window/currentEvent/actions after full down/up/repeat pairs; preserve private-DD/locked/unsignedarm64/serial30s/1200 boundaries and remaining physical/VoiceOver/olderOS/ring/viewport limits.

### Disabled fixed-control dispatch correction

The default-enabled scaffold produced actual30-issue disabled-policy RED, then its Boolean guard passed the whole pure13-method/33-case suite. Held-header fullpair Space/repeat immediate and settled counts passed. The first Today case missed its positive owner; one existing render settlement established Today Return, after which disabled Today Space/down and repeat callbacks yielded while fullpairs increased Today actions1→2→3 (actual1-case/2-issue RED). These results remain immutable.

The revised policy consumes only eligible disabled fixed-control activation down/repeat without action; editor, suppressed contexts, key-up/nonactivation and disabled grid still yield. The updated existing pure method produced exactly30consume RED issues at unchanged Router, with all pass-through boundaries passing. The minimal guard split subsequently passed the combined whole Router plus Today run: 14 methods/34 cases. Physical keyboard, VoiceOver and older OS remain separate; focused ring/viewport acceptance was established later, and the whole quality gate is still pending.

### Final cleanup and isolated ownership acceptance

- [x] Preserve historical diagnostic sources and raw evidence outside the worktree; remove temporary drawing callbacks/readers, 40 stage markers and the two-method causal Button Space suite from delivery.
- [x] Retain the corrected ZStack focus parent, single focusable chain and preference; accept the focused logical date in the group label only while focused with a nonnil anchor. No required AXValue or VoiceOver announcement claim.
- [x] Preserve all original viewport keys, 42 date Buttons, known date/selection/action/frame/reverse/month/scroll identity assertions and six PNGs. Replace diagnostic AX reads with the guarded exact unique successful public label assertion.
- [x] Run the cleaned isolated ownership suite against the reconciled 14-method/16-case manifest, with the current collector/checker and seven integrated tooling paths frozen alongside all source, HEAD and pins. Retain actual metadata, raw warnings, PNG hashes and fresh owned-process absence. Stop on any failure; no unchanged retry.
- [x] Hand off clean source and full result for root independent review. Product/helpers/collector source accepted; the diagnostic-child checker correction and milestone documentation reconciliation are the recorded findings.
- [ ] Complete the separately reviewed metadata correction, root version/readiness and whole quality. Physical keyboard, VoiceOver and older-OS acceptance remain separate.

Historical bounded results remain unchanged: disabled consume policy plus Today passed 14 methods/34 cases; held-header explicit Space/repeat immediate and settled counts passed; focused-label viewport passed one method/two cases at 312/812. The full cleaned ownership suite has now passed all 14 methods/16 cases with zero failures/skips. The integrated collector passed with all six PNGs. The original metadata checker rejected the retained QoS runtime-warning child as a parameter execution. Its separately reviewed correction now accepts the exact saved 14/16 metadata while retaining the warning. The whole quality gate remains pending.
