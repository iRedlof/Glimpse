# Fixture Hosting Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:executing-plans for the explicitly assigned work in this managed
> worktree. Runtime and implementation steps remain gated by the root handoff.

**Goal:** Make terminal fixture close release hosting content after helper scope
exit, with a behavioral regression against each original helper.

**Architecture:** A separate two-test suite calls the original helpers with
injected/inert content. Weak observations and a bounded drain establish release
without constraining window lifetime. After actual RED, change only the two
test-helper close methods to detach their content view before closing.

**Tech Stack:** Swift 6, Swift Testing, AppKit and SwiftUI; macOS 14+.

**Spec:** `docs/superpowers/specs/2026-11-02-fixture-hosting-cleanup-design.md`

## Global Constraints

- Canonical base `d36661d6b78a7236b0aedfc7e05237516000c9f1`.
- One second or 40 drain passes; 5 ms run-loop pump plus 25 ms await per pass.
- Original helpers remain unchanged during preparation and RED.
- Preserve both prior experiments, production, index, dependency pins and hooks.
- No NSWindow deallocation/count assertion, release-flag hacks or production claim.
- Exclusive runtime was subsequently granted and released after terminal process checks.
  Root integration is recorded below; whole quality remains a separate pending step.

## Review Focus

1. Assert a real settled hosting view existed before measuring its release.
2. Observe only weak host/view references after the factory returns.
3. Preserve close on throws/cancellation and bound all drain work.
4. Keep About reopen-before-close and accessibility consumers' terminal cleanup.
5. Distinguish an actual hosting-retention RED from setup/loader/compiler failure.

## Task 1: Prepare the original-helper regressions

**Files:** Create `GlimpseTests/FixtureHostingCleanupTests.swift`, register its four
test-target entries in `Glimpse.xcodeproj/project.pbxproj`, and own this spec/plan
and `.superpowers/sdd/2026-11-02-fixture-hosting-cleanup/progress.md`.

**Interfaces:** Consume `AboutUpdateHost`, `UpdaterFixture`,
`AccessibilityTestHost`. Produce
`FixtureHostingCleanupTests.aboutCloseReleasesHostingAfterScopeExit()` and
`.accessibilityCloseReleasesHostingAfterScopeExit()` plus scalar JSON receipts.

- [x] Audit every original close consumer and all About reopen call sites.
- [x] Write the two tests: require live fixture/tree before close, require helper
  scope exit, and expect weak hosting release after bounded drainage.
- [x] Inspect ownership, defer/cancellation paths and the mutation each test catches.
- [x] Validate project syntax/diff and freeze prepared inputs without compilation.
- [x] Hand off source and all audit boundaries; report runtime HOLD.

## Task 2: RED, then the minimal test-helper change

**Files:** Modify only `AboutUpdateHost.close()` in
`GlimpseTests/AboutUpdateSectionTests.swift` and `AccessibilityTestHost.close()` in
`GlimpseTests/AccessibilityTestHost.swift`, after actual RED is accepted.

- [x] After exclusive-slot grant, run only `GlimpseTests/FixtureHostingCleanupTests`
  through the existing bounded runner with pinned packages, unsigned arm64 and
  the owned local DerivedData. Retain the first actual result/raw xcresult.
- [x] Confirm both tests reached the hosting-release assertion against unchanged
  helpers; retain exact source/command/receipts and exclusions.
- [x] With root's implementation handoff, insert only `window.contentView = nil`
  immediately before the existing `window.close()` in both helper methods.
- [x] Run the unchanged two regressions under the renewed slot: both must pass.
- [x] Run the affected About, icon, date-search, preferences, viewport, settling
  and date-accessibility suites when authorized. Check all existing consumer
  behavior, including three About reopen scenarios and date-wrapper cleanup.
- [x] Retain raw warnings, actual selected names/cases, source integrity and owned
  process absence. Report hosting cleanup separately from remaining window
  retention. Integration/review/full gate require a later explicit handoff.

## Recorded acceptance and integration

Both unchanged-helper regressions failed their hosting-release assertion. The
minimal content-view detachment passed those same regressions and all 30 original
consumer methods: 32 methods/137 cases, zero failures/skips. Hosting views released
at the first approximately 30 ms drain sample; retained native windows and raw
warnings remain recorded without a production cause claim. Independent review
accepted the helper changes and root integrated the six scoped paths into the
keyboard candidate. The later whole quality gate remains pending.
