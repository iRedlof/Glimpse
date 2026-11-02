# Reliable Calendar Show Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make explicit Show and already-running app reopening reliably open or raise the calendar without toggling away its state.

**Architecture:** One main-actor command routes AppIntent and reopen requests to the existing status owner. Its throwing Show distinguishes hidden reopening from visible raising; the existing toggle remains separate.

**Tech Stack:** macOS 14+, Swift 6 complete concurrency, AppKit, SwiftUI, AppIntents, TCA; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-02-calendar-show-design.md`

## Global Constraints

- Preserve production calendar permissions/data, stored preferences, signing credentials and both immutable dependency locks.
- Preserve the `XCTestBundlePath` startup guard and quiet login launch.
- Tests own actual offscreen panels and injected stores/inert content; do not create real status items or replace `NSApp.delegate`.
- Do not add unconditional app activation, URL/scripting control, buffering or arbitrary readiness delays.
- Explicit Show uses `panel.isVisible`; existing click/hotkey toggle semantics remain.
- Keep source, fixture, installed native and artifact acceptance distinct.
- Candidate 1.4.13/build20: synchronize all four marketing versions/build numbers, README and evidence-backed readiness before protected delivery.
- Original other-Mac crash is unexplained; real restart is deferred; no performance/endurance outcome is presumed.

## Review Focus

1. An ordered-in but occluded or text-editing panel must retain state, first responder and lifecycle hooks across repeated Show.
2. Nil/nonfinite/invalid geometry must not partially prepare a hidden panel or hide an already-open panel.
3. Real intent execution and both reopen flags must reach the owned Show operation; missing routing must surface an error.
4. Startup registration must neither defeat the test-host guard nor turn quiet login launch into presentation.
5. Existing click/hotkey toggle, pin and cross-screen paths must preserve their presentation/reset behavior.

---

### Task 1: Owned Show routing and reusable-panel presentation

**Files:**
- Modify: `Glimpse/CalendarStatusItem.swift`
- Modify: `Glimpse/AppIntents.swift`
- Modify: `Glimpse/GlimpseApp.swift`
- Test: `GlimpseTests/CalendarStatusItemTests.swift`
- Modify: `Glimpse.xcodeproj/project.pbxproj`, `README.md`, `.github/release-readiness.json`
- Document: this plan/spec, `docs/product-inventory.md`, `docs/stability-roadmap.md`, `docs/superpowers/reviews/2026-11-02-calendar-show-acceptance.md`

**Interfaces:**
- Consumes: existing `CalendarPanel.prepareForReopen()`, `updatePlacement(statusItemFrame:visibleFrame:)`, panel/store lifetime and guarded AppDelegate startup.
- Produces: `CalendarStatusItem.showCalendar() throws`; `CalendarShowCommand.shared`, `register(_ target: (@MainActor () throws -> Void)?) -> (@MainActor () throws -> Void)?`, `requestShow() throws`; `CalendarShowError: LocalizedError` cases `notReady`, `unavailableAnchor`, `invalidGeometry`.
- Geometry seam: `CalendarStatusItem.PanelAnchor` carries `statusItemFrame: NSRect`, `visibleFrame: NSRect`; `init(anchorProvider: (@MainActor () -> PanelAnchor?)? = nil, panelFactory: @escaping @MainActor (NSRect, CGFloat) -> CalendarPanel = production factory, toggleVisibility: (@MainActor (CalendarPanel) -> Bool)? = nil, sameScreen: (@MainActor (CalendarPanel) -> Bool)? = nil)`.
- AppDelegate: production `override init()`; owned fixture initializer `init(calendarStatusItem: CalendarStatusItem, showCommand: CalendarShowCommand)`.

- [x] **Step 1: Write unchanged-source behavioral RED**
  Add serialized main-actor `CalendarShowTests.showIntentWithoutReadyTargetReportsFailure` in the existing test file. Record `NSApp.delegate` dynamic type and concrete cast outcome, then `await #expect(throws: (any Error).self) { _ = try await ShowCalendarIntent().perform() }`. Guarded test startup leaves no production presentation target.

- [x] **Step 2: Run RED**
  Run bounded arm64 Debug app tests with immutable packages, existing cached `/private/tmp/glimpse-ux02.dkbzt19q/DerivedData`, unsigned signing, `-skipMacroValidation`, 30-second per-test timeout and `-only-testing:GlimpseTests/CalendarShowTests`. Keep a unique xcresult/log/source/pin receipt outside tracked source.
  Expected: test executes and fails because `perform()` returns success without delivery; no missing-symbol failure.

- [x] **Step 3: Write real owned-panel regressions**
  Build a test utility using injected fixed time, fixture preferences, `.notDetermined` event authorization and inert view; record any unexpected production/event I/O. Assert:
  - `repeatedVisibleShowPreservesPanelAndState`: one panel, selected date/month/preferences/pin unchanged, zero new show/hide hooks.
  - `visibleShowPreservesNativeEditor`: actual owned text field/editor, draft/selection/first responder unchanged.
  - `hiddenShowResetsOnceAndReusesPanel`: Today/current month, one prepare/show per reopen and one allocation.
  - `unavailableOrInvalidAnchorFailsBeforeHiddenPresentation`: no allocation/show hook for nil/zero/nonfinite geometry.
  - `visibleShowReanchorsOrRetainsValidFrame`: changed valid anchor moves the same panel without reset; invalid/nil anchor preserves its frame.
  - `actualIntentUsesOwnedShow`: actual `perform()` raises the fixture twice, preserves state, and propagates a presentation error.
  - `reopenShowsForBothVisibilityFlags`: actual callback raises the owned fixture for both flags and returns false.
  - `guardedStartupDoesNotRegisterOrShow`: actual guarded didFinish callback leaves the command unready and the fixture untouched.
  - `existingToggleKeepsHideOpenPinAndCrossScreenBehavior`: invoke the actual toggle using injected visibility/screen observations; assert hide/reset/prepare effects including completion of the existing delayed cross-screen path.
  Use defer to restore shared registration, close only fixture windows and remove observers. Expectations use literal state/frame values.

- [x] **Step 4: Implement the minimal interfaces**
  Preserve default toggle behavior. Factor normal anchor acquisition and guarded hidden presentation; visible Show updates placement when valid and raises without prepare/orderOut. Register a weak production target after guarded setup; actual intent uses the command. Reopen requests it for either flag and logs any error. No new CalendarPanel/Core lifecycle redesign.

- [x] **Step 5: Run focused affected suites**
  Use Step2's bounded command with `CalendarShowTests`, `CalendarStatusItemTests`, `PanelLayoutTests`, and `CalendarInputTests`.
  Expected: all executed names/cases pass, source/pins unchanged during the run, no unexpected fixture I/O; retain raw diagnostics without treating them as native acceptance.

- [x] **Step 6: Prepare candidate and ordinary commit**
  Synchronize version1.4.13/build20 and write truthful scoped acceptance/inventory/roadmap. Readiness stays pending until actual role decisions exist. Commit explicit files through the normal hook with a unique retained whole-quality result directory.
  Expected: normal commit succeeds with zero whole-gate failures and unchanged pins; record the exact commit/tree and counts.

- [ ] **Step 7: Independent review and final readiness**
  Use one fresh whole-branch A1–A8 reviewer with this spec, Review Focus verbatim and the ledger. Adjudicate every finding/declined boundary; one Important/Critical fix pass, Minor deferred. Record actual Product/UX/Code/QA decisions and readiness evidence; any final tracked edit uses the ordinary required hook.
  Expected: no unresolved Critical/Important issue, valid readiness CLI, exact final staged-source quality accepted. Native limits remain explicit.

- [ ] **Step 8: Protected delivery and autonomous native checks**
  Integrate against fresh canonical main/admission/checks/current runs; sequence after PR18 delivery without blocking independent development. Verify terminal exact-main workflow and public signatures/feed/notarization, then use the existing authorized recoverable official-app installer. Check normal Finder reopen and the owned Shortcuts utility with CUA; observe the actual panel before claiming navigation works. Continue safe independent roadmap work if physical acceptance remains unavailable.
  Expected: record each actual boundary independently; no reboot/logout, permission expansion, fabricated global-key acceptance or crash/performance resolution.

- [ ] **Step 9: Complete task and preserve decisions**
  Use task-done against the accepted focused/mandatory gate receipts, record all rulings, update actual delivery status and finish only this plan's workspace once its required work is complete.
  Expected: terminal evidence and source identity support every completion claim; unresolved native outcomes remain explicit.

## Self-review

One coherent task owns the coupled command/presentation/lifecycle change. Each spec behavior maps to Steps1–5 and all five review conditions have real fixture cases. No new source registration or Core change is required. The chosen explicit failure avoids speculative readiness buffering; actual cold/system ordering remains native-open. User autonomy overrides routine approval/handoff questions. Baseline source808f/tree2b has a fresh accepted464-test gate; verify identity instead of rerunning unchanged baseline tests.
