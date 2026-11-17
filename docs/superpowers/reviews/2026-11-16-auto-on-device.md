# Auto prefers on-device AI with one Cloud AI fallback (v1.5.1/build38)

## Product authority

The owner reported that their Glimpse shows "AI couldn't complete that. Try again." for every Ask Glimpse query. Cause: the default provider, Auto, always resolved to Cloud AI (`AIDateHelper.provider(for:onDeviceSupported:)`), and the Cloud AI proxy currently returns `Upstream error: 401` on the server side (known issue 5). On-device AI was unaffected but was never used by Auto. The requested change: Auto should prefer on-device AI when supported, fall back once, and leave explicit choices unchanged.

## Implementation

- **Routing (pure):** `AIDateHelper.provider(for:onDeviceSupported:)` now returns `.onDeviceThenProxy` for Auto when on-device AI is supported (macOS 26 + FoundationModels), otherwise `.proxy`. Cloud AI stays `.proxy`; On-device AI stays `.foundationModels` / `.none`.
- **Fallback:** `.onDeviceThenProxy` runs on-device first. If it throws an `AIDateFailure` where `allowsAutoFallback` is true (unavailable, on-device request failure, unusable response, transport, non-HTTP, non-success), Cloud AI is tried exactly once and its result or error is shown. `requestPreparation` does not fall back.
- **No fallback for:** cancellation (propagates), an answer with nothing usable (nil → "I didn't catch that"), and explicit Cloud AI / On-device AI choices.
- **Settings:** the AI provider picker has a tooltip per choice (`AIProvider.helpText`). Auto: "Uses on-device AI when available and falls back to Cloud AI if it can’t answer. Uses Cloud AI otherwise." A tooltip was used instead of an extra visible line so the Settings content height (and the known issue 4 minimum height) is unchanged.
- **Diagnostics:** the active provider for Auto now reads "On-device AI, Cloud AI fallback".
- **Logging:** the fallback logs only a fixed category ("AI auto fallback: cloud"); no query or payload.
- Known issue 2 ("Auto always returns proxy") removed; known issue 5 notes Auto users with Apple Intelligence are no longer affected.

## Verification evidence

- **Tests first:** the new routing expectation, `AIAutoProviderTests` and `AIProviderHelpTextTests` were written before the implementation. The GlimpseCore run was confirmed red (no `helpText`) before implementing; the app suite was not run in its red state.
- **New tests (Swift Testing):**
  - `routingPrefersOnDeviceOnlyForAuto` — all 6 preference × support combinations.
  - `fallbackCoversUnavailableUnusableAndNetworkFailuresOnly` — every `AIDateFailure` case.
  - Fake providers: on-device answer skips Cloud; on-device unavailable / generation error falls back to Cloud exactly once; both failing shows the Cloud error after one call each; nil answer and cancellation do not fall back; explicit Cloud and On-device never call the other provider.
  - Provider names and help text for all choices.
- **QA:**
  - GlimpseCore: 214 tests in 14 suites pass (`swift test`).
  - App: 394 tests in 40 suites pass (`xcodebuild test`).
  - Debug build succeeds.
  - Live on-device check (`TEST_RUNNER_GLIMPSE_LIVE_AI=foundationModels`, `AILiveProviderGoldenTests`) on 2026-11-16: the first, cold run failed 2 of 4 queries with `onDeviceRequest`; the next two runs passed 4 of 4. A cold on-device failure in Auto now falls back to Cloud AI, which still fails while the proxy 401 persists.
- **Code review (A1–A8):** no blockers.
  - A5.2: `#if canImport(FoundationModels)` / `@available(macOS 26, *)` usage unchanged; the graceful fallback to the proxy is now real for Auto.
  - A5.1 / privacy: in Auto a query can reach Cloud AI only after on-device fails, which is what Auto means and what the tooltip says; explicit On-device never leaves the Mac.
  - A7: no `try?`, sleeps, force unwraps or magic numbers added; cancellation is re-checked inside each provider call, so a cancelled request never starts the fallback.
  - A8: every new function and case has tests.
- **UX:** the visible Settings layout is unchanged; error copy is unchanged.

## Known issue

Cloud AI still returns the upstream 401 (known issue 5, server side). Users who explicitly pick Cloud AI, Macs without on-device AI, and cold on-device failures still see "AI couldn't complete that."
