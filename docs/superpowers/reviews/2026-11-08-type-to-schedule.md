# Type to schedule in the Ask Glimpse field (v1.5.0/build37)

## Product and design authority

The owner reviewed eight big-idea picture stories (`hearth-task-artifacts/hearth-studio/big-ideas/`). On 2026-11-08 they voted 👍 for **Type-to-Schedule AI** and asked for it to be built ("build it").

## Implementation

The ⌘G field ("Ask Glimpse") now interprets five intents, validated in GlimpseCore (`AIIntent`, `AIIntentDecoder`):
- **Navigate:** unchanged behaviour.
- **Range:** for example "next 3 Fridays". Up to 31 days are highlighted.
- **Question:** for example "how many workdays until Mar 1?". It is answered locally by `DateAnswerer`, using the Workdays setting.
- **Create:** for example "coffee with Priya Thursday afternoon, 30 min". `FreeSlotFinder` finds up to 3 free slots around the user's events. The user picks one with ↑/↓ or a click, and Return saves through EventKit. An Undo button lasts 10 s, and ⌘Z also undoes.
- **Clarify:** one short question when the request isn't understood.

Rules the feature follows:
- **Honest buttons:** nothing is preselected, and nothing is written without an explicit pick. "Saving…" stays until EventKit confirms. Failures say "Nothing was saved."
- **Permission:** calendar access is requested only from an explicit "Allow calendar access" button. Denied access is explained, and the other intents keep working.
- **Dates:** the model never does date arithmetic. `DayPhraseParser` resolves relative weekdays and parts of day in Swift.
- **Privacy:** the AI never sees calendar data.
- **On-device AI:** uses `@Generable` behind `#if canImport(FoundationModels)` and `@available(macOS 26, *)`.

## Verification evidence

- **Code:** a pre-production review against A1–A8 returned SHIP. A fresh re-review after the fixes also returned SHIP, with no blockers.
- **QA:**
  - GlimpseCore: 212 tests.
  - App: 385 tests.
  - The key-panel suites pass.
  - The pre-commit quality gate passes.
  - CI `app-and-core` passed on PR #39.
- **Live AI:** with `TEST_RUNNER_GLIMPSE_LIVE_AI=foundationModels`, `AILiveProviderGoldenTests` passes all four example queries in three runs plus an independent run on 2026-11-08:
  - next Friday
  - next 3 Fridays
  - workdays until Mar 1
  - coffee Thursday afternoon
- **UX:** native renders of each state were captured in light and dark and inspected. Keyboard acceptance shows two Returns before a pick save nothing, and ↓ ↓ Return saves exactly once.

## Known issue

Cloud AI (the Auris proxy `/refine`) returns `Upstream error: 401` on the server side. This was already true in v1.4.29 and is recorded as known issue 5 in `.claude/rules/known-issues.md`. On-device AI is unaffected. The client request is unchanged.
