# Calendar Panel Screen Fit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep calendar/preferences within the usable screen and provide reliable vertical overflow navigation.

**Architecture:** Pure placement and wheel-routing policies feed one MainActor observable layout state and persistent measured SwiftUI viewport. CalendarPanel retains its bounded intrinsic-size debounce and uses the same geometry policy for show/resize/refresh. Root owns staged integration and protected delivery.

**Tech Stack:** AppKit, SwiftUI/Observation, Swift6, Swift Testing, existing TCA.

**Spec:** `docs/superpowers/specs/2026-11-01-panel-screen-fit-design.md`

## Global Constraints

- Base `302a260e736f8d9cdc14684b1f1281f7768588fa`; isolated `codex/panel-screen-fit` in `/Users/rohit/.codex/worktrees/stability-ux/Glimpse`.
- macOS14.0, Swift6.0/complete, existing TCA/Sparkle and15 pins in both lockfiles unchanged; no new package.
- Panel316, body300, caret12, menu gap6, left/right/bottom margin10, caret inset16, tolerance0.5, resize debounce0.05 seconds.
- Supported visible width≥336; finite positive geometry and desired height, available total height≥13. Invalid input returns nil; no invalid AppKit frame.
- No production permissions/data, persisted-setting changes, application installation/restart, machine restart/logout or UI automation by implementers/reviewers. App test host's existing XCTestBundlePath guard must remain.
- No source commit/push by workers. Root makes one accepted controller commit after all tasks and fresh previous-release gate; normal mandatory hooks, protected PR and exact-main Release/public/native verification. This plan uses the current gates for the affected production line. Under the updated master goal, unrelated independent development must not be globally blocked by a failed release; gate-boundary improvement is a separate backlog item.
- Marketing1.4.9/build16 only in Task3; all4+4 settings, README and readiness synchronized. Do not publish readiness before actual acceptance.

## Review Focus

- Negative-origin/side-Dock displays and menu bars below a screen's top: chosen visibleFrame controls all placement (Task1 geometry table).
- Long wrapped errors and content growth/shrink: natural measurement remains independent of viewport and every row stays reachable (Task2 controlled hosting fixtures).
- Partial wheel gestures crossing regions/overflow/recording: no stale accumulation or combined month+viewport movement (Task1 router tests, Task2 resets).
- Reused panel and display/wake refresh: no onAppear dependency, selected date resets only on reopen, frame changes converge (Task2 lifecycle/placement integration tests and source review).
- SwiftUI/hosting feedback with nearly identical measurements: no observable/frame mutation below0.5 and unchanged placement remains a fixed point (Task2 state/hosting tests).

---

### Task 1: Pure placement and wheel policy

**Files:**
- Create `Glimpse/PanelGeometry.swift`, `Glimpse/CalendarScrollRouter.swift`.
- Create `GlimpseTests/PanelGeometryTests.swift`, `GlimpseTests/CalendarScrollRouterTests.swift`.
- Modify `Glimpse.xcodeproj/project.pbxproj` only for unique DD-prefixed source/test registration; no version/settings change.

**Interfaces:**
- `struct PanelPlacement: Equatable, Sendable { let frame: CGRect; let caretXOffset: CGFloat; let maximumHeight: CGFloat }`.
- `enum PanelGeometry`: static constants `panelWidth=316`, `contentWidth=300`, `caretHeight=12`, `gapBelowMenuBar=6`, `edgeMargin=10`, `caretInset=16`, `tolerance=0.5`.
- `static func placement(statusItemFrame: CGRect, visibleFrame: CGRect, desiredHeight: CGFloat) -> PanelPlacement?`.
- `static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool` compares all four components with strict<0.5.
- `struct CalendarScrollRouter`: `enum Direction: Equatable, Sendable { case previous, next }`, `enum Phase: Equatable, Sendable { case none, began, changed, ended, cancelled }`, `struct Result { let direction: Direction?; let consumesEvent: Bool }`, private accumulator/gesture ownership, `mutating func reset()`, `mutating func suspendNavigation()`, `mutating func route(delta: CGFloat, panelVisible: Bool, eventIsForPanel: Bool, overCalendar: Bool, recordingShortcut: Bool, contentOverflows: Bool, phase: Phase = .none, momentumPhase: Phase = .none) -> Result`.
- Compact eligible finite nonzero delta: clamp±1.5, accumulate, strict>5→previous/<−5→next/reset; consume even before threshold. For unphased input, ineligible/nonfinite resets and passes; zero passes without action. Preserve accumulation across eligible discrete events.
- Phased begin resets accumulation and chooses calendar consumption only if eligible; otherwise chooses viewport pass-through. A changed/ended/momentum event without a known begin conservatively chooses viewport. Calendar ownership becomes suppressed consumption (no month action) after loss of eligibility, nonfinite input or suspendNavigation; viewport ownership always passes. Ended/cancelled events never navigate. Finger ended retains ownership for later momentum; cancellation/momentum ended clear after returning the correct ownership. Fresh finger began or discrete input ends old ownership. Hidden/other-window events pass and fully reset. `suspendNavigation` clears accumulation and suppresses active calendar ownership, preserving viewport ownership; `reset` clears both.

- [ ] **Step 1: Write behavioral regressions against the released arithmetic/routing before replacing it.** Preserve RED xcresult/logs separately from compilation attempts. The concrete fixture `(status:1000,876,100,24; visible:0,48,1440,828; desired:900)` must produce frame `(892,58,316,812)`, caret158, maximum812; old requested y42 must fail containment. Desired824 also caps812; desired432→y438. Left/right/side Dock and negative origin must respect10-point margins; above-screen status top must clamp safely to visible maxY, and invalid/nonfinite/narrow/impossible-anchor inputs return nil. `framesMatch` false for x/y/width/height changes≥0.5 and true below0.5. Router RED tests must expose the old overflow+navigation/pass-through conflict and stale partial accumulation; add phased calendar→overflow consumption/no action, overflow→compact pass-through/no action, finger end→momentum begin retains owner, momentum end/cancel clears, unseen changed passes, context suspension consumes only matching visible panel, fresh begin restores eligible navigation. Only compileable behavioral failures count as RED.
- [ ] **Step 2: Run focused tests and confirm behavioral failures.** Resolve pinned dependencies once into owned scratch and preserve both lockfile hashes. Use xcodebuild schemeGlimpse, destinationplatform=macOS, `-skipMacroValidation -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO test`, `-only-testing:GlimpseTests/PanelGeometryTests -only-testing:GlimpseTests/CalendarScrollRouterTests`, owned derivedData/resultBundle paths. Capture actual exit status and xcresult summary; retain source snapshots/hashes. No live app actions.
- [ ] **Step 3: Implement the interfaces.** Center/round x then clamp within visible bounds; anchor top to min(status.minY−6,visible.maxY); maximumHeight=top−(visible.minY+10). Cap desiredHeight to maximumHeight, enforce minimum13 and valid width≥336. Clamp caret to[16,300]. Validate derived values as well as raw values. Implement pure router and reset contracts.
- [ ] **Step 4: Run focused GREEN once, self-review and freeze.** Cover strict thresholds, four±1.5 contributions, oversized finite deltas, partial accumulation→overflow/settings/hidden/other-window/recording/NaN→compact first contribution does not navigate; repeated geometry deterministic. Record actual tests/pass/fail/skip, pins unchanged, exact changed file hashes, owned scratch cleanup. Full quality belongs Task3/controller.
- [ ] **Step 5: Report without committing.** Write full Task1 report with RED/GREEN evidence and concerns to the workspace report path supplied by root. Fresh task reviewer must pass spec and code quality before Task2.

### Task 2: Measured viewport and native integration

**Files:**
- Create `Glimpse/PanelLayoutState.swift`, `Glimpse/PanelViewport.swift`.
- Modify `Glimpse/CalendarPanel.swift`, `Glimpse/CalendarStatusItem.swift`, `Glimpse/CalendarPopoverView.swift`.
- Create `GlimpseTests/PanelLayoutTests.swift`; extend `GlimpseTests/CalendarInputTests.swift` if needed for integration.
- Modify project only for unique source/test registration; no version change.

**Interfaces:**
- Consumes Task1 `PanelGeometry`, `PanelPlacement`, `CalendarScrollRouter` exactly.
- `@MainActor @Observable final class PanelLayoutState`: read-only-to-view `naturalContentHeight: CGFloat=420`, `maximumHeight: CGFloat=800`, `caretXOffset: CGFloat=158`; computed `viewportHeight`, `totalHeight`, `isOverflowing`; `func updateContentHeight(_ height: CGFloat)` accepts finite positive values with change≥0.5; `func updatePlacement(maximumHeight: CGFloat, caretXOffset: CGFloat)` validates values and mutates changed fields only at≥0.5. Viewport=min(natural,maxHeight−12), total=viewport+12, overflow=natural−viewport>0.5.
- `struct PanelViewport<Content: View>: View`: `init(layout: PanelLayoutState, @ViewBuilder content: () -> Content)`. Persistent vertical ScrollView, natural-width300 fixed vertical child measurement, constrained viewport height, disabled scroll when fits. Measurement callback updates state outside body/layout computation; no replacement subtree or render-time side effects.
- `CalendarPanel` owns `let layoutState: PanelLayoutState`; existing init remains compatible; `func updatePlacement(statusItemFrame: NSRect, visibleFrame: NSRect)` stores valid anchor/bounds, updates layout budget/caret and applies same geometry. Existing `caretXOffset` may bridge to layout state if compatibility needs it. Invalid geometry preserves last valid state, logs error.
- Root view receives shared layout state (a default state is permitted only for panel-less fixtures). Use ScrollViewReader with IDs `panel-content-top` and `panel-ai-input`; showingPreferences changes and panelDidShow reset top, aiFieldActive=true scrolls field into view.
- `CalendarPopoverView.nonisolated static func scrollPhase(_ phase: NSEvent.Phase) -> CalendarScrollRouter.Phase`: began/mayBegin→began, cancelled→cancelled, ended→ended, changed/stationary→changed, none→none. Precedence cancelled, ended, began/mayBegin, changed/stationary. Native event phase and momentumPhase both flow to router.

- [ ] **Step 1: Add meaningful failing layout/integration regressions.** State tests: natural300,max812→viewport300,total312,no overflow; natural900,max812→viewport800,total812,overflow; growth/shrink; invalid values ignored; sub0.5 changes leave values identical. Controlled generic hosting fixtures (no live stores) assert actual root intrinsic/fitting height≤budget while natural content900 remains900; long wrapped text growth/shrink and repeated settling. Anchor refresh must not send prepareForReopen; reopen reset/wheel reset/AI anchor must use explicit notifications/state changes. Expose narrow test seams only where needed, not a second implementation.
- [ ] **Step 2: Run scoped compileable RED tests.** Same owned/pinned xcodebuild process as Task1; select PanelLayoutTests and existing CalendarInputTests. Use a unique owned internal `/tmp` directory for DerivedData, cloned packages and TMPDIR, matching the established quality pipeline; retain commands, logs, source snapshots, exit receipts and xcresults under an owned validation evidence directory. Keep the unchanged test startup guard and `CODE_SIGNING_ALLOWED=NO`; no signing/protection bypass. Bound each test attempt to ten minutes. If the owned host starts but produces no test output for 90 seconds, pause and report exact owned PIDs to root for diagnosis; workers do not signal processes. Preserve failing assertion evidence and source snapshot.
- [ ] **Step 3: Implement state/viewport/integration.** Keep caret12 outside ScrollView at actual panel width316; material/rounded clipping fixed around300-point viewport. Child owns existing padded stack including all preferences/errors/events/footer. No PreferencesView behavior changes. Preserve reader/recorder/AI state across overflow. Replace wheel accumulator with router and native phase mapping; suspend on hover exit/recording/overflow changes, reset on hide/reopen, honor returned consumption even after content reflow. Store anchor/bounds for resize; reject invalid intrinsic values and compare all frame components via framesMatch. Retain50ms debounce/cancellation/first-show behavior. StatusItem chooses visibleFrame, calls updatePlacement before orderFront, and recomputes visible placement after display parameters/wake/menu item width updates without reopening/resetting selection. New observer token gets explicit removal with Swift6-safe lifetime.
- [ ] **Step 4: Run covering GREEN once and inspect convergence.** Include Task1 suites plus PanelLayoutTests/CalendarInputTests/CalendarStatusItemTests. Actual controlled natural/intrinsic/viewport values and settled repeated-pass count belong evidence; do not call source assertions native reachability proof. Confirm no new warnings, pin hashes unchanged, production process/preferences untouched, scratch inactive then removed.
- [ ] **Step 5: Freeze report for fresh spec/code and independent product/UX/QA review.** No commits/pushes/build suite duplication. Record every changed hash and fixture limits. Root retains final broad review and signed native validation.

### Task 3: Accepted release metadata and protected delivery

**Files:**
- Modify project4 MARKETING_VERSION→1.4.9 and4 CURRENT_PROJECT_VERSION→16.
- Modify README badge→1.4.9.
- Modify `.github/release-readiness.json`.
- Create `docs/superpowers/reviews/2026-11-01-panel-screen-fit-acceptance.md`.
- Include root-owned `AGENTS.md`, `docs/product-inventory.md` and the current operating section of `docs/stability-roadmap.md`, reconciling the updated master goal and already-shipped findings. Do not rewrite historical acceptance evidence or claim unperformed validation.

**Interfaces:**
- Consumes frozen Task1/Task2 source, actual regression/hosting evidence, fresh independent review verdicts; no product-code edits.
- Produces synchronized version/build/readiness with evidence path to committed acceptance, preserving limits on physical screen/native/reboot/other-machine validation.

- [ ] **Step 1: Write acceptance and metadata only after actual source gates pass.** Distinguish requested geometry, controlled hosted layout, source review and installed native evidence. Product/UX/code/QA status passed must refer to concrete acceptance evidence, with pending postpublication native checks explicit.
- [ ] **Step 2: Validate metadata with `release-control.py version`, pin checker, exact change count and staged diff; fresh task review and whole-branch A1–A8 review.** Controller stages all accepted changes, confirms no outside-scope file, retains durable reports.
- [ ] **Step 3: Root runs fresh prior-main admission, ordinary commit (mandatory staged-source full quality), ordinary push (mandatory gate), protected PR hosted revision checks and ordinary expected-head squash merge.** Attach created PR. Every head/synthetic/main revision must be tested. No bypass/signing/credential/protection changes.
- [ ] **Step 4: Verify whole exact-main Release/Recovery plus public tagged/latest bytes, manifest/feed/Sparkle/notarization/team/signatures and cleanup.** A failing release blocks this iteration's integration/promotion. Investigate and verify exact Recovery while continuing safe independent work; the separately tested CD-01 correction moves the existing global hook admission to the appropriate boundaries. Preserve existing checks until that correction is accepted. Independently accept actual artifacts.
- [ ] **Step 5: Root installs verified public update under existing authorization and performs native panel/preferences/scroll/pin/reopen/resource checks as UI access permits.** Preserve rollback/preferences/production permissions. Carry unsupported physical configurations and user-deferred restart as limits. Retain all receipts/rulings, close only this completed plan workspace, keep hourly monitor and broader goal active.
