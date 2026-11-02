# Native keyboard mechanism probe plan

Spec: `docs/superpowers/specs/2026-11-02-keyboard-focus-probe-design.md`.

## Global constraints

Own only the probe test, its project registration, this spec/plan, isolated SDD
workspace and external receipts. Production source/version/pins/index/refs remain
unchanged. No other agents or native UI operations. Root has released the build
slot after QA's focused process exited. Preserve the workspace for handoff.

## Task 1: Prepare and run the bounded experiment

1. Record baseline branch/HEAD/tree/index and tracked file/pin digests externally.
   Expected: clean `codex/keyboard-focus`, baseline matches the spec.
2. Add an opt-in characterization test and test-only native prototype. Register
   one test source in the test target; create an SDD ledger with explicit rulings.
   Expected: only the four owned files appear in source status.
3. Verify project syntax and source scope. Run only this suite with the spec's
   build constraints and record command/source/pins/log/xcresult/timeout/exit.
   Expected: terminal evidence, including honest mechanism failures if present.
4. Read the actual native observations and failure details. Correct only fixture
   defects supported by evidence; do not patch the mechanism to manufacture success.
   Expected: observed Tab/focus/key counts and cleanup, or an explicit prerequisite
   limitation. A failed hypothesis is a valid experiment result, not a green gate.
5. Write the external recommendation/evidence and update the ledger. Preserve
   exact candidate source, package receipts and SDD workspace.
   Expected: a prototype-limited handoff, no product/release acceptance claim.

## Review focus

Direct owned-window event delivery must not be replaced by AX actions or predicates.
FocusState must be recorded alongside the AppKit firstResponder, not inferred from
the requested target. Public configuration is observed without modifying it.
Failure diagnostics must remain distinguishable from fixture defects and user
acceptance. Inspect cleanup and application activation boundaries.
