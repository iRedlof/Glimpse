# Performance batch (v1.5.9/build46)

## Product authority

Backlog item #6 (audit PERF-glimpse.md, items P1–P6 and P8). The owner said on 2026-11-19 to continue with performance optimization after the backlog.

## Change

- **P1:** re-fetching the day already shown keeps its events (no "Loading events…" flash). A new day, lost access or a prior failure still clears the agenda; the requestID guard still drops stale responses.
- **P2:** app activation reloads events only when EventKit authorization changed.
- **P3:** Equatable `DayCell` with cell-local hover; per-grid day cache, so hovering re-renders about two cells instead of the whole popover.
- **P4:** one static locale-aware `Date.FormatStyle` for event times (24-hour locales now get 24-hour times).
- **P5:** the menu bar skips identical re-renders (key: options, date string, meeting, appearance, thickness, day); the theme notification clears it. Still image-only, no appearance KVO.
- **P6:** opening the AI editor prewarms one on-device session (guarded by `canImport(FoundationModels)` and macOS 26), single-use and matched to today's instructions.
- **P8:** removed the 150 ms preference-post delays (the save is synchronous) and the duplicate launch-at-login refresh.

## Verification

- **Code:** an independent review against A1–A8 found no CRITICAL or HIGH issues. Two MEDIUM edge cases were accepted: the prewarm loses its benefit across midnight, and the panel's today mark across midnight is unchanged from 1.5.8 behaviour.
- **QA:** GlimpseCore 288 tests; full app suite 487 tests (keyboard suites included); release tooling 239 tests; hosted CI quality gate on the PR.
- **Performance:** cell comparison is about 4.8 µs for 42 cells per pass, and the day cache (about 46 µs) is rebuilt only when the month changes. Identical menu bar triggers skip the about 170 µs render and the resize.
- **UX:** the grid hover, today/selection rings, keyboard focus ring and agenda rows keep their visuals; checked after install on the owner's Mac.
