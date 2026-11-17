# Auto prefers on-device AI with one Cloud AI fallback (v1.5.1/build38)

## Product authority

The owner reported that their Glimpse shows "AI couldn't complete that. Try again." for every Ask Glimpse query. Cause: the default provider, Auto, always resolved to Cloud AI (`AIDateHelper.provider(for:onDeviceSupported:)`), and the Cloud AI proxy currently returns `Upstream error: 401` on the server side (known issue 5). On-device AI was unaffected but was never used by Auto. The requested change: Auto should prefer on-device AI when supported, fall back once, and leave explicit choices unchanged.

## Implementation

- **Routing (pure):** `AIDateHelper.provider(for:onDeviceSupported:)` now returns `.onDeviceThenProxy` for Auto when on-device AI is supported (macOS 26 + FoundationModels), otherwise `.proxy`. Cloud AI stays `.proxy`; On-device AI stays `.foundationModels` / `.none`.
- **Fallback:** `.onDeviceThenProxy` runs on-device first. The on-device branch only throws `unavailable`, `onDeviceRequest` (any generation/network/unusable-output failure) or cancellation, so any on-device `AIDateFailure` makes Cloud AI run exactly once and its result or error is shown. The earlier `allowsAutoFallback` filter was removed: it could only ever see those two cases, so it looked more selective than it was.
- **Apple Intelligence off:** if on-device was `unavailable` and Cloud AI then fails too, Auto throws `onDeviceOffCloudFailed` and shows "Cloud AI couldn't complete that and on-device AI is off. Turn on Apple Intelligence in System Settings, or try again." This replaces the bare "AI couldn't complete that", which gave no hint while the proxy 401 persists.
- **No fallback for:** cancellation (propagates), an answer with nothing usable (nil → "I didn't catch that"), and explicit Cloud AI / On-device AI choices.
  - Owner decision needed: when on-device AI answers but `AIIntentDecoder.validate` rejects the output, the result is nil and Auto does not fall back. This matches the proxy's nil path ("understood, nothing usable"). It could also count as an "unusable response". The behaviour is pinned by `autoDoesNotFallBackWhenOnDeviceAnswersWithNothingUsable`.
- **Settings:** the AI provider picker has a tooltip per choice (`AIProvider.helpText`). Auto: "Uses on-device AI when available and falls back to Cloud AI if on-device AI is unavailable or fails. Uses Cloud AI otherwise." A tooltip was used instead of an extra visible line so the Settings content height (and the known issue 4 minimum height) is unchanged.
- **Diagnostics:** the active provider for Auto now reads "On-device AI, Cloud AI fallback".
- **Logging:** the fallback logs only a fixed category ("AI auto fallback: cloud"); no query or payload.
- Known issue 2 ("Auto always returns proxy") removed; known issue 5 notes that Auto users with Apple Intelligence are largely unaffected (a cold on-device failure still reaches the failing proxy). `docs/ux-audit.md` no longer says the Auto-to-proxy behaviour stays, and the Tab-routing comment in `PreferencesAccessibilityTests` now points at the renumbered known issue 4.

## Verification evidence

- **Tests first:** the new routing expectation, `AIAutoProviderTests` and `AIProviderHelpTextTests` were written before the implementation. The GlimpseCore run was confirmed red (no `helpText`) before implementing; the app suite was not run in its red state.
- **New tests (Swift Testing):**
  - `routingPrefersOnDeviceOnlyForAuto` — all 6 preference × support combinations.
  - Fake providers: on-device answer skips Cloud; on-device unavailable / generation error falls back to Cloud exactly once; on-device request failure plus Cloud failure shows the Cloud error after one call each; on-device unavailable plus Cloud failure gives `onDeviceOffCloudFailed`; cancellation during the Cloud fallback stays cancellation; nil answer and cancellation do not fall back; explicit Cloud and On-device never call the other provider.
  - Provider names and help text for all choices.
  - Model level: the `AIDateModelFixture` resolver now calls the real `AIDateHelper.provider(for:onDeviceSupported:)` instead of a hard-coded copy of the old routing. `autoRequestUsesRealRouting` checks that Auto reaches the provider as `.onDeviceThenProxy` (supported) or `.proxy` (unsupported), and `autoBothUnavailableTellsUserToTurnOnAppleIntelligence` checks the new message.
- **QA:**
  - GlimpseCore: 214 tests in 14 suites pass (`swift test`).
  - App: 397 tests in 40 suites pass (`xcodebuild test`).
  - Debug build succeeds.
  - Live on-device check (`TEST_RUNNER_GLIMPSE_LIVE_AI=foundationModels`, `AILiveProviderGoldenTests`) on 2026-11-16: the first, cold run failed 2 of 4 queries with `onDeviceRequest`; the next two runs passed 4 of 4. A cold on-device failure in Auto now falls back to Cloud AI, which still fails while the proxy 401 persists.
- **Code review (A1–A8):** no blockers.
  - A5.2: `#if canImport(FoundationModels)` / `@available(macOS 26, *)` usage unchanged; the graceful fallback to the proxy is now real for Auto.
  - A5.1 / privacy: in Auto a query can reach Cloud AI only after on-device fails, which is what Auto means and what the tooltip says; explicit On-device never leaves the Mac.
  - A7: no `try?`, sleeps, force unwraps or magic numbers added; cancellation is re-checked inside each provider call, so a cancelled request never starts the fallback.
  - A8: every new function and case has tests.
- **UX:** the visible Settings layout is unchanged. The only new copy is the Auto-only Apple Intelligence message.

## Known issue

Cloud AI still returns the upstream 401 (known issue 5, server side). Users who explicitly pick Cloud AI, Macs without on-device AI, and cold on-device failures still see "AI couldn't complete that."
