# Actionable calendar dates implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose every existing calendar date as an individually actionable native control.

**Architecture:** Wrap the existing production day label in a plain native Button.
Keep the real reducer and input/lifecycle policy. Test the full production view
in an owned offscreen host with isolated dependencies.

**Tech Stack:** Swift 6, macOS 14+, SwiftUI/AppKit, TCA, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-02-date-accessibility-design.md`

## Global Constraints

- Keep 42 dates, 30-point cell height, current geometry, labels, selected trait and hover.
- One action sends `.dateTapped(day.date)`; no additional tap handler.
- Keep `.buttonStyle(.plain)` and `.focusable(false)`; no key/focus/permission policy change.
- No dependency changes, private events, production settings or system accessibility changes.
- Preserve real panel reuse, monitors, viewport convergence and single-image status rendering.
- Candidate version/build must synchronize all four entries and README before delivery.
- Native VoiceOver/older-OS/focus acceptance remains separate from owned fixtures.

## Review Focus

1. A single native or pointer press must not double-toggle a selected date.
2. An outside-month press must preserve displayed month and permission gating.
3. Plain button wrapping must preserve full-cell geometry and today/selected/hover rendering.
4. Root-host fixtures must not escape to live preferences, calendar, AI or startup services.
5. The existing Return/arrows/editor/recorder policy must remain unchanged; semantic buttons alone must not imply keyboard-focus acceptance.

### Task 1: Native date actions with protected delivery

**Files:**
- Modify: `Glimpse/CalendarPopoverView.swift`
- Create: `GlimpseTests/CalendarDateAccessibilityTests.swift`
- Modify test utility if needed: `GlimpseTests/AccessibilityTestHost.swift`
- Modify delivery metadata: `Glimpse.xcodeproj/project.pbxproj`, `README.md`, `.github/release-readiness.json`
- Update: product inventory, roadmap and scoped acceptance document.

**Interfaces:**
- Consumes: existing `CalendarFeature.Action.dateTapped(Date)`, `CalendarPopoverView` injected stores, `AccessibilityTestHost`.
- Produces: 42 native date Buttons with the existing full-date labels and actual default press.
- No public/Core interface change.

- [x] **Step 1: Write real-view regression and observe RED**
  Add `CalendarDateAccessibilityTests.datesExposeDistinctNativeActions`.
  Host November 2030 with fixed injected time and no event access.
  Assert 42 date buttons, unique full-date names, 30-point disjoint frames,
  unchanged initial selection and no date-action/event receipts after enumeration.
  `#expect(dateButtons.count == 42)` must fail on unchanged production source,
  because the dates currently use Text/tap gestures, rather than missing symbols.
  Run bounded immutable-package arm64 Debug app tests in the existing cache,
  unsigned, `-skipMacroValidation`, 30-second per-test timeout and
  `-only-testing:GlimpseTests/CalendarDateAccessibilityTests`.
  Expected: actual tests execute; date-button expectations fail.

- [x] **Step 2: Add activation regressions and minimal implementation**
  Add actual default-press select/repeated-deselect and outside-month regressions;
  add center/four inset-corner pointer cases asserting exactly one date receipt.
  Selected state and full-date/outside-month labels remain available.
  Wrap existing day label in Button, preserve modifiers/geometry and remove tap.
  Expected: one unchanged reducer action per press; no month jump or external I/O.

- [x] **Step 3: Verify affected behavior**
  Run the bounded command with date accessibility, calendar input, scroll router,
  panel layout and existing control-accessibility suites. Read raw xcresult and
  logs, validate source and both dependency pins before/after.
  Expected: zero failures/skips and no new runtime warnings. Real fixture
  activation/geometry is accepted separately from signed/VoiceOver behavior.

- [ ] **Step 4: Candidate, independent review and ordinary quality**
  Write truthful scoped acceptance, synchronize version1.4.14/build21, update
  existing inventory/backlog and readiness after actual role decisions.
  Dispatch one fresh whole-branch A1–A8 reviewer with this spec/five focus items
  and ledger; adjudicate all findings. One Important/Critical TDD fix pass;
  defer Minor findings. Use the normal commit hook and retain exact-source
  whole-quality evidence. Do not repeat unchanged checks just for bookkeeping.
  Expected: no unresolved Important/Critical issue; required gate/readiness pass.

- [ ] **Step 5: Protected delivery, native follow-up and task receipt**
  Use fresh canonical-main admission/head/base/checks/run observations and normal
  protected integration. Verify exact-source terminal release, public signed
  artifacts and recoverable official installation. Reopen through Finder and
  observe real date nodes/actions with CUA; preserve settings and calendar access.
  Use task-done to validate accepted source-bound mandatory receipts, retain
  native limits and carry all rulings/deferred minors into the finish report.
  Expected: claims match each actual boundary; keep whole-product goal active.

## Self-review

One coherent task implements the existing date semantic proposal. Each review
condition maps to real action/geometry/isolation tests or retained input tests.
The actual root view avoids a parallel lookalike. The initial baseline is the
accepted canonical v1.4.13 tree; no duplicate baseline build is needed.
User autonomy supplies execution/delivery authorization, so routine approval
and execution-method prompts are omitted.
