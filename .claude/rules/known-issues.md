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

5. **Tab skips Settings rows scrolled out of view in a shrunk window** (found 2026-11-05,
   v1.4.29 classic pane). At the default 480×470 size the whole page fits and Tab reaches
   every control. If the window is shrunk below its content height (e.g. the 440×320
   minimum), SwiftUI's focus routing skips rows fully clipped by the scroll view (workdays,
   AI search and the Quit link), even though the AppKit key-view loop contains all of them
   in order (probe: 31 entries, correct order). v1.4.27's layout reached offscreen rows, so
   this is a regression limited to shrunk windows. Root cause not yet identified; the
   section accessibility containers were ruled out experimentally.

## Test Status

- GlimpseCore: 32 tests, 3 suites — `cd GlimpseCore && swift test`
- App tests: 18 tests, 3 suites — `xcodebuild test`
- Total: 50 tests — all pass
