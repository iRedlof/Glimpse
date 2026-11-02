# Update Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with checkbox tracking. Execution is root-native, followed by independent whole-branch review; no per-task implementation agents are requested.

**Goal:** Give every Sparkle no-update reason truthful, actionable About guidance while preserving latest expiry and UX-02 callback/check freshness.
**Architecture:** Copy trusted NSError metadata into small Equatable values in the existing main-actor driver. Add one terminal status and complete its About projection using existing controls; reuse the current injected backend, controlled delay and owned accessibility host. Make the production About view injectable for genuine full-view fixture rendering.
**Tech Stack:** macOS 14+, Swift 6, AppKit/SwiftUI, Swift Testing, locked Sparkle 2.9.4.
**Spec:** `docs/superpowers/specs/2026-11-02-update-guidance-design.md`, copied from the accepted external design with only provenance links adapted.
**Plan destination:** `docs/superpowers/plans/2026-11-02-update-guidance.md`.

## Global Constraints

- Lead acceptance is under the autonomous master goal; detailed copy is team-owned, not human-approved.
- Base: main `1ee8f7ec96c524544cd089aae635488b46c40737`, tree `51a8820a1918e4a5cb2fccc6159c19ef3b3fc2ab`; root has moved the managed worktree to `codex/update-guidance`.
- Preserve both lockfiles, Sparkle 2.9.4 revision `b6496a74a087257ef5e6da1c5b29a447a60f5bd7`, HTTPS/EdDSA/security/settings and the test-host startup guard.
- Explicit `.latest` retains green presentation/five-second expiry, with the lead-revised exact headline **`No newer update was found`**.
- Other no-update results persist in memory through native dismissal/reopen; no timer, UserDefaults, new updater, Dismiss control or settings deep link.
- Every non-latest result offers exactly **Check for Updates** and **View Releases**, using existing fresh admission and `https://github.com/iRedlof/Glimpse/releases/latest`.
- Keep information-only/major upgrades, release notes, cancellation, termination retry, Core/proxy/calendar behavior and startup work outside scope.
- Candidate **v1.4.12/build19** depends on a fresh version/source check before editing; synchronize four marketing versions, four build numbers and README badge.
- Retain source identities, receipts, logs, xcresults and render artifacts outside tracked source; do not alter source while its verification command runs.

## Review Focus

1. NSNumber Bool/coercion, fractional/non-finite/overflow values must never become a false latest result — Task1 reason fixtures.
2. Optional/conflicting SDK-item metadata must preserve the reason and safely omit malformed thresholds — Task1 adapter/validation fixtures.
3. Old delay, acknowledgement reentrancy and pending choices must not erase/consume a newer presentation — Task1 lifecycle fixtures.
4. Eligibility changing after rendering and repeated presses must admit at most one check — Task1 driver plus Task2 actual AX presses.
5. Long reason/detail/disabled text must fit the actual full About view in both appearances, with usable named controls — Task2 full-view rendering.

## Files and interfaces

| File | Responsibility |
| --- | --- |
| Modify `Glimpse/SparkleUpdater.swift` | Value models, classification, new terminal phase, callback/eligibility/dismiss behavior. |
| Modify `Glimpse/AboutWindow.swift` | Exhaustive status switch, exact guidance/copy, internal injected production About constructor. |
| Modify `GlimpseTests/SparkleUpdaterTests.swift` | Contract-correct error/item helpers and classifier/lifecycle regressions, reusing current fixtures. |
| Modify `GlimpseTests/AboutUpdateSectionTests.swift` | Copy/action/AX regressions and extension of the same owned host to production full About content. |
| Modify project version + README | v1.4.12/build19, after fresh verification; no dependency or release-policy changes. |
| Create tracked spec/plan and `docs/superpowers/reviews/2026-11-02-update-guidance-acceptance.md` | Accepted requirements, execution record, scoped evidence/gaps. |
| Modify `docs/product-inventory.md`, `docs/stability-roadmap.md` | Actual implementation/test/delivery status; preserve unrelated open gaps. |

Keep production additions in existing files; no new Xcode file entries or parallel test infrastructure.
Types: `UpdateNoUpdateReason: Equatable` with `unknown`, `newerThanFeed`, `systemTooOld`, `systemTooNew`, `requiresAppleSilicon`.
`UpdateNoUpdateGuidance: Equatable` has `reason: UpdateNoUpdateReason`, `requirementVersion: String?`.
Add `UpdateStatus.noUpdate(UpdateNoUpdateGuidance)`; `InlineUpdateDriver.noUpdateStatus(for error: Error) -> UpdateStatus`.
Task2 consumes these exact values and the existing `updater.checkForUpdates()`, `canCheckForUpdates` and choice UUID interfaces.

## Run setup and bounded commands

Root owns commands below; this planning pass executes none. The existing wrapper retains before/after source/pin hashes, logs and receipts, and bounds its owned process group to 1200 seconds.
Do not overlap commands using retained DerivedData; the fresh baseline has completed.

```sh
cd /Users/rohit/.codex/worktrees/stability-ux/Glimpse
UPD03_EVIDENCE=/Volumes/xHome/Github/Glimpse/build/validation/update-guidance-implementation.bpo8vktn
UPD03_WRAPPER=/Volumes/xHome/Github/Glimpse/build/validation/accessibility-implementation.xeeb2lu6/run-bounded.py
UPD03_DERIVED_DATA=/private/tmp/glimpse-ux02.dkbzt19q/DerivedData
```

Fresh root baseline: EXIT0, 26 named tests/72 cases, no failures/skips/xcresult runtime warnings; raw destination/linkd diagnostics retained separately.
Root's compiled SDK probes confirm enum case names below and real public item min/max metadata. Reuse their receipts; these do not establish native compatibility selection.
Every wrapper destination/result bundle must be new; increment `red-1`/`green-1` suffixes for retries. Retain complete logs; do not pipe tests through tail.

**Driver command** (use `task1-red-1`/`task1-green-1` and corresponding result paths at the named steps):

```sh
python3 "$UPD03_WRAPPER" "$UPD03_EVIDENCE/task1-red-1" xcodebuild test \
  -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$UPD03_DERIVED_DATA" -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates -skipMacroValidation \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 30 \
  -only-testing:GlimpseTests/UpdateNoUpdateTests -only-testing:GlimpseTests/SparkleUpdaterTests \
  -only-testing:GlimpseTests/UpdateChoiceTests -only-testing:GlimpseTests/UpdateResultTests \
  -resultBundlePath "$UPD03_EVIDENCE/task1-red-1.xcresult" CODE_SIGNING_ALLOWED=NO
```

**About command** (use `task2-red-1`/`task2-green-1` at the named steps):

```sh
python3 "$UPD03_WRAPPER" "$UPD03_EVIDENCE/task2-red-1" xcodebuild test \
  -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$UPD03_DERIVED_DATA" -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates -skipMacroValidation \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 30 \
  -only-testing:GlimpseTests/AboutUpdateSectionTests \
  -resultBundlePath "$UPD03_EVIDENCE/task2-red-1.xcresult" CODE_SIGNING_ALLOWED=NO
```

GREEN requires EXIT0, **TEST SUCCEEDED**, a Swift Testing summary containing the intended named tests/cases, and no unaccounted failure/skip/runtime warning. XCTest's “0 tests” line is not sufficient. RED must expose the intended behavior regression, not an unrelated compiler/setup failure.

## Task 1: classification and driver lifecycle

**Files:** updater source/tests; About switch only as the necessary compile companion; tracked accepted spec/plan.
**Consumes:** existing SDK callbacks, `UpdaterFixture`, `UpdateBackend`, `ControlledUpdateDelay`.
**Produces:** the exact models/classifier/status above, terminal check/dismiss behavior, stable contract helpers and lifecycle regressions.
This is a driver gate, not release eligibility; Task2 must replace its generic compile companion with the full reason projection.

- [x] **1. Confirm execution identity/version and copy planning documents.** Verify clean owned branch/head/tree and both lock hashes; inspect current marketing/build/badge. Copy accepted spec/plan to intended tracked paths, making provenance references resolvable without changing accepted behavior. Preserve external acceptance hashes in evidence.
- [x] **2. Add meaningful RED reason tests in existing test file.** Introduce `UpdateNoUpdateTests` and helper `noUpdateTestError(reason: SPUNoUpdateFoundReason, item: SUAppcastItem? = nil) -> NSError`, using `SUSparkleErrorDomain`, `Int(SUError.noUpdateError.rawValue)`, `SPUNoUpdateFoundReasonKey: NSNumber(value: reason.rawValue)`, optional `SPULatestAppcastItemFoundKey`.
  Initial assertions use existing `.latest`: latest input remains latest; every other reason plus arbitrary `updateTestError` must satisfy `#expect(fixture.driver.status != .latest)` and one acknowledgement. These fail behaviorally before new model cases exist.
  Replace current latest-only calls using `updateTestError` with the genuine explicit-latest helper, including About's latest setup. Keep ordinary failure tests unchanged.
- [x] **3. Run driver RED command.** Retain intended non-latest assertion failures and source/pin receipt. Do not proceed on an unrelated build failure.
- [x] **4. Implement models/classifier and exhaustive compile companion.** Use imported SDK cases `.unknown`, `.onLatestVersion`, `.onNewerThanLatestVersion`, `.systemIsTooOld`, `.systemIsTooNew`, `.hardwareDoesNotSupportARM64`.
  Require domain/code before trusting reason; reject CFBoolean explicitly before numeric conversion, using public CoreFoundation type identity if needed.
  Accept numeric values exactly representable as OSStatus and equal to a known case; SDK boxed raw values/normal Int bridges and integral `NSNumber(value: 1.0)` are valid, Boolean `true` is not. Reject fractional/non-finite/overflow values without trapping/truncation.
  Read only real `SUAppcastItem` metadata. Trim outer whitespace; allow one–three nonempty ASCII digit components, periods only, at most32 characters and no internal whitespace/controls; copy applicable min/max only.
  Publish before acknowledging once; schedule five seconds only for `.latest`; add `.noUpdate` to check-eligible terminal phases and dismissal preservation. Keep current fresh read, cancellation and native-choice ownership.
  **Compile companion:** handle `.noUpdate` in About with the accepted unknown headline/recovery and existing two controls, no icon/timer. It is a complete generic terminal presentation, explicitly superseded by Task2's reason matrix; never leave the switch non-exhaustive or call this gate the finished UX.
- [x] **5. Strengthen exact reason/number/item assertions.** `reasonClassificationPreservesNativeMeaning` covers all six cases and exact expected status; `untrustedOrMalformedReasonNeverClaimsLatest` covers wrong domain/code, missing key, future/negative raw values, String, NSNull, Bool true/false, 1.5, NaN/infinity and oversized signed/unsigned numbers.
  `nativeIntegralReasonBridgeIsAccepted` proves the actual SDK NSNumber/rawValue boundary plus Int/integral numeric bridging.
  `publicAppcastItemAdapterCopiesOnlyApplicableMetadata` uses public `SUAppcastItem(dictionary:)`, enclosure `{url: "https://example.invalid/Glimpse.dmg", sparkle:version: "19"}` and `sparkle:minimumSystemVersion`/`sparkle:maximumSystemVersion`; require the item and assert actual stored strings before driver projection.
  Retain the expected deprecated-constructor diagnostic; this fixture tests metadata, not flags/OS selection. No private APIs/KVC/fake native objects.
  `requirementValidationPreservesReason` covers nil/wrong item, blank/non-ASCII/internal-control/four-component thresholds, valid1–3 components/outer whitespace, length32 accepted/33 omitted, and conflicting item data. Assert only wrong detail disappears.
- [x] **6. Add lifecycle/freshness assertions with existing fixtures.** `guidanceSurvivesNativeDismissalWithoutDeadline` covers all five guidance reasons, one ack, no new delay and preserved result through dismissal.
  Extend cancelled-latest replacement tests with each guidance result; resume cancelled delay successfully and await its return before asserting no overwrite. Preserve latest→latest and delay-failure coverage.
  Extend acknowledgement reentrancy to guidance→dismiss/offer/ready/progress/error/latest/check; assert one ack, state already visible inside ack and no later callback overwrite.
  Extend terminal-finished preservation and owned-choice tests: pending offer/ready UUID persists until native dismissal; Check blocked; retained old controls cannot consume newer IDs.
  `guidanceCheckRevalidatesEligibilityAndAdmitsOnce` covers observation/live disagreement, disabled→enabled, synchronous `.checking`, double press, no restart and new latest/error/offer/guidance outcomes.
  Use controlled continuations/drain, not real sleeps or unbounded waiting; serial native sessions cannot generate out-of-order results independently of their declared callbacks.
- [x] **7. Run driver GREEN command and inspect receipts/xcresult.** Exact reason/lifecycle tests and unchanged UX-02 suites pass, with pins/source stable across the run. Record name/case counts without double-counting parameterized cases.
- [ ] **8. Commit the scoped driver gate.** Stage only owning source/tests/planning files; use normal local hooks and a concrete message such as `fix: preserve Sparkle no-update reasons`. Do not push/publish an incomplete About projection.

## Task 2: exact About guidance, full production rendering and delivery bookkeeping

**Files:** About source/tests; final updater tests if fixture assertions need shared helpers; version/readiness/product documents.
**Consumes:** Task1 models/classifier and existing injected updater/client/owned-host interfaces.
**Produces:** complete accepted reason UI, production-injected full About rendering seam, actionable AX tests and scoped release readiness.

- [ ] **1. Write About behavioral RED tests.** `noUpdateGuidanceHasExactCopyAndActions` invokes genuine native errors through the driver for each reason and asserts the matrix below, no invalid install/skip/relaunch/Dismiss controls and both named actions.
  `latestCopyReportsCheckOutcome` asserts `No newer update was found` and absence of the old “latest version” headline.
  `guidanceEligibilityRefreshesAndPressRevalidates` performs real owned AX presses with false→true eligibility and live eligibility loss before notification; expect zero rejected calls, one accepted call and `.checking`.
  Run About RED command; Task1's generic presentation/latest wording must fail the specific copy assertions.
- [ ] **2. Implement the reason projection in `AboutUpdateSection`.** Use existing `statusText`, `checkButton`, `releasesLink`, AppDesign padding/spacing; primary headline, secondary centered wrapping detail/recovery; no new non-latest icon.

| Reason | Headline | Optional detail | Recovery |
| --- | --- | --- | --- |
| latest | `No newer update was found` | None | None. |
| newerThanFeed | `You’re running a newer version.` | None | `Your installed version is newer than the version in the update feed. You can keep using this version.` |
| systemTooOld | `This update needs a newer macOS version.` | `Requires macOS {minimum} or later.` | `Check Software Update in System Settings, then check again.` |
| systemTooNew | `Your macOS version is newer than this update supports.` | `This update supports up to macOS {maximum}.` | `View releases for compatibility details, or check again later.` |
| requiresAppleSilicon | `This update requires Apple silicon.` | None | `It can’t be installed on this Intel Mac. View releases for compatibility details.` |
| unknown | `No installable update was found.` | None | `Check again or view Glimpse releases on GitHub.` |

  Non-latest action labels: `Check for updates`, `View Glimpse releases on GitHub`; visible titles `Check for Updates`, `View Releases`. Disabled Check adds exactly `Checking is temporarily unavailable.` Link remains enabled and targets only the fixed official URL.
- [ ] **3. Add the legitimate full-view seam.** Change private `AboutView` to internal and give it `init(updater: SparkleUpdater = .shared)` initializing the existing State from that instance. Production `AboutWindow.show()` continues to construct `AboutView()`; injected tests must never evaluate/use `.shared`.
  Extend current `AboutUpdateHost` with initializer parameter `fullAbout: Bool = false` and optional `appearance: NSAppearance? = nil`; its content factory uses the actual `AboutView(updater: fixture.updater)` for full mode, the existing section otherwise.
  Keep offscreen/non-key/non-main ownership and injected `openURL`. Settle and close each host; do not invoke `AboutWindow.show`, activate the app or duplicate the product layout.
- [ ] **4. Verify reopen, link and genuine full About rendering.** `guidanceReopenAndReleaseLinkPreserveDriverOwnership` reconstructs the same host, asserts no new start/check/ack, presses link, verifies sole official receipt and unchanged state/UUIDs/backend counts.
  Add `fullAboutGuidanceFitsAndRemainsAccessible` in the same host suite; serialize owned AppKit cases to avoid competing run-loop/layout work.
  Parameterize light/dark, five guidance reasons, with/without valid OS detail and disabled footnote; include the longest valid32-character detail. Exercise full production About content at its300-point width and actual fitting height, with app header, diagnostics/footer still present.
  Assert readable text, correct action roles/enabled sets, finite fitting/content bounds and no clipped/overlapping controls; retain full-view image renders outside source and inspect them visually. Make geometry/image access a small extension of the existing host, not a duplicate renderer/window manager.
  If production fit fails, fix its actual sizing/wrapping; do not mask it by inflating only the fixture or claim section-only renders satisfy design acceptance9. A remaining signed native fit check stays explicit.
- [ ] **5. Run About GREEN command, then the driver command only if Task2 changed driver/fixture behavior.** Record exact copy/action/geometry and visual acceptance separately from physical keyboard/VoiceOver. Existing initialization/error/choice paths still pass.
- [ ] **6. Finalize candidate version and readiness in this owning task.** Fresh-check source/version; if still1.4.11/build18, set all four marketing values to1.4.12, all four build values to19 and README badge to1.4.12. If main advanced, reconcile monotonically rather than overwrite blindly.
  Populate the scoped acceptance document plus inventory/roadmap with implementation, measured tests/rendering, SDK adapter evidence and native gaps. Keep tracked plan status honest and provenance links valid.
  Check `python3 tools/scripts/release-control.py version --root .` and `python3 tools/scripts/check-dependency-pins.py --root .`; these must pass with the same lock hashes.
- [ ] **7. Run the ordinary whole-source quality gate before success claims/commit.**

```sh
python3 "$UPD03_WRAPPER" "$UPD03_EVIDENCE/final-quality-1" env \
  GLIMPSE_BUILD_ROOT=/Volumes/xHome/Github/Glimpse/build \
  GLIMPSE_RESULTS_DIR="$UPD03_EVIDENCE/final-quality-results-1" \
  tools/scripts/quality-gate.sh
```

  Require terminal EXIT0, actual app/Core/tooling/monitoring results, before/after pins identical and current source matching receipts. Preserve logs/xcresults; do not repeatedly broaden/re-run unchanged successful checks without a new concern/change.
- [ ] **8. Obtain independent whole-branch A1–A8 review.** Reviewer reads accepted spec, all source/tests/docs/version diff and exact-source evidence; prioritize A1 text/actions, A4 state/callback/security/latest expiry, A7 strict parsing/no retained native objects and A8 meaningful regressions. Resolve findings and rerun only affected checks plus final exact-source quality after changes.
- [ ] **9. Commit/release through ordinary protected delivery.** Stage only the scoped files, use normal hook enforcement and synchronized version commit where repository convention calls for it; update PR title/body around final behavior and truthful validation.
  Push branch, create/attach PR, refresh exact head/base/main/run/check observations and trusted admission; pause merge during unchanged-main manual release/reruns. Failed/unavailable admission blocks integration, not unrelated development.
  After protected merge, verify terminal exact-main Release/Recovery and public signed/notarized DMG, manifest, appcast/Sparkle signature and official installation/launch. Record delivery separately; do not call queued checks, fixtures or artifact downloads release success.

## Native limits and final handoff

This plan proves source contracts/injected production-driver and owned full-view behavior; it does not reproduce real incompatible feeds, Intel eligibility, physical keyboard/VoiceOver, retry/install/relaunch, restart, endurance or performance.
Real compatibility cases require a separate controlled native SDK/feed harness; actual ARM64-ineligible acceptance requires Intel hardware, not translated execution on Apple silicon.
Never alter official installed feed/security settings for those checks. Preserve the user-deferred restart limit and unexplained other-Mac crash.
Root can execute accepted scope without routine human approval; a later specific physical action/permission remains separate.

## Self-review

Spec requirements map to Task1 classification/ownership/expiry and Task2 exact copy/actions/full About/acceptance/delivery.
All five Review Focus classes have named owning tests; all model/helper names are consistent; Task1 remains compile-complete.
The full About production seam covers acceptance9 without copying layout or activating a window. Integral/Bools and public-item boundaries are concrete and separately scoped.
No product behavior choice remains open; native opportunities are evidence limits. This plan claims no implementation/test/delivery completion.
