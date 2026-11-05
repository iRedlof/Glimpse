# Approved Settings and footer

The user approved **Settings & Quit** and **Native groups** on 2026-11-04, referencing the comparison page `glimpse-design-comparison.html` (SHA256 `e0242ba7f656b94705326ffb3d67126f2b1f82f23b053e543b9ff2d6e5dc305c`). This approval is the binding design specification.

## Requirements

- Two equal, connected footer cells: Settings then Quit, inline icon and label, subtle separator, full-cell hover and native keyboard activation.
- One compact, categorized Settings page in its retained separate window: modest headings, native controls, filled groups without normal-contrast outer outlines.
- Opening Glimpse retains login and shortcut controls and adds the existing transient Pin calendar action. Menu bar, Calendar and AI date search retain every preference and real preview/provider behavior.
- About, Open Calendar app and Quit remain available as small Settings-window actions.
- Preserve startup errors/recovery, pending shortcut intent/recording, accessibility and native focus.
- Settings handoff preserves pinned calendar frame/date/scroll; an unpinned calendar hides. Closing Settings never reopens the calendar.
- Do not add persisted pin state, change provider policy, change permissions, or reboot the Mac.

## Ownership and interfaces

Root owns production views, window coordination and delivery records. The existing **Glimpse QA and release verification** chat owns test files and serialized SDK/native execution. A separate reviewer checks the whole final diff; UX compares actual renders against this approved pair.

The Settings controller must bind to the exact calendar passed through the existing show path. Its Pin binding invokes the calendar's existing reducer action and synchronizes native panel state; it cannot search for another panel or store a second preference. Root keeps the existing priority coordinator and window fitting rules.

## Task 1: approved native presentation

Files: `CalendarPopoverView.swift`, `AppDesign.swift`, `PreferencesView.swift`, `SettingsRootView.swift`, `SettingsWindow.swift`, `CalendarPanel.swift`.

1. QA adjusts footer accessibility/traversal tests for the approved two controls and adds real Settings action/pin coverage; observe the expected old-design failure.
2. Implement the two-cell footer and compact native Settings groups; connect moved actions to their existing implementations.
3. Run focused native Settings/footer/keyboard checks and inspect light/dark renders.

Expected: exactly two equal footer cells; all settings/actions reachable; no pinned calendar movement or selection loss; recording/login recovery unchanged.

## Task 2: review and delivery

Files: version/build project settings, README, inventory/roadmap and release-readiness evidence.

1. Independent A1–A8 source review and bounded UX review of actual renders; resolve material findings.
2. Synchronize the next release version/build and run the ordinary exact-source quality gate.
3. Use the existing protected PR/release flow; verify signed public artifacts before the authorized official installation.
4. Inspect the installed app and capture the approved footer/Settings. Record actual boundaries separately from other-machine crashes, restart and physical accessibility.

Expected: actual installed app implements the approved pair; delivery receipts identify exact source/version/build and checks without claiming unobserved reliability outcomes.
