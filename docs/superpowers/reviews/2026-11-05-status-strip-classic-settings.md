# Status strip footer and Classic preferences Settings (v1.4.29/build36)

## Product and design authority

After using installed v1.4.28, the user rejected the whole footer and Settings redesign. They asked for five mocks of each, side by side, with pick and refine controls. From that comparison (`build/design/2026-11-04-redesign-options/`) they picked **A · Status strip** for the footer and **C · Classic preferences pane** for Settings. Their picks were recorded by the page's local feedback endpoint on 2026-11-05, with no refinement notes.

## Implementation

**Footer.**
- A 30pt bar.
- The left side shows today's context ("Week N · Thu, Nov 5").
- The right side has three 28pt icon buttons matching the header arrows:
  - Pin: toggles through `CalendarPanel.setPinned`, with a selected tint while pinned.
  - Settings.
  - Quit: still asks for confirmation.
- Keyboard owners `.footerPin`, `.footerSettings` and `.footerQuit` keep the existing Return/Space ownership.

**Settings.**
- One page with no cards or visible titles.
- Rows have right-aligned labels: Startup, Keyboard shortcut, Calendar window, Menu bar shows, Style, Week starts on, Workdays and AI date search.
- Groups are separated by rules, and switches became native checkboxes.
- Each category is a named accessibility group, so VoiceOver keeps the category names.
- Every preference setter, recovery message, recorder path, the pin binding, and the About, Open Calendar and Quit links are unchanged. The version is shown at the bottom right.
- The window is 480×490. Its minimum content height equals the full content height, so resizing can never clip rows; this mitigates known issue 5, raised by the PR38 review.

**Fixes found during verification.**
- The AI provider popup was labelled twice ("AI provider, AI provider"); the duplicate is removed.
- Focus reveal kept a 28pt row margin after the visual row height shrank. It now uses `revealRowHeight`.

## Verification evidence

- Actual native renders were inspected:
  - Settings in light and dark, at nominal and constrained sizes.
  - The full calendar with the new footer.
- Test contracts were updated for the new structure:
  - Footer order is Pin, Settings, Quit, with 28pt targets.
  - Settings sections are identified by accessibility group.
  - Row labels and geometry tokens match the new layout.
  - One device pixel of scroll rounding is allowed for baseline-aligned rows.
  - A disabled checkbox keeps its owned focus while launch-at-login updates. This is an intentional change from the old switch, which dropped focus to the window.
- An independent review of these contract changes found no weakened assertions beyond the documented pixel tolerance and the native 16pt checkbox height.
- The exact-staged Quality hook runs for this commit.

Known issue 5 (SwiftUI Tab routing skips fully clipped Settings rows) is recorded in `.claude/rules/known-issues.md`. It is mitigated by the content-height minimum and is only reachable on screens with less than about 520pt of usable height. A test now asserts that the document fits at the minimum size. Other-machine crash causality, the real restart check, physical VoiceOver and endurance remain separate.
