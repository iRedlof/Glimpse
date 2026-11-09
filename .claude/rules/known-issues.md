# Known Issues & Deferred Items

These items were reviewed and intentionally deferred. Do not attempt to fix
them unless explicitly asked — the rationale for each is documented here.

## Deferred

1. **Ad-hoc signing keychain prompt** — Every rebuild with `--sign -` creates a new
   identity, which can trigger Keychain password prompts. Partially mitigated by not
   reading Keychain on every preferences open. Full fix requires a valid developer cert.

2. **Auto AI provider always returns proxy** — `AIDateHelper.activeProvider()` with
   `.auto` always returns `.proxy`. Does not fall back to on-device FoundationModels.
   Intentional: proxy is always available and more reliable.

3. **PreferencesView creates new Store each time** — `Store(initialState:)` is created
   inline in CalendarPopoverView. This means preferences state resets on each toggle.
   Acceptable because state is loaded from UserDefaults in `onAppear`.

4. **Sparkle update check may fail silently** — Without a valid appcast URL and EdDSA
   key, Sparkle's check completes with no visible feedback. The inline status UI handles
   this with error state display.

5. **Tab skips Settings rows scrolled out of view** (found 2026-11-05, v1.4.29 classic
   pane). SwiftUI's focus routing skips rows fully clipped by the Settings scroll view
   (workdays, AI search, Quit link) even though the AppKit key-view loop contains all of
   them in order (probe: 31 entries). Mitigated: the window's minimum content height equals
   its full content height (490pt), so normal resizing can't clip rows. Remains possible
   only on screens whose usable height is below ~520pt, where fit() clamps the minimum.
   v1.4.27's layout reached offscreen rows; root cause not identified (section
   accessibility containers ruled out).

5. **Cloud AI upstream returns 401 (server side)** — Checked live on 2026-11-08: the
   `{tier, prompt}` request to `proxy.auris.workers.dev/refine` is accepted (HTTP 200),
   but the body is `{"text":null,"error":"Upstream error: 401"}`, so every Cloud AI query
   shows "AI couldn't complete that. Try again." This predates Type to Schedule (v1.4.29
   is affected too). Fix belongs on the proxy (upstream key); the client contract, headers
   and secret handling are unchanged. On-device AI is unaffected. Re-checked later on
   2026-11-08 with `AILiveProviderGoldenTests` (proxy): still `unusableResponse` for all
   four example queries; on-device passes all four.

6. **Type to Schedule scope** — Writes only to the default writable calendar (named on
   the card), single-day timed events only; no invitees, location, recurrence, or
   non-default calendar choice. Workday counts don't know holidays (the answer says so).

## Test Status

- GlimpseCore: 212 tests, 13 suites — `cd GlimpseCore && swift test`
- App tests: 385 default-run tests — `xcodebuild test`; key-panel suites (keyboard 45, AI 11, agenda 13) run in the quality gate
- Live AI golden check (opt-in, 4 queries): `TEST_RUNNER_GLIMPSE_LIVE_AI=foundationModels`
- All pass
