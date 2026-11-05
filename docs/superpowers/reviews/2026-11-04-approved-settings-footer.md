# Approved Settings and footer acceptance

Candidate: **v1.4.27/build34**. Base: canonical `22a96aba891c6f6125928bfec40252de3f5c8f7a`.

## Product and design authority

The user explicitly approved the comparison pair **Settings & Quit** and **Native groups** on 2026-11-04 and instructed implementation with every existing setting/action, separate Settings and no calendar jumping. The comparison artifact SHA256 is `e0242ba7f656b94705326ffb3d67126f2b1f82f23b053e543b9ff2d6e5dc305c`. The [implementation plan](../plans/2026-11-04-approved-settings-footer.md) records the required interfaces and constraints.

Public/installed v1.4.26 is technically verified; the user rejected its design. Its earlier UX acceptance cannot accept this new design or override the user's feedback.

## Implementation

The calendar footer now contains Settings then Quit, with inline labels/icons and equal connected cells. The retained Settings page uses compact native controls, modest headings and filled groups. Pin calendar operates the bound panel's existing reducer and native pin state. About, Open Calendar app and a Cancel-first Quit sheet remain available in Settings. Every preference setter, actual menu-bar renderer, login recovery and shortcut recorder retains its existing path.

## Continuation fixes (2026-11-04, second owner)

Actual native renders of the first candidate showed visible gaps against the approved comparison, now fixed:
- The shortcut recorder shows the saved combination as a compact key, not a truncated monospaced "Set and enable shortcut". Its accessible name and hint are unchanged.
- Workday chips are equal-width connected cells.
- The Week-starts and Provider popups align with the switch column.

The three native failures from the handover were root-caused and fixed:
1. **Settings unpin changed the hidden month.** A Settings-unpin hide is now a one-shot context-preserving hide (`CalendarFeature.hiddenPreservingContext`). All monitor, focus, text-input and event-load cleanup still runs, and every reopen still resets through `prepareForReopen`. Other hide paths keep `.onDisappear`.
2. **Escape left the Quit sheet attached.** Assigning `defaultButtonCell` rebinds Cancel's key equivalent to Return, so no button answered Escape. Return still cancels through the default button. Escape is handled by a monitor scoped to the sheet window and owned by the controller. That monitor also consumes held-Escape repeats after the sheet ends, so they cannot close Settings; a new `escapeHeld` native case covers this.
3. **The fixed utility footer scrolled the settings document.** Focus reveal now ignores focused views outside the Settings scroll view. Native output confirms that every in-document target is a scroll-view descendant and that only the three footer links are outside it. The traversal test now admits footer links as fixed controls: visible, outside the clip, with no document scroll.

## Verification evidence

- The design is the user's explicit choice, and the second owner inspected actual light/dark nominal/compact Settings renders and full-calendar renders.
- An independent lifecycle review found one real defect (held-Escape repeats), which is fixed and covered by a regression test. An independent preserved-actions/accessibility review found no defects.
- Results on the working source:
  - Focused native: unpin, all four Quit-sheet cases, traversal, Settings categories in all four appearances, and the viewport suite passed.
  - GlimpseCore: 71 tests passed.
  - Tooling contracts: 239 passed, with the manifest at 45 methods / 93 cases.
- Exact-staged whole Quality runs in the pre-commit hook for this commit.

Still not established: hosted checks, protected integration, canonical publication, signed public verification and installed appearance. The historical crash on another machine, the real restart check, physical VoiceOver, older macOS/Intel and endurance also remain separate.
