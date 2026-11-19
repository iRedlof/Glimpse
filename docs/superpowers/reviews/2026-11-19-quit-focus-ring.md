# No focus ring on a mouse-opened Quit confirmation (v1.5.5/build42)

## Product authority

On 2026-11-19 the owner sent a screenshot of the calendar footer's Cancel | Quit Glimpse halves showing a blue box around Cancel, and asked to get rid of it.

## Change

The confirmation still gives Cancel keyboard focus, so Escape and Return keep working. Its focus ring is now drawn only after keyboard use:
- the confirmation was opened with a key, or
- the user Tabs between the halves.

A mouse click leaves no ring. The new `calendarFocusRingVisible(after:)` decides this from the current event type. `CalendarKeyboardFocusOutline` gains `visible`, which defaults to true, so every other control keeps its ring.

## Verification

- **Code:** a small change; A1.2 keyboard focus and VoiceOver are preserved, and focus ownership is unchanged.
- **QA:** `QuitFocusRingVisibilityTests` covers mouse (no ring) and keyboard (ring). The full quality gate runs on commit.
- **UX:** the keyboard-opened confirmation renders keep their ring; a mouse click shows none.
