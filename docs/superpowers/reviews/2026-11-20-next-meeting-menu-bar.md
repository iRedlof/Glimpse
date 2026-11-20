# Next meeting in the menu bar (v1.5.8/build45)

## Product authority

This is backlog item #3 (big idea g-now-strip). The owner said on 2026-11-19 to keep working through the backlog.

## Change

**Menu bar countdown:**
- An opt-in Settings toggle, "Show next meeting in the menu bar", appends today's next meeting to the menu bar item ("Standup in 12m").
- It turns amber within 5 minutes, and reads "ends 10:30" during the meeting.
- All-day, free and declined events are ignored.
- It's drawn into the single menu bar image (no subview), and the Settings preview uses the same drawing code.

**Updates:**
- One query for today, made on toggle, calendar change, wake, midnight and clock change.
- The per-minute update reuses those events, aligned to the minute boundary.

**Join:**
- Shown when an event has an https link on a known Zoom, Meet, Teams or Webex host (strict extraction).
- Opens from the Join button on the agenda row or with ⌘J, only after a user action.

## Verification

- **Code:** an independent review against A1–A8 found no blockers.
- **QA:**
  - GlimpseCore: 275.
  - App: 464.
  - Keyboard: 55. AI: 11. Agenda: 13.
  - Hosted CI quality gate on the PR.
- **Performance:** idle CPU is 0.0% before and after with the panel closed; the minute update costs about 0.15 ms.
- **UX:** 16 menu bar renders (light/dark, filled/bordered, off/upcoming/amber/in-meeting) plus the Join row were inspected.
