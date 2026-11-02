# A11Y-01a Names, Values and Icon Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give nine existing preference controls useful names and state, name date-search dismissal accurately, and provide actual disjoint 28/24-point icon targets without changing input or lifecycle behavior.

**Architecture:** Keep names, native controls and target tokens in the existing app view layer. Inject the existing hotkey model and a local notification center for whole-preferences fixtures; expose only the three actual calendar control rows needed for safe native action/layout tests, sharing those rows with production. Keep all stores, AI state, panel effects and external actions in their current owners; add no accessibility model or Core UI code.

**Tech Stack:** macOS 14.0+, Swift 6.0 complete concurrency, SwiftUI/AppKit, existing TCA and Observation, Swift Testing with public in-process accessibility.

**Spec:** [Accepted A11Y-01 design](../specs/2026-11-02-accessibility-controls-design.md), SHA-256 `b161057c13a9a9ec9b7eb17b644052ac66ce1eb7211b67b851f9d67d62a7cd75`; read its full A11Y-01a contract, `report.md`, `builder-review.md`, `root-acceptance.md` and `root-design-acceptance.json`. The accepted design is copied unchanged beside this plan; supporting accepted-design artifacts remain under `/Volumes/xHome/Github/Glimpse/build/validation/accessibility-design.58ie9seq`.

## Global Constraints

- Scope is **A11Y-01a: names, state, and icon targets.** A11Y-01b date native activation, ordinary keyboard traversal, initial/reopen focus and visible focus treatment remain open.
- Preserve **Swift 6, macOS 14 deployment floor, current TCA stores/actions/bindings and native styles. No new package or Core UI imports.**
- Preserve **316 pt root / 300 pt body**; date cells remain **30 pt high**, and pill/workday sizing remains unchanged.
- Five footer icons and three header icons receive **28 × 28 pt** actual hit rectangles; AI dismiss receives **24 × 24 pt**. Keep centered existing glyphs/colors and disjoint targets with **at least the existing 8 pt standard spacing** between neighboring header/footer controls.
- Put frame and rectangular `contentShape` inside each Button label. No overlay targets, text shrinking, wider panel, fixed overall content height or unrelated calendar-circle token.
- Use nonempty native Toggle/Picker titles with hidden visual labels; retain switch/mini styling, native role/value/menu behavior. Do not override native values or include “button,” “switch,” or “picker” in names.
- Keep display pill state in exact **On/Off** values and the expanded names below; preserve the existing one-action toggle and menu-bar notification.
- AI dismiss is **Close date search**, hint **Clears the query and closes date search.** Clear query/error, exit editing, keep the panel open; never call `deactivateTextInput` here. Dismiss remains absent during processing; no cancellation behavior is added.
- Conditional AI grouping repair requires an actual recorded accessibility-tree observation. No blanket second container label or assumption that current grouping is broken.
- Preserve `.focusable(false)`, keyboard/scroll monitors, editing and shortcut ownership, notifications, persistence/provider selection, pin behavior, reusable show/hide cleanup and scroll reset.
- Keep one persistent `PanelViewport`, guarded height observation, scroll ownership/momentum suppression and the single-image menu renderer/shared preview.
- Preserve calendar authorization/private data, production defaults, startup preferences, updater/diagnostics, external Calendar launch and Quit confirmation semantics.
- Fixtures use per-test injected dependencies and synthetic input. No `.live()` preference state, `.standard` defaults, shared hotkey/updater, real Carbon registration, EventKit/TCC/AI, browser, Calendar, About or Quit operation.
- Hidden hosts establish fixture behavior only. macOS 14/current-supported-OS VoiceOver, keyboard, constrained native reachability and signed panel lifecycle require separate evidence.
- Root uses the established inline execution method, no intermediate commits, one final independent A1–A8 source review, and the ordinary final staged-source commit hook as the sole local whole-quality pass. Root owns fresh versions, readiness, protected delivery/public verification and native acceptance.

## Review Focus

1. Mixed saved display values, especially “Mon”: each pill announces its own expanded name and current On/Off; pressing it changes only its corresponding preference once (Task 1).
2. AI preference turned off/on and picker selection changed: provider disappears/reappears with retained value; native picker selection persists once without display/calendar cross-notification (Task 1).
3. Pointer near an icon edge, a neighbor gap or disabled Today: the allocated rectangle activates only its intended action, gaps activate none, and disabled Today performs no action (Task 2).
4. Preferences open in a constrained viewport with legacy/overlay scrollers: targets stay inside the 300-point body, remain reachable after scrolling and retain state; layout converges without replacing the viewport (Tasks 2–3).
5. Active date search with an error, or processing: editor and dismiss remain separate usable controls; dismissal clears/error exits once and processing offers no dismiss action or implicit submit (Task 3).

---

## Baseline and exact responsibility map

Planning inspected clean `/Users/rohit/.codex/worktrees/stability-ux/Glimpse`, HEAD `50bb17e0d5941e375767b0f32bc6cfbd1900cacc`, tree `12af40599f8f064acd049e676f329df8ba24db69`. Locally recorded `origin/main` is protected squash `f88197ba9bf68a088f6c4b9c77984024086d07d4`, the identical tree and parent `06e48b4fcf10c4af7abbe6a457c63c33ed73bb83`. No fetch occurred. The three production files below byte-match design-source `ec5e15c4f238e2d3eeb114bb2bdcf1cde04dfd96`.

| File | SHA-256 / responsibility |
| --- | --- |
| `Glimpse/PreferencesView.swift` | `5d1a4cf57b94ef87387beb91ceb83b2c5003bf58600268cb1e05f63105ef254f`; Task 1 names, values and minimal whole-view injection. |
| `Glimpse/CalendarPopoverView.swift` | `746564b131c433c3ca7b34fca9de2ea937b5bcc6819c634b44c44d5b2f56db92`; same app owner across Tasks 2–3: shared header/footer/date-search rows; original store/state/effect/action ownership. |
| `Glimpse/AppDesign.swift` | `eea54c06bc8b61e596078b7cd480b2737541efa5d84c8ddceabbc32021b8a699`; Task 2 named control target tokens used by Task 3. |
| Create `GlimpseTests/AccessibilityTestHost.swift` | Task 1 test-only public AX traversal, bounded settling, per-fixture dependencies and owned-window point delivery reused by Tasks 2–3. |
| Create `GlimpseTests/PreferencesAccessibilityTests.swift` | Task 1 actual full preferences controls/state/actions; no parallel implementation ownership. |
| Create `GlimpseTests/CalendarControlAccessibilityTests.swift` | Tasks 2–3 actual shared header/footer/date-search rows, AX activation and pointer receipts. |
| Create `GlimpseTests/AccessibilityViewportTests.swift` | Tasks 2–3 production row/viewport composition and normal/constrained legacy/overlay hit-layout checks. |
| Modify `Glimpse.xcodeproj/project.pbxproj` | Add each test file to PBXFileReference, PBXBuildFile, GlimpseTests group `BB00000000000000000008` and test Sources `BB00000000000000000005`; use unused DD-prefixed IDs checked at execution. No new app file or scheme/target change. |
| Root-only accepted plan/design, scoped review, inventory/roadmap/readiness/project versions/README | Record achieved evidence and final delivery; choose no future version from this snapshot. |

The scheme already runs app-hosted `GlimpseTests` (`BB00000000000000000001`), with `TEST_HOST` Glimpse and its app target dependency. Preserve `GlimpseApp.swift:9–17`'s `XCTestBundlePath` startup guard. Existing `HotkeyFixture`/`FakeHotkeyBackend` are test-target-visible and supply disposable suite defaults and fake Carbon tokens; reuse them without calling `.shared`. `AboutUpdateSectionTests.swift` demonstrates fixture-local `.environment(\.accessibilityEnabled, true)`, offscreen non-key/main hosting, bounded AppKit run-loop pumping and public ObjC AX dispatch; do not extract or edit that unrelated fixture.

Before execution, root refreshes actual checkout/main/readiness, accepted UX-02 delivery scope, rules, hashes and locked graphs. The supplied Release/public/install results are parent evidence, not independently reverified by this planning task. UX-02 official About keyboard/VoiceOver/actions, original other-Mac crash, real restart and the parent-labeled v149/v150 calendar physical checks remain open. Do not treat inventory's older snapshot or successful v1.4.10/build 17 artifact installation as complete native acceptance.

## Shared fixture and verification contract

Produce test-only `@MainActor AccessibilityTestHost.init<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content)`, `elements() -> [AccessibilityTestNode]`, `control(named: String) throws -> AccessibilityTestNode`, `settle(until: () -> Bool) async throws`, `click(atScreenPoint: NSPoint) async throws`, and `close() -> Void`. `AccessibilityTestNode` exposes public role/label/value/help/frame/enabled/children/parent/hit-test/press through optional ObjC dispatch, as the About fixture does; do not require formal `NSAccessibilityProtocol` conformance, reflect private SwiftUI objects or use private selectors.

Host actual production views in a per-test offscreen `NSWindow`/`NSHostingView<AnyView>` with public `canBecomeKey`/`canBecomeMain` overrides false. Enable AX only in the fixture environment. Traverse public children with identity deduplication. Pump layout/display/default AppKit run loop plus `Task.yield()` to a predicate, bounded to one second; a timeout reports the observed tree/frame/receipts and fails the fixture. Never activate the app, change global AX/VoiceOver settings, or send events through `NSApplication.shared`.

`click` delivers one public `NSEvent` mouse-down/up pair, converted from screen to the owned window's coordinates, through that window's `sendEvent`; settle and assert it stayed non-key/non-main. Use only safe receipt closures/injected stores. AX hit-test identity and AX frame measurements corroborate pointer receipts; host `NSView.hitTest` alone cannot prove which SwiftUI action fired. If direct owned-window delivery or a native picker action is unavailable, record that exact fixture limitation and retain a required native acceptance case; never replace it with direct closure/store invocation and claim a pointer/native pass.

`PreferencesAccessibilityFixture.init(state: PreferencesFeature.State)` produces `store: StoreOf<PreferencesFeature>`, `hotkeyModel: HotkeyPreferencesModel`, `notifications: NotificationCenter`, thread-safe per-fixture save receipts and `close()`. Use plain supplied state and explicit preferences loads/saves; use `LockIsolated` for `@Sendable` dependency receipts. Supply `.notRegistered` launch status and forbidden-action counters; registration must never run. Own a reused `HotkeyFixture`, initialize the existing model with its hotkey/defaults and a no-op handler, and clean only that fixture's suite. No default client fallback. Wait for the existing 0.15-second deferred notification using the bounded predicate before removing observers/closing; isolated centers prevent cross-test/global observers. Mark the new host suites `.serialized` and `@MainActor`.

Execution commands only, not run during planning. Set `A11Y_SCRATCH` to a fresh root-approved external evidence directory; retain full logs, actual exit, source tree/file SHA-256, pin before/after hashes and unique xcresults for each run. Reuse the established bounded command runner rather than adding tooling to tracked source. Resolve locked packages once:

```sh
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse \
  -derivedDataPath "$A11Y_SCRATCH/DerivedData" \
  -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation
```

For the exact suites named below, use a fresh `A11Y_RUN` evidence directory and repeat `-only-testing:GlimpseTests/SUITE` for each:

```sh
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -destination 'platform=macOS' \
  -derivedDataPath "$A11Y_SCRATCH/DerivedData" -skipMacroValidation \
  -disableAutomaticPackageResolution \
  -only-testing:GlimpseTests/SUITE \
  -resultBundlePath "$A11Y_RUN/AppTests.xcresult" CODE_SIGNING_ALLOWED=NO test
```

Meaningful RED must reach a wrong value/name/target/action assertion; missing symbols, AX unavailable, dependency failure or timeout are fixture/infrastructure failures. Native roles for mini switches/pickers are expected `checkBox`/`popUpButton`, with native switch `NSNumber` 0/1 and selected option text; first inspect the real host tree. If an OS exposes another genuine native representation, document it and assert that exact supported representation without manually overriding production values or weakening to “some node exists.” Unavailable assertions remain acceptance gaps, never silent passes/skips.

### Task 1: Name the native preference controls and expose display-pill state

**Files:** `PreferencesView.swift` native controls at current lines 91–101, 154–171, 223–250, pills 115–146 and hotkey state 342; new host/preferences test files; their project membership.

**Interfaces:**
- Preserve `displayBinding(keyPath:action:) -> Binding<Bool>`, store/actions and the deferred notification paths.
- Add `PreferencesView.init(store: StoreOf<PreferencesFeature>, hotkeyPreferences: HotkeyPreferencesModel? = nil, notificationCenter: NotificationCenter = .default)`. Remove the eager `@State HotkeyPreferencesModel()` initializer; use injected model or the same lazily constructed production model in `_hotkeyPreferences`. Route this view's posts and publishers through its injected center; default production remains `.default`.
- Produce `PreferencesAccessibilityTests` and the shared fixture/host interfaces above. No extracted settings model or duplicate control view.

| Native title / pill text | Exact accessible name | Value / existing action |
| --- | --- | --- |
| Filled background | Filled background | Native switch; `.setShowFilledBackground` |
| AI date search | AI date search | Native switch; `.setShowAISearch` |
| Week starts on | Week starts on | Existing full weekday option; `.setStartOfWeekday` |
| Provider | AI provider | Existing `provider.displayName`; `.setAIProvider` |
| Icon | Show icon in menu bar | On/Off from `showIcon`; `.setShowIcon` |
| Day | Show day of week in menu bar | On/Off from `showDayOfWeek`; `.setShowDayOfWeek` |
| Mon | Show month in menu bar | On/Off from `showMonth`; `.setShowMonth` |
| Date | Show date in menu bar | On/Off from `showDate`; `.setShowDate` |
| Year | Show year in menu bar | On/Off from `showYear`; `.setShowYear` |

- [ ] **Step 1: Write actual-control regressions and register both new files.** `nativeTitlesPreserveRolesAndSelectedValues` requires exactly one affected native control by each table name, switch native boolean values, picker selected weekday/provider text and no role words in names. `displayPillPressChangesOnlyItsOwnValue` parameterizes all five pills and both initial boolean states: assert button role, exact expanded name, `#expect(value == (initial ? "On" : "Off"))`; native press once, reacquire the node, assert inverted value, full options changed only at that key path, one save and one menu-bar notification; press again and assert restoration/save 2/notification 2.
- [ ] **Step 2: Write conditional picker/state cases (Review Focus 2).** `providerVisibilityAndSelectionSurviveSearchToggle` starts `.proxy`, native-presses AI search off/on, asserts provider absent/present and retained `displayName`, one AI save per toggle, no display/calendar notification. `nativePickerSelectionSavesOnce` starts weekday 1/provider `.auto`, uses each actual picker's public press/menu-item action to select weekday 2/provider `.proxy`, and checks selected native value (`Calendar.current.weekdaySymbols[1]`/`.proxy.displayName`), one matching save, weekday calendar notification 1, provider notification 0. Close only an owned menu in teardown; do not emulate selection by writing store state. If the hidden host cannot expose its native menu/action, retain the tree/result as a gap and assign this exact case to native acceptance.
- [ ] **Step 3: Make the fixture safe and compile-compatible before semantic changes.** Implement only the defined injection seam and test host; inject all per-fixture loads/saves/hotkey/defaults/center. `hostingPreferencesNeverTouchesProtectedDependencies` asserts zero fake-hotkey operations, zero launch registration/forbidden saves/external actions before and after hosting, and non-key/main window. Capture the unmodified controls' native tree.
- [ ] **Step 4: Record behavioral RED for `PreferencesAccessibilityTests`.** The current pills lack explicit On/Off; retain a failing expected-value/name assertion. Some native names may already be inferred by macOS; record that baseline honestly rather than require every native-title test to fail.
- [ ] **Step 5: Implement the table on the existing controls.** Replace only the four empty native titles while keeping `.labelsHidden()`/styles/options. Extend the existing pill tuple with its expanded name and add `.accessibilityLabel` plus `.accessibilityValue(isOn ? "On" : "Off")`; retain the same action, key path, notification and visual modifiers.
- [ ] **Step 6: Record GREEN and preservation checks.** Run `PreferencesAccessibilityTests`; from `GlimpseCore`, run `swift test --scratch-path "$A11Y_SCRATCH/Core" --cache-path "$A11Y_SCRATCH/swiftpm-cache" --force-resolved-versions --filter PreferencesFeatureTests`. Existing Core action tests must pass; unchanged workday/startup/recorder controls remain intact. Freeze focused evidence; no commit or whole quality.

### Task 2: Enlarge header/footer targets and prove real hit/layout behavior

**Files:** `AppDesign.swift`, `CalendarPopoverView.swift` header 273–316/footer 749–817, new calendar/viewport test files and project membership.

**Interfaces:**
- Produce `AppDesign.Control.iconTargetSize: CGFloat = 28` and `AppDesign.Control.dismissTargetSize: CGFloat = 24`.
- Produce internal `@MainActor CalendarHeaderControls: View` with `init(monthYearString: String, isShowingCurrentMonth: Bool, todayIsDisabled: Bool, previous: @escaping () -> Void, today: @escaping () -> Void, next: @escaping () -> Void)`.
- Produce internal `@MainActor CalendarFooterControls: View` with `init(isPinned: Bool, showingPreferences: Bool, quit: @escaping () -> Void, about: @escaping () -> Void, togglePin: @escaping () -> Void, openCalendar: @escaping () -> Void, togglePreferences: @escaping () -> Void)`.
- Keep those types in `CalendarPopoverView.swift`, shared directly with production and fixtures. Existing owner passes the unchanged store/panel/animation/About/Calendar/quit-confirmation closures; no live defaults in either row. Produce `CalendarIconTargetTests` and `AccessibilityViewportTests` consuming Task 1 host.

- [ ] **Step 1: Write native target/action cases.** `headerAndFooterTargetsHaveSingleEdgeActions` measures each button's public AX frame and asserts 28×28 within 0.5 pt; public pointer clicks at center and four 1-pt-inset corners increment only that action receipt once per click. Assert one actionable node per existing name, native button role, unchanged header/footer order, dynamic Pin/Unpin and Open/Close preferences labels. `neighborGapsAndDisabledTodayDoNothing` clicks midpoint gaps and attempts native press/pointer activation of disabled Today; assert zero extra receipts and disabled AX state.
- [ ] **Step 2: Write `targetsFitAndRemainReachableInPersistentViewport` (Review Focus 4).** Compose actual injected PreferencesView, header/footer rows and synthetic inert calendar-height content inside the production `PanelViewport`, original 12-point caret/316-point root, 300-point body and 16-point padding/268-point inner width. Parameterize maximum heights 812 and 312, preferences closed/open, and fixture-only `NSScroller.Style.legacy/.overlay`. Scroll the owned clip view to each obscured row before measuring/clicking; all eight targets must be checked across those row visits. Convert measured rectangles into stable document coordinates to assert horizontal body containment, no pairwise allocation intersection and neighbor gaps ≥8 pt; assert each visited row's targets fit the visible rounded body before edge clicks. Assert the viewport instance persists, preference state is retained, fitting/intrinsic width 316 and height ≤ cap+0.5, and four repeated layout passes converge. AX frames/point hits must be converted consistently from screen coordinates; clipped/offscreen targets are not counted as currently clickable.
- [ ] **Step 3: Expose the actual safe rows without changing semantics/size.** Move only existing header/footer composition into the declared shared types. Keep Today predicate in the parent exactly as before, header spacing `AppDesign.Spacing.sm + 2`, leading Quit/Spacer and original callbacks/labels/plain style/focus policy. Fixtures supply receipts for all actions, including Quit/About/Calendar, so none calls the real workflows.
- [ ] **Step 4: Record behavioral RED for `CalendarIconTargetTests` and viewport target assertions.** Original glyph-sized hit frames or inset-edge receipts must fail the 28-point contract. Verify tests exercise the extracted production rows, not generated lookalikes.
- [ ] **Step 5: Apply tokens inside labels.** Add frame then rectangular content shape to each of eight labels, after original glyph styling/rotation. Set footer HStack spacing explicitly to `AppDesign.Spacing.sm`; keep header's 10-point spacing. Preserve leading Quit separation; no outer/overlapping hit overlay.
- [ ] **Step 6: Record GREEN.** Run `CalendarIconTargetTests` and `AccessibilityViewportTests`, then existing `PanelLayoutTests`, `PanelGeometryTests`, `CalendarInputTests`, `CalendarScrollRouterTests` and `HotkeyPreferencesModelTests` together once as focused preserved-boundary checks. Existing reducers/actions remain untouched; source review verifies callback wiring, including Quit still requesting confirmation. Freeze evidence; no commit or whole quality.

### Task 3: Name and enlarge date-search dismissal without changing editing

**Files:** `CalendarPopoverView.swift` date-search row 322–400; extend calendar/viewport tests. Consume Task 2 target token and Task 1 host.

**Interfaces:**
- Produce internal `@MainActor CalendarDateSearchRow: View` with `init(query: Binding<String>, isActive: Binding<Bool>, isProcessing: Bool, error: Binding<String?>, focused: FocusState<Bool>.Binding, onSubmit: @escaping () -> Void, onEditorAppear: @escaping () -> Void)`.
- Move only the existing AI row/error presentation into this shared view. Parent retains the same `@State`/`@FocusState`, task, submit method, `onChange` panel/editor synchronization and hide/reset logic. Production `onEditorAppear` retains `activateForTextInput` and the existing 0.1-second focus scheduling; fixture supplies a counted no-op and owns focus binding. Row's dismiss action writes the existing bindings to false/empty/nil, with no extra callback or deactivation.
- Produce `DateSearchAccessibilityTests`; extend `AccessibilityViewportTests` with the actual shared date-search row. No AI service/client/state-model change.

- [ ] **Step 1: Write `dateSearchDismissClearsWithoutSubmitting` and processing/grouping cases.** Host active synthetic query `"fixture draft"` and error `"fixture error"`; require one native button named **Close date search**, help **Clears the query and closes date search.**, and 24×24 frame. Public press and each 1-pt-inset edge click independently clear query/error and active state; assert submit count 0, no external/panel-deactivation action, and the collapsed prompt returns. `processingHasNoDismissOrImplicitSubmit` hosts processing true and asserts no dismiss control and submit 0. `activeEditorAndDismissAreSeparateControls` records the actual row tree and requires reachable text-field and dismiss elements without an obscuring extra row action.
- [ ] **Step 2: Write the extended viewport edge/reachability cases.** In the Task 2 real composition, include active date-search with long synthetic query/error and processing variants. Under both scroller styles and height caps, scroll it into view, verify 24×24 containment/disjointness, click inset edges, assert only query/error/active state clears and preference/pin/action receipts stay unchanged. Verify the same viewport and stable width/heights after row collapse/error removal; no replacement scroll view or nested scroll.
- [ ] **Step 3: Expose the actual row without speculative grouping repair.** Preserve existing placeholder **e.g. next Friday, Christmas...**, prompt **Go to date...  ⌘G**, parent tap-to-activate, label **Go to date using AI**, styling, focus/submission and processing branch. Capture collapsed/active/error/processing AX trees. Record whether either child is obscured; this observation is fixture evidence, not VoiceOver evidence.
- [ ] **Step 4: Record behavioral RED for `DateSearchAccessibilityTests`.** Missing Close date search name/hint or 24-point edge/size contract must fail. An unavailable AX tree is a fixture failure/gap, not proof of a grouping defect.
- [ ] **Step 5: Add dismiss name/hint/target.** Use `AppDesign.Control.dismissTargetSize` frame and rectangular content shape inside the original label; retain plain style/focus suppression and binding mutations. Only if the recorded actual row tree hides/obscures editor or dismiss, apply the accepted bounded repair: remove the conflicting parent accessibility label/grouping and place **Go to date using AI** on the actual collapsed button and active field; retain the placeholder and pointer tap behavior. Re-record the tree and prove the two actual controls remain individually usable. Do not add a wrapper, new focus policy or processing cancellation.
- [ ] **Step 6: Record GREEN and inspect the integration seam.** Run `DateSearchAccessibilityTests`, `AccessibilityViewportTests` and only affected earlier new suites. Confirm parent `submitAIQuery`, keyboard monitor, field activation/focus timing, Escape path, panel hide reset, pin state and scroll ownership are unchanged. Reuse Task 2 preserved-boundary results unless changes or a failure require another run. Freeze final source/hashes and all native gaps; no commit or whole quality.

## Root-owned completion and evidence boundaries

- [ ] **Independent final source acceptance:** one fresh A1–A8 reviewer checks the complete accepted design against frozen source/tests. A1 names/native roles/default actions/duplicate grouping; A2–A3 geometry/panel/input/recording; A4–A6 unchanged updater/AI/startup/preferences/permission/data; A7 minimal shared seams/tokens/public API/concurrency; A8 actual action/value/edge/viewport evidence. Resolve material findings with focused reruns only.
- [ ] **Native A11Y-01a acceptance:** on an available authorized macOS 14 and current supported macOS setup, inspect names/roles/values, use VoiceOver press for all affected controls, select native picker options, check duplicate/obscured row behavior and click target edges. In preferences with constrained height, reach every control through scrolling; check typing/arrows/submit once/dismiss/Escape/reopen/pin/recorder cancellation with disposable preferences and synthetic input. Preserve user VoiceOver/keyboard/TCC/startup settings and private calendar data; record any unavailable setup/case explicitly.
- [ ] **Scoped records and fresh metadata:** root records source, fixture, signed/native, release and public artifact evidence separately, preserves all open historical/native checks, and keeps whole A11Y-01 open. Select current next marketing/build only at delivery time; synchronize four marketing/four build settings, README and readiness. From the implementation root run `python3 tools/scripts/release-control.py version --root "$PWD"` and `python3 tools/scripts/check-dependency-pins.py --root "$PWD"`; require successful consistency/unchanged aligned pins and retain both locked graphs.
- [ ] **One final ordinary hook/integration:** after independent acceptance, root stages the intended final source/docs/metadata and makes its ordinary normal commit. Its staged-source hook is the sole local whole-quality pass; retain exact archive tree/logs/xcresult/pin comparison and rerun only if final source changes. No hook bypass, intermediate task commits or duplicate full gate.
- [ ] **Protected delivery and public/native verification:** root refreshes exact head/base/main/checks/run facts, observes ordinary protected Release/Recovery terminal success and verifies public signed/notarized/Gatekeeper/Sparkle artifacts and installed identity. Artifact/install success does not fill missing macOS 14 VoiceOver, keyboard, picker, fit/scroll or signed lifecycle evidence.

Planning produced no implementation/build/test/native evidence. Root owns accepted-plan handoff under the established inline method; no new human execution-menu question is required. Permissible eventual roadmap wording remains: “Names, pill state and icon targets accepted at recorded evidence levels; date native activation and keyboard/focus lifecycle remain open.”
