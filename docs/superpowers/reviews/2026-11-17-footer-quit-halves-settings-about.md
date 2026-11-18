# Half-and-half Quit confirmation and About in Settings (v1.5.3/build40)

## Product authority

On 2026-11-17 the owner sent screenshots of the current UI with two requests:
- **Calendar footer:** the Quit confirmation should take over the whole footer, split half and half.
- **Settings:** remove the footer (About, Open Calendar, Quit, version) and keep About as the last item of the Settings page.

## Implementation

**Calendar footer:**
- Cancel fills the left half and "Quit Glimpse" (white on red) the right half, each the full 30pt footer height.
- The question "Quit Glimpse?" moved into the tooltip.
- Unchanged: VoiceOver names, focus owners, Escape, Return/Enter/Space, held-key repeats and Tab order.
- Voice Control input labels were added.

**Settings:**
- The footer is removed.
- A last "About:" section shows "Glimpse <version> (<build>)" and an "About Glimpse…" button that opens the existing About window.
- The Settings Quit sheet and the Open Calendar launcher are removed with the footer, and the roadmap docs are updated to match.

## Verification

- **Code:** pre-production review A1–A8 returned ship, and all five should-fix notes were addressed.
- **QA:**
  - GlimpseCore: 214 tests.
  - App: 400 tests.
  - Keyboard ownership: 44 methods / 89 cases.
  - AI integration: 11. Agenda: 13. Python tooling: 239.
  - The full quality gate passed.
- **UX:** native renders of the calendar footer (normal and confirm, light and dark, and keyboard focus) and of Settings with About last (nominal and constrained, light and dark) were inspected.
