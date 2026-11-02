# Diagnostics Fixtures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Root explicitly assigned one Developer and owns the final whole-candidate review.

**Goal:** Make diagnostics deadline/ownership fixtures exercise explicitly controlled real collector scheduling.

**Architecture:** Inject only worker submission and deadline awaiting, preserving current production defaults. Test-owned single-shot acknowledgements and gates sequence real background work and retain ordered observations.

**Tech Stack:** Swift 6, Swift Testing, Foundation Dispatch, unsigned arm64 Debug Xcode tests.

**Spec:** `docs/superpowers/specs/2026-11-02-diagnostics-fixtures-design.md`

## Global Constraints

- Work only on `codex/diagnostics-fixtures` in the assigned isolated checkout.
- Preserve real request/read/ownership semantics and the production utility queue/Task.sleep defaults.
- Timeout `0.2`; production-default smoke elapsed time `<1s`; fixture watchdog `5s`.
- Run only DiagnosticsExportTests with immutable pins and 30-second per-test timeout.
- No commit/push/PR/full gate; no native UI, private data, signing or version/delivery changes.
- Preserve lockfiles and retain workspace/artifacts.

## Review Focus

- Deadline before queued work must skip the provider and retain ownership until complete worker exit.
- Deadline after blocked provider/iterator entry must deliver before reader release.
- Late output must not reach either the timed-out result or a fresh collection.
- Cancellation and teardown must resume acknowledgements once and drain captured work.
- Production-default deadline must still use the requested real delay and existing elapsed bound.

### Task 1: Controlled deadline and ownership fixtures

**Files:**
- Modify: `Glimpse/DiagnosticsExport.swift`
- Modify/Test: `GlimpseTests/DiagnosticsExportTests.swift`

**Interfaces:**
- Consumes: real `collect(timeout:outputLimit:read:)`, request delivery/read loop.
- Produces: internal `init(submitWorker: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void, awaitDeadline: @escaping @Sendable (TimeInterval) async throws -> Void)` with current production defaults.

- [x] Write parameterized blocked-provider/iterator test, deadline-before-worker test, and production-default timer smoke. Keep report/read/cancellation tests; make existing reader watchdog explicit.
- [x] Add compile-only initializer surface with unwired parameters; retain preparatory diff/source identity separately. This is not unchanged-production RED.
- [x] Run bounded focused RED. Expected: executable fixture/control assertions fail because the supplied scheduler/deadline boundaries are unused, with exact failures and exclusions retained.
- [x] Store initializer closures and wire existing utility worker submission and detached timer delay through them, without moving timer/worker/cleanup logic.
- [x] Run one bounded focused GREEN. Expected: all diagnostics names/cases pass; source and package receipts unchanged during execution.
- [x] Stage source/spec/plan and return exact receipts plus ledger for root's final review/hook. Do not commit or rerun the final gate.

Focused receipts are retained under
`build/validation/diagnostics-fixture-implementation.yucljzsb`: executable RED
ran 17 names/18 cases (14 passed, four expected fixture-control failures);
GREEN ran the same 17 names/18 cases and all passed. Two earlier attempts
failed before test-bundle connection and are excluded from behavioral RED.
GREEN used local `/tmp` DerivedData, `ENABLE_DEBUG_DYLIB=NO`, immutable pins,
unsigned arm64 Debug, 30-second test limits and the 1200-second outer wrapper.
The default real timer measured 0.203699042 seconds against the unchanged
one-second bound. Source and both lockfiles remained identical during each
run. Root's final whole-candidate review and mandatory hook remain pending.

### Review corrections I1/M1

- [x] Add deterministic canceled-caller/durable-completion and completed-worker
  ownership regressions. Observe behavioral RED before changing fixture semantics.
- [x] Separate per-observer cancellation from durable acknowledgement; make
  bounded cleanup cancellation-resistant and consume/release captured work.
- [x] Run one affected GREEN with the same local DerivedData, immutable pins,
  test limits and wrapper; retain new receipts without overwriting original runs.
- [x] Stage only owned tests/spec/plan and return source/rulings for root's
  focused re-review and final normal gate. Production collector stays frozen.

New review receipts are retained without overwriting the original evidence:
`build/validation/diagnostics-fixture-implementation.yucljzsb/review-I1-M1.w7nsh0kz`.
Behavioral RED ran 19 names/20 cases: eighteen existing cases passed; the two
new cancellation/draining and weak-collector cases failed at the expected
boundaries. Affected GREEN passed all 19 names/20 cases, exit0 in11.981985s,
with source/pins unchanged during the run. Real timer elapsed0.207496041s,
timeout0.2 and unchanged<1s bound. The original production collector SHA256
`6bc0a78fe56d6f3bdbd892fa769c427f0eb0942827d88ad35cce07978a45add2`
is unchanged. Review corrections are implemented and fixture-validated;
root's focused re-review, normal whole gate, integration and delivery remain
pending.
