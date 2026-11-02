# Shortcut Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Preserve a working shortcut when a replacement fails and report actual registration availability with an actionable recovery path.

**Architecture:** An independently instantiated, main-actor observable coordinator owns Carbon references, accepted event identity, callback and transaction state. A view-used observable preferences model owns recording, explicit requested intent and failure presentation. Tests inject native operations, monitors and isolated defaults.

**Tech Stack:** Swift 6, Observation, SwiftUI, Carbon, AppKit and Swift Testing; existing macOS deployment floor and dependency pins.

**Spec:** [Shortcut recovery design](../specs/2026-11-01-shortcut-recovery-design.md) and [HK1–HK10 acceptance](../../shortcut-product-ux-acceptance.md).

## Global Constraints

- Keep Carbon registration options=0; do not promise exclusive ownership or universal cross-app collision detection.
- Saved requested state, configured combination and usable registration are separate facts; absent requested state defaults to true.
- Keep the current Features card, mini switch, monospaced recorder, inline caption messages, AppDesign spacing, and deliberate focus policy.
- Do not redesign the calendar, change AI behavior, or broaden shortcut reservation rules.
- Preserve startup opt-in after failure; a failed first enable must not introduce enabled=true.
- Explicit disable cancels recording and saves off intent; native failure must not falsely report successful teardown.
- Retain ownership of references after cleanup failures and suppress dispatch from unaccepted candidates.
- Test instances must not use the live singleton, shared defaults, native global registration or installed app.
- Root owns versions, release readiness and integration; developer owns app changes and project membership.
- Normal commit/push hooks, checks for every introduced revision, protected merge and exact prior/final release verification are mandatory.
- Native installation/restart, desktop shortcut registration and machine reboot/logout remain separately authorized work.

## Review Focus

- Native noErr with nil key/handler: fail without publishing availability; tested in Task 1.
- Old retirement and candidate rollback both fail: preserve accepted state and retain suppressed candidate ownership; tested in Task 1.
- Queued old/foreign events arrive after replace/disable: accepted identity is checked at delivery; tested in Task 1.
- Disabled or failed-startup recording is cancelled: preserve intent/configuration, restore applicable failure and remove capture once; tested in Task 2.
- Disable succeeds for the key but fails for its handler: show inactive with cleanup failure and retain retry ownership; tested in Tasks 1 and 2.

---

### Task 1: Registration transaction and native adapter

**Files:** Modify `Glimpse/GlobalHotkey.swift`; create `GlimpseTests/GlobalHotkeyTests.swift`; add test membership in `Glimpse.xcodeproj/project.pbxproj`.

**Interfaces:** `@MainActor @Observable GlobalHotkey.shared` is the live instance. Tests use `init(backend: any HotkeyBackend, defaults: UserDefaults)`. `register(combo:handler:)` and `unregister()` return `Result<Void, HotkeyRegistrationError>`. The coordinator exposes `currentCombo`, `lastError` and computed `isRegistered`. Backend operations return status and optional native references; `HotkeyEventID` is Equatable/Sendable.

- [x] Introduce a behavior-retained injection seam and run the regression suite unsigned. Record expected assertion failures separately from compiler failures.
- [x] Verify `replacementFailurePreservesRegistrationCallbackAndSavedCombo`, `sameComboRetainsNativeRegistrationAndUsesAcceptedCallback`, and `successfulReplacementPersistsOnlyAfterReleasingOldKey` against exact operation traces and isolated saved values.
- [x] Verify first failure, nil native handles, handler failure, old-release failure, candidate cleanup failure and repeated teardown against owned-reference counts and actual availability.
- [x] Implement candidate-before-retirement, same-active reuse, deferred persistence, typed failures and retryable owned cleanup.
- [x] Parse native event identity, allocate a distinct candidate generation and recheck accepted identity when queued main-actor delivery runs.
- [x] Verify matching callbacks fire once and stale, malformed and foreign events cannot activate the accepted callback.
- [x] Run the focused `GlobalHotkeyTests` unsigned and retain logs/result bundle externally. Pass means all transaction/dispatch assertions succeed with unchanged dependency pins.

### Task 2: Preferences lifecycle and diagnostics

**Files:** Create `Glimpse/HotkeyPreferencesModel.swift` and `GlimpseTests/HotkeyPreferencesModelTests.swift`; modify `Glimpse/PreferencesView.swift`, `Glimpse/CalendarStatusItem.swift`, `Glimpse/DiagnosticsExport.swift`, `GlimpseTests/DiagnosticsExportTests.swift` and project membership.

**Interfaces:** `HotkeyPreferencesModel.init(hotkey:defaults:handler:)` exposes `isEnabled`, `isRequested`, `displayedCombo`, `errorMessage` and `isRecording`. `setEnabled(_:)`, `beginRecording(using:)`, `cancelRecording()` and `handle(_:)` control state. Injectable `HotkeyRecordingClient` installs/removes capture and reports recording transitions. Input carries key/modifiers and visible/key/owner guards. `HotkeyDiagnosticSnapshot` is Sendable and contains requested/registered/saved/active/error facts.

- [x] Add failing regressions for rejected replacement with recorder retained, first-enable failure, startup opt-in preservation and explicit **Keep shortcut off** opt-out, inactive recording/cancel/success and successful retry clearing errors.
- [x] Add capture ordering/count assertions for Escape, second click, disable, hide and disappear, plus reserved input and foreign/unmodified pass-through.
- [x] Implement the actual view-used model, custom switch binding, visible inactive **Set and enable shortcut** action, conditional **Keep shortcut off** opt-out when inactive/requested=true, contextual copy and accessible names/hints.
- [x] Wire startup to the live coordinator while retaining requested intent on failure.
- [x] Replace diagnostic saved-intent-only reporting with an injected immutable requested/actual snapshot; test report values and partial-report behavior.
- [x] Run focused model, coordinator and diagnostics suites unsigned; pass means all acceptance transitions and existing diagnostic tests succeed.
- [x] Freeze app/project membership before root changes version metadata. No source commits occur between these tasks.

### Task 3: Scoped acceptance and normal integration

**Files:** Update `docs/shortcut-product-ux-acceptance.md`; create scoped code/QA acceptance documents; update four app/test marketing versions and builds, README badge and `.github/release-readiness.json`.

**Interfaces:** PM/UX reviews HK1–HK10 against frozen source and evidence. Independent QA and A1–A8 reviewer accept only exercised source contracts. Readiness references those scoped documents for version 1.4.6/build 13.

- [x] Obtain independent frozen-source PM/UX, QA and A1–A8 review; resolve demonstrated blockers and rerun affected checks.
- [x] Synchronize version 1.4.6/build 13 only after membership freeze; confirm dependency pins unchanged.
- [ ] Stage all approved files and make a normal commit. The installed pre-commit hook verifies the previous main release and tests the exact staged archive with retained result bundles.
- [ ] Push normally, create/attach the PR and verify every introduced commit plus synthetic merge source in hosted quality artifacts.
- [ ] Use ordinary protected merge after exact-head checks and resolved findings. Hold subsequent source commits/pushes until the entire exact-main Release or authorized Recovery is verified.
- [ ] Independently verify actual anonymous signed DMG/app/feed/manifest source, signatures, tickets, Gatekeeper and Sparkle after publication; retain receipts.
- [ ] Refresh original checkout only by clean fast-forward after release verification; preserve the managed monitoring worktree.
- [ ] Leave remote crash, signed UI/Powerbox/shortcut delivery, login/reboot, sleep/wake, accessibility, sustained performance and endurance criteria open until actual evidence exists.

## Execution and evidence

The user's existing cross-functional team and iterative implementation authorization
determines execution; no additional plan approval is required. Checkbox completion
must follow evidence, not anticipated outcomes. This plan is a bounded app fix
within the active reliability goal and does not claim that goal is complete.
