# Updates and About sections replace the About window (v1.5.4/build41)

## Product authority

On 2026-11-18 the owner asked whether Glimpse needs a separate About dialog and asked for before/after mocks (`hearth-task-artifacts/hearth-studio/glimpse-about/`). They picked **B · Updates + About**.

## Implementation

- The About window is removed.
- A new **Updates:** section in Settings has:
  - a "Check for updates automatically" checkbox bound to Sparkle;
  - a Check Now button;
  - an inline status for every UpdateStatus case: up to date with the check time, checking, available with Update/Skip, downloading with progress, installing, ready with Install and Relaunch, no update, and error with Try Again.
- A slim **About:** section has the version, "Diagnostics…" (the existing export), Website and Support (GitHub issues).
- The Settings minimum height is now 600pt.

## Verification

- **Code:** pre-production review A1–A8 returned ship, and all code should-fixes are in HEAD.
- **QA:** the full pre-commit gate passed:
  - app: 431 tests
  - key-window keyboard suite: 45 methods
  - other app suites: 11 and 13
  - GlimpseCore: 214
  - tooling: 239
- **UX:** native renders of each update state in light and dark were inspected against the picked mock.
