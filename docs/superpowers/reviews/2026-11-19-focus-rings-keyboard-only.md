# Focus rings only after keyboard use, app-wide (v1.5.6/build43)

## Product authority

On 2026-11-19 the owner chose improvement #4: no leftover focus rings anywhere after a mouse click. This follows the v1.5.5 fix that covered only the footer Quit.

## Change

- **Tracker:** a new `InputModalityTracker` (one local monitor, installed at launch and kept alive) records whether the last input was the keyboard or the pointer.
- **Calendar rings:** `CalendarKeyboardFocusOutline` and the calendar grid's selected-date outline draw only after keyboard use. This covers the header, Ask Glimpse, footer, quit confirmation and schedule links.
- **Settings rings:** Settings uses `.focusEffectDisabled` when the last input was the pointer. A gear click opens it with no ring; ⌘, or Tab shows the native rings.
- **Behaviour kept:** focus ownership, Tab order, Return/Space/Escape and VoiceOver are unchanged.
- **Cleanup:** the v1.5.5 Quit-only state is removed.

## Verification

- **Code:** self-review against A1–A8 found no blockers.
- **QA:**
  - GlimpseCore: 214.
  - App: 442, including InputModalityTests.
  - Keyboard suite: 47 methods, including the new pointer and keyboard ring tests.
  - AI: 11. Agenda: 13. Tooling: 239.
  - The pre-commit gate passed.
- **UX:** native renders, light and dark: calendar Quit after a click (no ring) and after Tab (ring); Settings opened by pointer (no ring), opened by keyboard, and after Tab (ring).
