# Open an agenda event in Calendar; stuck agenda fix (v1.5.7/build44)

## Product authority

On 2026-11-19 the owner picked improvement #4/#5 and asked to work through the backlog. Backlog item #2 was to tap an event to open it in Calendar: events were read-only, and the Open Calendar launcher had been removed in v1.5.3.

## Change

**Open in Calendar:**
- Clicking an agenda event row, or pressing Return/Space on a focused row, opens that event in Calendar.
- The link is `ical://ekevent/<calendarItemIdentifier>?method=show&options=more` (with the occurrence start for repeating events), opened with LSOpenCFURLRef.
- It is sandbox-compatible: proven with a sandboxed probe (OSStatus 0, Calendar launches) and used by MeetingBar.
- Rows have hover, a pointing-hand cursor, an accessibility label and hint, and keyboard focus that follows the keyboard-only ring rule.
- A failure shows "Couldn't open Calendar."

**Stuck agenda fix (#47):**
- Rapid event refreshes could cancel the newest query in favour of an older one, leaving the agenda stuck loading.
- The new `cancellableLatestWins` keeps send order. This fix is already on main and ships with this release.

## Verification

- **Code:** self-review against A1–A8 found nothing open.
- **QA:**
  - GlimpseCore: 227.
  - App: 450.
  - Tooling: 239.
  - The hosted CI quality gate, including the key-window suites, runs on the PR.
- **UX:** native renders of the agenda rows (rest, hover and focus, light and dark) were inspected.
