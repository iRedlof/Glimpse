# UX-02 Actionable About Update Failures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give About persistent, actionable update failures while preserving Sparkle eligibility, callback ownership and existing installation behavior.

**Architecture:** Extend the existing MainActor `SparkleUpdater` and `InlineUpdateDriver`; inject a small app-local updater client and an awaited latest-result delay. About reads the same driver status, captures local choice identities in its controls, and delegates every update action to guarded methods. Production retains exactly one native updater.

**Tech Stack:** macOS 14+, Swift 6 complete concurrency, SwiftUI/AppKit, Observation, Combine, pinned Sparkle 2.9.4, Swift Testing in `GlimpseTests`.

**Spec:** [Accepted design](../specs/2026-11-02-update-retry-design.md), accepted SHA-256 `5d6d9faf27774a6bada859e363de7e1a4a0f94dfb671622bb7055f27dae729b9`; read the complete design, `report.md`, `builder-review-round1.md` and `root-design-acceptance.json` before execution. Root later copies this plan and the accepted design to `docs/superpowers/plans/2026-11-02-update-retry.md` and `docs/superpowers/specs/2026-11-02-update-retry-design.md`, updating this reference together.

## Global Constraints

- Planning only now. Execution order is **UX-01 verified delivery → CD-01 → UX-02 implementation**. This plan is not evidence that either prerequisite has completed.
- Preserve the macOS 14.0 deployment target, Swift 6.0 and `SWIFT_STRICT_CONCURRENCY = complete`; preserve both equal 15-pin graphs, including Sparkle 2.9.4 at `b6496a74a087257ef5e6da1c5b29a447a60f5bd7`.
- Keep the existing native About layout, shared MainActor updater/driver, installation choices, privacy behavior, HTTPS feed and EdDSA verification, test-host startup guard, and both locked dependency graphs.
- No automatic retry, updater replacement, background-check override, new dependency/global state framework, release control, settings change, automatic download/install choice, or unrelated UI work.
- Initialization failure is terminal for this launch: one start attempt, no Check/Retry or repeated start. Runtime Retry uses the same successfully started updater.
- One predicate gates both presentation and activation: successful initialization, Sparkle eligibility, no owned update/install choice, and idle or runtime-error status. Activation refreshes eligibility from the live client first.
- Keep existing eligibility observation; never initiate a check from its observer. No session subscription/cache, separate admission flag, `showUpdateInFocus`, or global exclusion of deferred/downloaded/installing update resumption.
- All status, callback, identity and timer mutations occur on MainActor. `.checking` is published synchronously before calling the native check.
- Error publication retains pending replies; native dismissal retires them without invoking them. Consume a valid user choice once, retire it before invocation, and make no old-state writes after invoking it.
- Use fresh choice identities captured by value by rendered controls; Install/Skip share one offer identity. An identity protects local controls, not arbitrary native callback reordering.
- Only latest auto-dismisses, after five seconds. Keep one cancellable Task and its own post-await cancellation/status guard, with no await before writing idle. No timer generation or independent timer-completion API.
- Fixed native release link: `https://github.com/iRedlof/Glimpse/releases/latest`. No raw errors, paths, framework details, offline diagnosis, or promises of retry success in UI.
- Preserve no-update reason handling, information-only/major-update behavior, release notes, cancellation controls and termination-retry behavior. Existing `.extracting` continues presenting “Installing…”; this work does not invent an installation phase.
- Keep plain Button/Link styling and AppDesign targets. Remove `.focusable(false)` only in updater controls; this accepted keyboard-access requirement overrides the generic view rule. No global Return shortcut or calendar/input routing change.
- Fixture tests use per-test injected clients, counted callbacks and controlled delays. Never construct `SparkleUpdater.shared` or `SPUUpdater`, touch production defaults, fetch a feed, change signing, or perform a real update.
- Workers do not commit/push or run duplicate whole suites. Root owns acceptance, metadata, the one ordinary exact-source commit hook, protected delivery and native checks.

## Review Focus

1. Eligibility changes after Retry was rendered, or notification is delayed: stale activation must do nothing; two rapid activations admit one synchronous check (Task 1 tests).
2. Error arrives with an outstanding offer/ready reply: acknowledgement alone must not unlock a new check, consume a choice, or erase the failure (Task 2 tests).
3. Choice A synchronously publishes same-phase choice B: retained A Install/Skip/Relaunch actions must leave B intact and B must remain usable (Task 2 tests).
4. Canceled sleeper returns successfully after an equal newer latest result, or an acknowledgement publishes a new state: the newer presentation must survive (Task 3 tests).
5. About is recreated while a failure or choice is outstanding: state/choice survives, eligibility refresh reaches the displayed control, and disabled/native keyboard actions cannot start work (Task 4 fixture tests plus signed keyboard acceptance in Task 5).

---

## Baseline and exact file responsibility map

Source inspected read-only: `/Users/rohit/.codex/worktrees/stability-ux/Glimpse`. Brief-supplied source identity is `ec5e15c4f238e2d3eeb114bb2bdcf1cde04dfd96`, tree `c1f9525ee01b666d2b0bd231d9691e971f34f857`; supplied protected-main squash `7b1f18155f42007087733bed149ab0fc9cae6c58` has the same tree. Planning verified file hashes, not Git refs. The earlier design inspected `f90999f3…`; its relevant files still match. Current project/README/readiness values are 1.4.9/build 16; that release/native acceptance remains pending.

| File | Responsibility and owner |
| --- | --- |
| Modify `Glimpse/SparkleUpdater.swift` | One app owner across Tasks 1–3: client, typed status, guarded check, private callback ownership, identities, result Task and callback ordering. Keep these small, coupled types in the existing file. |
| Modify `Glimpse/AboutWindow.swift` | Same coordinated app owner: minimal enum compatibility in Task 1, move choice calls into driver methods in Task 2, actual injected `AboutUpdateSection` and final presentation in Task 4. No diagnostics or other About behavior changes. |
| Create `GlimpseTests/SparkleUpdaterTests.swift` | `@MainActor` `SparkleUpdaterTests`, `UpdateChoiceTests`, `UpdateResultTests`; shared file-local/internally visible test-only fixture utilities. Tests exercise real driver/client methods. |
| Create `GlimpseTests/AboutUpdateSectionTests.swift` | `@MainActor` actual hosted section tests, public in-process accessibility traversal/activation and intercepted `OpenURLAction`. |
| Modify `Glimpse.xcodeproj/project.pbxproj` | One coordinated owner: add both test files to PBXFileReference, PBXBuildFile, GlimpseTests group and its Sources phase; use unused DD-prefixed IDs verified at execution. Root alone later synchronizes versions. |
| Root-only `README.md`, `.github/release-readiness.json`, `docs/product-inventory.md`, `docs/stability-roadmap.md` | Task 5 metadata and truthful scoped evidence; no provisional passed claims. |
| Root-only planned docs paths above; `docs/superpowers/reviews/2026-11-02-update-retry-acceptance.md` | Accepted design/plan and later independent source acceptance. |
| Preserve `Glimpse/GlimpseApp.swift`, `Glimpse/Info.plist`, both `Package.resolved`, Core, AppDesign, calendar/input/preferences and release tooling | No implementation edits. Read for compatibility and verify preservation. |

Before dispatch, root rechecks prerequisite acceptance, actual branch/tree/cleanliness, relevant file hashes, rules, pin maps and CD-01's final hook behavior in the later isolated implementation worktree. Rebase this plan's line anchors/interfaces if the final baseline changed; do not blindly patch the frozen source or assume a cached release result. Tasks below depend on this preflight and execute in order.

## Focused verification contract

Use unique owned scratch outside tracked source for each RED/GREEN run. Create a task-local `run-bounded.py` there with the following interface: `python3 run-bounded.py EVIDENCE_DIRECTORY COMMAND [ARG ...]`. Its implementation must use `subprocess.Popen(argv, start_new_session=True, stdout=log, stderr=subprocess.STDOUT)`, `wait(timeout=1200)`, and on timeout send SIGTERM to that child's process group, wait at most 10 seconds, then SIGKILL that group if needed. Write command argv, working directory, exit code/timeout and elapsed time to JSON beside the complete log; return the actual command exit code, or 124 for timeout. Poll/tail the retained log for progress. This runner is owned scratch, never tracked product code. Dependency infrastructure failure/timeout is not behavioral RED.

From the implementation worktree, assign `UX02_SCRATCH` to a unique `mktemp -d` directory under the root-approved external build directory. Create a fresh `UX02_RUN` directory for each invocation. Resolve once:

```sh
python3 "$UX02_SCRATCH/run-bounded.py" "$UX02_RUN" \
  xcodebuild -project Glimpse.xcodeproj -scheme Glimpse \
  -derivedDataPath "$UX02_SCRATCH/DerivedData" \
  -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation
```

For each suite named by a task, run the following through that bounded runner, setting `UX02_RUN` to a fresh owned directory and replacing `SUITE` with that exact suite name:

```sh
python3 "$UX02_SCRATCH/run-bounded.py" "$UX02_RUN" \
  xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -destination 'platform=macOS' \
  -derivedDataPath "$UX02_SCRATCH/DerivedData" -skipMacroValidation \
  -disableAutomaticPackageResolution -only-testing:GlimpseTests/SUITE \
  -resultBundlePath "$UX02_RUN/AppTests.xcresult" CODE_SIGNING_ALLOWED=NO test
```

Retain actual command/exit/log, source identity and changed-file SHA-256 manifest for that run, lockfile before/after hashes, test names/parameter cases/pass/fail/skip counts, and xcresult. Missing interface compilation may be an initial scaffold failure; meaningful RED must reach and fail the specified behavioral assertion before accepting the fix. Rerun only affected focused suites after fixes, then freeze for review. Task 5 alone runs whole quality via the ordinary controller commit hook.

### Task 1: Inject native updater access and make manual checks/failures truthful

**Files:** Modify `Glimpse/SparkleUpdater.swift` (current status and updater blocks, lines 8–55; error callback lines 105–108); adapt exhaustive switches in `Glimpse/AboutWindow.swift` (lines 135–179); create `GlimpseTests/SparkleUpdaterTests.swift`; add its project membership.

**Interfaces:**
- Produce `enum UpdateFailure: Equatable { case check, update }`; replace `.error(String)` with `.error(UpdateFailure)` and add `.initializationFailed` to `UpdateStatus`.
- Produce `@MainActor struct UpdaterClient` with `start: () throws -> Void`, `canCheckForUpdates: () -> Bool`, `observeCanCheckForUpdates: (@escaping @MainActor (Bool) -> Void) -> AnyCancellable`, `checkForUpdates: () -> Void`, and `static func live(userDriver: InlineUpdateDriver) -> Self`.
- Produce `SparkleUpdater.init(userDriver: InlineUpdateDriver, client: UpdaterClient)`, retaining its client and observation token; keep a private production convenience constructor for `.shared`. `live` constructs one `SPUUpdater` and captures that instance in these closures. Preserve the existing KVO publisher and synchronous MainActor delivery; do not introduce a scheduling hop to fix actor diagnostics.
- Keep `SparkleUpdater.checkForUpdates() -> Void`; expose `var canCheckForUpdates: Bool` as the common computed predicate. Store private initialization success and private observed native eligibility separately; those are not a check-admission flag or session cache.
- Produce driver `beginUserInitiatedCheck() -> Void` and `showInitializationFailure() -> Void`. Driver status remains the sole presentation state. Later tasks make callback slots private.
- Produce `InlineUpdateDriver.init(delay: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) })`; initially replace only the existing Task's awaited sleep with this dependency. Preserve `NSObject` initialization/protocol conformance. Task 3 owns the scheduling/cancellation fixes.
- Test utility `@MainActor final class ControlledUpdateDelay`: injected `sleep(_ duration: Duration) async throws`, per-request integer IDs/durations, continuation-based wait-for-registration/return receipts, and `resumeSuccessfully(_ id: Int)`/`resumeThrowing(_ id: Int)`. Record the caller's `Task.isCancelled` when returning; allow a successful return despite cancellation. IDs exist only in the fixture. Drain all continuations at teardown.
- Test utility `@MainActor final class UpdaterFixture`: `driver`, `updater`, `backend`, `delay`; always inject the controlled delay, including before Task 3. Backend records `startCount`, `checkCount`, `canCheck`, `onCheck`, optional `startError`, and `publishEligibility(_:)`. Changing `canCheck` without publishing simulates a delayed notification. Its closures are the real injected client; it never models driver transitions.

- [ ] **Step 1: Write behavioral regression scenarios in `SparkleUpdaterTests`.** `initializationFailureHasNoRetryPath` injects start throwing, projects the same driver twice, invokes stale `checkForUpdates`, and asserts `#expect(driver.status == .initializationFailed)`, `#expect(backend.startCount == 1)`, `#expect(backend.checkCount == 0)`, `#expect(!updater.canCheckForUpdates)`. `checkErrorWaitsForEligibilityAndPersistsThroughDismissal` starts a check, makes eligibility false, invokes the actual error callback with a counter and then actual dismissal: assert `.error(.check)`, acknowledgement count 1, disabled check; publish true and assert enabled with no additional check.
- [ ] **Step 2: Add stale admission and successor scenarios.** `eligibilityDropRejectsRenderedRetry` captures the action while eligible, changes live eligibility without publishing, invokes it, and asserts unchanged failure/check count plus false computed availability. `doubleRetryAdmitsBeforeNativeCallback` makes `onCheck` assert `.checking`, delays all native callbacks/notifications, calls twice, then publishes true: assert count increased exactly 1, status `.checking`, and no queued follow-up. Parameterize `retryReceivesNewOutcome` over latest/repeated-error using actual callbacks and the controlled delay; assert new state supersedes error and a repeated failure permits only another explicit eligible retry. Unknown/idle preceding error must produce `.error(.update)`. The offer-success case is written in Task 2 after its helper exists.
- [ ] **Step 3: Record RED for `SparkleUpdaterTests`.** Use the focused command above; the stale/double-check assertions must fail behaviorally against the original unguarded check path. Add only the minimal compile-compatible seam/types needed to reach those assertions, and retain that distinct baseline.
- [ ] **Step 4: Implement the defined interfaces.** Subscribe before the single start attempt, publish `.initializationFailed` on throw, and log bounded context through AppLogger without showing raw errors. Observation only stores availability. Activation re-reads live eligibility into the observed value, evaluates the same predicate, cancels old result work/sets `.checking`, and then calls the client. A native error maps a preceding `.checking` to `.check`, everything else to `.update`, records before acknowledging once, and does not retire choices. Adapt About's enum switch with the accepted failure text so this task compiles; complete actions/layout/accessibility in Task 4.
- [ ] **Step 5: Record focused GREEN and review.** Verify start remains one through every retry; test-host guard and native factory are isolated from fixture construction. Freeze source/hashes and report focused evidence to root; no worker commit.

### Task 2: Own Install/Skip/Relaunch choices and teardown

**Files:** Modify `Glimpse/SparkleUpdater.swift` (driver fields, offer/ready/dismiss methods); replace direct callback/status mutation in `Glimpse/AboutWindow.swift` (current lines 181–233); extend `GlimpseTests/SparkleUpdaterTests.swift`.

**Interfaces:**
- Consume Task 1's typed status/client/fixture and common predicate.
- Produce `private(set) var updateChoiceID: UUID?`, `private(set) var installChoiceID: UUID?`; make both callback slots private. Read-only identity presence lets the common predicate detect ownership even when error presentation has replaced the offer.
- Produce `presentUpdate(version: String, reply: @escaping (SPUUserUpdateChoice) -> Void) -> Void`, called by `showUpdateFound(with:state:reply:)` using `displayVersionString ?? versionString`. Tests call this exact production helper; do not initialize `SPUUserUpdateState`.
- Produce `chooseUpdate(_ choice: SPUUserUpdateChoice, id: UUID) -> Void` accepting only `.install`/`.skip` in `.available`, and `chooseInstallAndRelaunch(id: UUID) -> Void` accepting only a matching `.readyToInstall` choice. Both require matching identity and nonnil slot.
- Retain actual `showReady(toInstallAndRelaunch:)` and `dismissUpdateInstallation()`. Each offered/ready reply gets a fresh UUID; no generic queue or session identity.

- [ ] **Step 1: Write `UpdateChoiceTests` for consumption and same-phase replacement.** In `oldOfferControlsCannotConsumeReplacementOffer`, capture A's ID and both A actions by value; A's `.install` callback synchronously calls `presentUpdate` for B. After A, assert `#expect(aChoices == [.install])`; invoke retained A Install and Skip, assert `#expect(bChoices.isEmpty)` and `#expect(driver.updateChoiceID == bID)`; activate B with B's ID twice and assert `#expect(bChoices == [.install])`. A separate fresh fixture chooses Skip twice and asserts `[.skip]`, no check and no fabricated choice. Mirror A→B with `showReady`/`chooseInstallAndRelaunch`, asserting each matching reply receives `.install` once and retained A leaves B intact.
- [ ] **Step 2: Write teardown/error blockers.** Parameterize `errorRetainsOwnedChoiceUntilSparkleDismisses` over offer and ready: publish a choice, invoke actual error and record acknowledgement's observations of `.error(.update)` and unchanged ID; assert no choice invocation and `!canCheckForUpdates`, including after an eligibility notification. Actual dismissal must nil both IDs without invoking either reply and preserve failure. Then an explicit eligible check is accepted. Parameterize `failureDuringProgressAllowsOnlyNewCheck` over download and installation callbacks: consume the prior install choice, enter progress, publish error, and assert `.error(.update)`, acknowledgement 1, no replayed choice and no new check while ineligible; dismissal/eligibility restoration permits one explicit new check only. `dismissInvalidatesAllOldControls` retains offer and ready actions, dismisses, invokes all, and asserts zero calls/IDs nil/idle. Parameterize active phase over checking/available/downloading/extracting/ready; attempted check must leave check/start/choice counts unchanged. Keep tests on actual driver callbacks, not direct status writes.
- [ ] **Step 3: Record RED for `UpdateChoiceTests`.** The old take-after-call view behavior and unvalidated replacement identity must be demonstrated by failed callback-count or preserved-B assertions; missing symbols alone are insufficient.
- [ ] **Step 4: Implement ownership and wire the existing controls.** Take a matching callback locally, retire its own slot and ID, leave that phase with disabled choice controls while awaiting Sparkle, then invoke and return. In About, bind `let id` while rendering each choice and capture that value in its closure; never read the current ID at activation. Disable controls when phase/ownership is absent. Dismiss clears both slots/IDs, changes ordinary active presentation to idle, and preserves `.initializationFailed`, `.error` and `.latest`. It never manufactures an install/skip/dismiss response.
- [ ] **Step 5: Record focused GREEN and review.** Add the offer-success case to `retryReceivesNewOutcome` using `presentUpdate` and run `SparkleUpdaterTests` along with `UpdateChoiceTests` for this change. Verify `.available`/`.readyToInstall` after consumption still block checks until a native transition, even if a fake notification is delayed. Include a realistic resumed-update sequence: idle/no owned choices/live eligible → explicit check → offer/ready callback → matching user choice. No `sessionInProgress` contradiction is needed. Freeze and return evidence; no worker commit.

### Task 3: Keep latest dismissal and acknowledgement reentrancy safe

**Files:** Modify `Glimpse/SparkleUpdater.swift` (current timer lines 66–77, all presentation callbacks, installation completion); extend `GlimpseTests/SparkleUpdaterTests.swift`.

**Interfaces:**
- Consume Tasks 1–2's transitions, ownership, status, injected delay initializer and `ControlledUpdateDelay`.
- Retain one private `Task<Void, Never>?` and name its `.seconds(5)` latest duration.
- Use one private status-publication helper to cancel superseded result work; preserve latest task/result on ordinary dismissal. No extra independently writable presentation state.

- [ ] **Step 1: Write `UpdateResultTests` for real Task cancellation.** `latestWaitsFiveSecondsAndSurvivesOrdinaryDismissal` invokes actual no-update callback; assert latest/ack 1, await the injected sleep registration and assert `#expect(request.duration == .seconds(5))`; dismiss and assert latest; resume the current sleep, allow the actual MainActor Task to complete, assert idle. Parameterize `canceledLatestCannotEraseNewPresentation` over error/check/offer/download/extraction/ready/installing/new-equal-latest using real transitions. Register A, supersede it, return A successfully, assert its captured caller-cancellation flag is true and the newer state persists. For equal latest B, assert latest after A returns, then idle only after B's own five-second request returns. Use continuation receipts and bounded executor draining, not wall-clock sleeps or a separate production timer-completion method.
- [ ] **Step 2: Write the acknowledgement reentrancy matrix.** For error/latest/installed-finished, count acknowledgement and inspect state inside it: error/latest must already be published; installation-finished must already have cleared owned IDs and published idle for ordinary progress. Have each acknowledgement either call ordinary dismissal or publish an offer, ready choice, progress or a new error synchronously. Assert acknowledgement count 1 and replacement status/identity survives return. For latest acknowledgement publishing a replacement, release any canceled sleeper and assert it cannot erase the replacement. Include error/latest ordinary dismissal preservation and installation-finished ordinary cleanup.
- [ ] **Step 3: Record RED for `UpdateResultTests`.** Expected original failures include error/offer not canceling latest, latest scheduled after acknowledgement, and installation-finished idle written after acknowledgement. Retain the failing observable state assertions; a timeout is not the target regression.
- [ ] **Step 4: Implement task/publication ordering.** Cancel on a new check and every superseding result/offer/progress/ready presentation, including equal latest. Schedule the new latest Task before acknowledgement; after awaiting delay, guard its own `Task.isCancelled` and expected `.latest`, then write idle synchronously. Treat cancellation as expected; log an unexpected injected delay error without falsely showing idle. Record errors before acknowledgement. Installation-finished retires choices and clears ordinary progress before acknowledgement, preserving an already terminal About result consistently with dismissal. No callback makes old-state writes or schedules old work after acknowledgement.
- [ ] **Step 5: Record focused GREEN and review.** Verify failures have no dismissal request; ordinary dismissal leaves latest's live Task intact; a canceled delay that returns successfully cannot mutate any newer equal result. Check callback blocks remain small and MainActor-safe, then freeze evidence; no worker commit.

### Task 4: Render the actionable About section and prove real bindings

**Files:** Modify `Glimpse/AboutWindow.swift` (update section only); create `GlimpseTests/AboutUpdateSectionTests.swift`; add its project membership.

**Interfaces:**
- Consume `SparkleUpdater`, driver status/read-only identities, guarded `checkForUpdates()` and choice methods from Tasks 1–3.
- Produce internal `@MainActor struct AboutUpdateSection: View` with `init(updater: SparkleUpdater, appVersion: String)` and no default singleton argument. Existing private `AboutView` owns its shared updater as before and renders this section. No independent state model, view-created updater, lifecycle reset or status/callback mutation.
- Test-only `AboutUpdateHost` hosts the actual section in an owned, never-frontmost `NSWindow`/`NSHostingView`, supports replacing only its root section with the same updater, traverses public in-process `NSAccessibility` children, finds controls by label and invokes `accessibilityPerformPress()`. Do not assume SwiftUI buttons are `NSButton` subclasses or use private view reflection. Intercept link opening with `.environment(\.openURL, OpenURLAction { … .handled })`; record the URL without launching a browser.

- [ ] **Step 1: Write `AboutUpdateSectionTests` that drive native bindings.** `failureReopenRetainsFallbackWithoutStartingAgain` hosts initialization failure, recreates the section with the same updater, asserts visible initialization copy/release link and absence of Check/Retry, and checks start 1/check 0. `retryBindingRefreshesInPlace` reaches check failure through actual callbacks, asserts Retry visible/disabled and helper text; attempt its accessibility press and assert no check; publish eligibility true without replacing host, assert enabled/helper absent, press and assert check +1 and `.checking`. Immediately repeat/retain the action and assert no second check.
- [ ] **Step 2: Cover actual choice and release actions.** Parameterize `sectionChoiceInvokesMatchingDriverAction` over Install/Skip/Install & Relaunch: present through the real helper/callback, find by accessibility name, activate, and assert exactly the matching choice count and retired ID; recreate the section before activation to prove no start/check/choice on reopen. In the Install case, callback publishes same-phase B; newly rendered B control must invoke B once. Driver tests retain stale A identities; source review separately verifies the actual view captures ID by value. `releaseLinkUsesOfficialDestination` presses the actual link in each failure kind, asserting exactly the fixed HTTPS URL and no updater call. Parameterize status rendering over every enum case and runtime failure kind; assert the controls' presence/absence and disabled state, not just literal strings.
- [ ] **Step 3: Record RED for `AboutUpdateSectionTests`.** Expected failures are missing recovery controls, no live eligibility binding, direct choice callback ownership or unusable disabled activation. Missing host/accessibility plumbing is a fixture issue to repair, not a passing substitute or reason to test a duplicate model.
- [ ] **Step 4: Implement the exact presentation below.** Keep the existing width/layout/diagnostics/version presentation. Wrap and center failure text; use AppDesign `.xs`/`.sm`/`.md` spacing, `.padding(.horizontal, AppDesign.Spacing.sm)`, `.padding(.vertical, AppDesign.Spacing.xs)` and `.contentShape(Rectangle())` on update Button/Link labels. Keep plain styling, native focus indication, readable text independent of red and decorative error/check icons `.accessibilityHidden(true)`. No global key shortcut.

| Status | Text and controls |
| --- | --- |
| idle | “Check for Updates”; disabled by common predicate |
| initializationFailed | “Updates are unavailable.” / “Get the latest Glimpse release from GitHub.”; View Releases only |
| checking | Existing spinner and “Checking for updates…”; no Check/Retry/Install |
| error(.check) | “Couldn’t check for updates.”; Retry and View Releases; disabled Retry remains visible with “Retry is temporarily unavailable.” while common predicate is false |
| error(.update) | “The update couldn’t be completed.” / “Check again for available updates.”; Check for Updates disabled by common predicate, plus View Releases |
| latest | Existing “You're on the latest version”; decorative check hidden from accessibility |
| available | Existing current → offered version, Install and Skip captured from one offer ID |
| downloading / extracting | Existing spinner and “Downloading…” / “Installing…” |
| readyToInstall | Existing “Install & Relaunch”, enabled only for the captured owned ready ID |

Use accessibility labels exactly: “Retry checking for updates”, “Check for updates”, “View Glimpse releases on GitHub”, “Install update”, “Skip this update”, “Install update and relaunch Glimpse”.

- [ ] **Step 5: Record focused GREEN and source/accessibility review.** Assert public roles Button/Link and the specified labels; prove disabled activation and fixed link via the real section. Hidden hosting is controlled fixture evidence, not proof of visible window fit, VoiceOver or keyboard focus. Check only updater `.focusable(false)` modifiers were removed, all status cases are covered, and no Return shortcut/production settings were introduced. Freeze and return evidence; no worker commit.

### Task 5: Root-owned acceptance, current-baseline metadata and verified delivery

**Files:** Root-owned docs, project version settings, README and readiness from the map. Source acceptance is a gate before metadata work; no app worker owns this task.

**Interfaces:** Consume frozen source/hash manifests and actual focused RED/GREEN/xcresult evidence from Tasks 1–4; produce independent A1–A8 acceptance, synchronized next version/build/readiness, exact-source whole-quality evidence, protected Release/Recovery/public-artifact evidence and separately labeled native acceptance.

- [ ] **Step 1: Accept the source against the complete design and A1–A8.** Review UI roles/focus (A1), preserved About/calendar lifecycle/input boundaries (A2–A3), all Sparkle transitions/HTTPS/EdDSA/choices/five-second dismissal (A4), unchanged AI/preferences (A5–A6), no redundant state/private API/dependency/unsafe concurrency (A7), and real behavior/host bindings (A8). Resolve material findings and rerun only affected focused suites. Record native limitations and all 13 design acceptance rows explicitly.
- [ ] **Step 2: Dispatch metadata only after refreshing the prior baseline.** Root checks current accepted production and exact main plus UX-01/CD-01 completion; select the next marketing/build values before assigning metadata, with build strictly greater than the verified prior release. Do not preselect “1.4.10/17” from this planning snapshot. Synchronize all four marketing values, all four build values, README badge, readiness version/build and scoped evidence together. Readiness must reference accepted UX-02 evidence, not copied screen-fit acceptance. Run `python3 tools/scripts/release-control.py version --root "$PWD"` and `python3 tools/scripts/check-dependency-pins.py --root "$PWD"`; expect successful consistency and unchanged 15-pin maps.
- [ ] **Step 3: Run one ordinary controller commit hook on the final staged source.** After independent whole-branch review, root stages all intended source/docs/metadata and makes the normal commit with no bypass/config changes. The hook owns `tools/scripts/quality-gate.sh` against the exact staged archive and detects mutation; retain its real source tree, exit, complete logs, pin comparison and app xcresult. Do not run a duplicate full suite before it. CD-01 may change admission boundaries; preflight must confirm the accepted hook preserves these quality/mutation checks. If anything changes during the hook, its evidence is stale and the ordinary hook must run on the corrected final staged source.
- [ ] **Step 4: Follow ordinary protected integration and terminal release verification.** Root verifies required checks and exact-main Release/Recovery, signed/notarized app and DMG, bundle/source/version/build/team, Sparkle signature and anonymous public feed/downloads. Attach any created PR through the normal app tool. A merged PR or green focused tests are insufficient release evidence.
- [ ] **Step 5: Record signed About acceptance separately.** Verify actual wrapped copy/content height/window fit, light/dark contrast, VoiceOver names/roles, keyboard traversal/focus indication, focused activation and disabled activation, Check/Retry responsiveness, release-link destination and close/reopen persistence. Confirm no global Return binding and ordinary window close/calendar editing/shortcut routing. Use a controlled injected presentation only where a safe real fault reproducer is unavailable, label that evidence, and do not ship a production debug switch just for it. Real network errors/retry, deferred/resumed update prompts, existing install/Skip/relaunch behavior require distinct native evidence; record any unavailable case as a limit. Preserve permissions/data/startup/signing; original other-Mac crash and user-deferred restart remain unresolved. Only then update inventory/roadmap with the achieved evidence boundaries.

## Self-review coverage and handoff

All accepted design rows map to tasks: initialization/reopen → 1+4; error/ack/dismiss/eligibility → 1+2+4; live drop/double admission → 1+4; phase/choice blockers → 2; retry latest/offer/repeated failure → 1+2+3; download/install failure → 2+4; both same-phase A→B cases → 2; native invalidation → 2; canceled/equal timer and ordinary dismissal → 3; error/latest/finished acknowledgement reentrancy → 3; outstanding choice/failure reopen → 4. Signed/native conditions and release limits belong Task 5.

Self-review checked spec coverage, one checkable action per step, cross-task names/types, all five Review Focus cases and proportion. Fixes applied during review: root-only commits replace the skill's generic per-task commits; latest uses the existing Task's cancellation rather than a generation; no second admission/session state; immutable control identity and real hosted action tests are complementary, not substitutes; metadata values wait for the post-CD-01 baseline.

This planning artifact permits review, not execution now. Root owns plan acceptance and the already established execution method after prerequisites; no new execution-method question or delegated implementation is part of this assignment.


## Lead execution handoff — 2026-11-02

UX-01 public delivery and CD-01 protected integration/exact-main verification are accepted. Installed v1.4.9 physical fit/scroll checks remain pending. Implementation starts from main `06e48b4fcf10c4af7abbe6a457c63c33ed73bb83`, tree `c7a1e0f3d63d7c4873e41ccfaa285f354761c3be`; relevant app/lock hashes still match the accepted design. Historical planning-only conditions above describe the original assignment; this handoff authorizes execution under the active master goal. Root executes Tasks 1–4 inline, without intermediate commits or duplicate whole checks, followed by one independent whole-source review and Task 5. No future version/build is selected yet. Original design/reports/reviews remain in `/Volumes/xHome/Github/Glimpse/build/validation/update-retry-design.flqanipo`.
