# Glimpse QA baseline — 2026-11-01

Baseline source: `1eaae2643625f435c3a5b176b7f63b5de1ebcd21` in the original checkout at `/Volumes/xHome/Github/Glimpse`. Test artifacts are outside source under `/tmp/glimpse-qa`. The installed app, preferences, login registration, and running process were not changed.

## Installed runtime evidence

| Observation | Result |
| --- | --- |
| Installed and running app | `/Applications/Glimpse.app` |
| Bundle identifier | `com.rohit.Glimpse` |
| Version / build | `1.4.3` / `10` |
| Runtime host | macOS `27.0.1` (`26A434`), Xcode `27.0` (`27A266a`) |
| Installed process | PID `2805`, started September 29, approximately 33 days and 8 hours of uptime |
| Process CPU | `0.0%` in repeated `ps` samples; cumulative CPU `30.58 seconds` |
| Resident memory | `17,728–17,776 KiB` in four samples two seconds apart; earlier snapshot `10,944 KiB` |
| launchd runtime job | Running; `runs = 1`; `last exit code = (never exited)` |
| macOS Background Task Management | Glimpse app entry, `Disposition: [enabled, allowed, notified] (0xb)`; sandboxed; URL `/Applications/Glimpse.app`; generation `2` |
| Accessibility runtime | Application alive, accessory activation policy, not hidden; owned `AXMenuExtra` present and enabled, size `101 × 24` |
| Menu item location | AX position `(-472, 3)`, within the active left display bounds `(-2560, 0, 2560, 1440)`; second display bounds `(0, 0, 2560, 1440)` |

The current process is alive and idle, and macOS currently allows it to launch at login. Those observations cannot establish registration state at an earlier restart or explain a crash on the user's other machine. The AX item location confirms an existing item on the left display; it does not prove visibility in the menu bar on every display or rule out menu bar overflow.

`sfltool dumpbtm` returned the Glimpse registration on its second unprivileged attempt. Other attempts timed out after 25–30 seconds, so this command is not reliable as a fast health check on this host. The database directory requires elevated read access; no elevation was performed.

Runtime read-only output is saved in `/tmp/glimpse-qa/installed-runtime.txt`.

## Retained crash reports

A case-insensitive filename search for Glimpse recursively covered both:

- `~/Library/Logs/DiagnosticReports`, including its existing `Retired` directory.
- `/Library/Logs/DiagnosticReports`, including its existing `Retired` directory.

There were **zero Glimpse-named retained reports** and no directory-read errors. This includes all retained dates in those trees. Absence of a retained report does not prove absence of a historical crash: reports can expire, an app can exit without crashing, and the reported failure occurred on another machine whose logs are unavailable.

## Baseline tests

| Suite | Command / artifact | Outcome |
| --- | --- | --- |
| App | `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -skipMacroValidation -derivedDataPath /tmp/glimpse-qa/app-build -resultBundlePath /tmp/glimpse-qa/app-baseline.xcresult CODE_SIGNING_ALLOWED=NO test` | Passed: **42 tests in 7 suites**, exit `0` |
| GlimpseCore | In `GlimpseCore`: `swift test --scratch-path /tmp/glimpse-qa/core-build` | Build failed before tests, exit `1` |

App log: `/tmp/glimpse-qa/app-baseline.log`. Structured test results: `/tmp/glimpse-qa/app-baseline.xcresult`. No framework re-signing was required for this baseline run.

Core log: `/tmp/glimpse-qa/core-baseline.log`. Failure:

```text
swift-composable-architecture/Sources/ComposableArchitecture/Observation/NavigationStack+Observation.swift:149:17:
error: cannot form key path to main actor-isolated subscript 'subscript(fileID:filePath:line:column:)'
```

The two local lockfiles resolve different graphs; the app lockfile was ignored at baseline:

| Dependency | Core lockfile | App lockfile |
| --- | --- | --- |
| Composable Architecture | `1.25.2` | `1.26.1` |
| Swift Navigation | `2.7.0` | `2.10.3` |
| Sparkle | `2.9.0` | `2.9.4` |

The app's dependency graph compiles on Xcode 27. The core's older graph fails in dependency source. This is a test/build compatibility failure; it is not evidence of a shipped app runtime crash. The repository notes claiming 18 app tests and 32 core tests are stale.

## Source risks and regression priorities

These are source-supported risks, not a demonstrated explanation of the unavailable other-machine crash.

| Review area | Evidence | Regression needed |
| --- | --- | --- |
| A7.2: startup input validation | `HotkeyCombo.load()` converts persisted integers directly to `UInt32`. Negative or out-of-range values trap. | Missing keys; negative key/modifier; integers above `UInt32.max`; valid custom key; invalid modifier bits. Verify fallback and no startup trap. |
| A6/A8: login status | The baseline client exposes only `status == .enabled`. Successful registration leaves the optimistic UI toggle true without re-reading actual status. | Model every `SMAppService` disposition; successful call followed by approval-required/not-found; thrown error; rapid repeated toggles; refresh after System Settings changes. Use injected clients, without modifying this machine's registration. |
| A7.5: diagnostics subprocess | Export starts a child before assigning its termination callback, and reads its pipe only after termination. Large output can fill the pipe and prevent exit. | Empty output; output larger than pipe capacity; child failure; immediately exiting child; timeout and cancellation. Ensure export completes or reports a bounded failure. |
| A2/A3: panel event handling | Local key monitors are application-wide and removed only through SwiftUI disappearance; reused panel hide/show does not guarantee that callback. | Hidden panel and About window must not consume navigation/Enter/Escape. AI field arrows must move its caret. Reopen and repeated hide/show must not multiply monitors. |
| A2/A7.5: redraw convergence | Current source already composites the status item into one image and guards panel frame mutation with a `0.5pt` tolerance. | Idle panel closed/open; repeated preference changes and theme changes; ensure resize stabilizes and CPU returns to idle. |
| A2: empty display | Current renderer forces a date icon when formatted text is empty. | All text/icon preferences off still produces a nonempty, usable item in both appearances. |

## Manual regression matrix

Run against a separate development app with a unique bundle identifier and preference domain. Preserve PID 2805. Disable its global hotkey and automatic update checks through launch arguments so it does not contend with or update the installed app. Never register/unregister the QA app as a login item during this session.

| Scenario | Check / evidence |
| --- | --- |
| First launch | Development process remains alive; menu extra exists; no prompt unless the user invokes a permission-requiring feature. |
| Panel lifecycle | Open/close/reopen 20 times; preferences collapse; current month/today selection restores; pin/unpin and Escape work; monitors stay bounded. |
| Text input | Type, move caret with arrows, submit with Enter; close AI field; previous app focus restores. |
| Hidden-panel keyboard | About window navigation and text fields receive their own keys; hidden calendar does not react. |
| Render combinations | Both appearances, filled/bordered, icon/text combinations including every display field disabled; readable width and nonempty fallback. |
| Multiple displays | Open from each display, check caret/edge placement; disconnect/reconnect with user-controlled hardware; account for menu bar overflow and separate Spaces. |
| Date lifecycle | Midnight and DST through deterministic tests; wake/reopen after a date change; today's events refresh and permissions remain correctly represented. |
| Login lifecycle | Injected status/error tests now; actual reboot/login/approval scenarios on a disposable test account or later user-authorized session. |
| Diagnostics | Export under low/high log volume; immediate process exit and deadline; no hangs or confidential query/calendar data in exported logs. |
| Sustained runtime | Leave development app idle with panel closed/open and after interaction; record CPU, cumulative CPU, RSS, PID uptime, and new Glimpse-only reports. |

## Metrics and practical limits

- Record wall-clock timestamp, source revision, bundle version/build, macOS build, app path/PID, and current login disposition with each run.
- Compare CPU and RSS only after builds finish. Track one-minute idle CPU median/p95, CPU time per elapsed minute, and memory before/after repeated panel cycles. The observed installed process supplies an idle reference, not a universal memory threshold.
- Initial performance gate: CPU settles near idle within five seconds after interactions; no sustained redraw loop; RSS plateaus after warm-up across repeated cycles. Investigate a persistent CPU increase or monotonic memory growth instead of dismissing it as test variance.
- Count app starts and unexpected exits; distinguish a missing process from a running process whose menu extra is offscreen/overflowed. Capture a Glimpse crash report or scoped process sample when the failure is present.
- No reboot, installed-app quit/replacement, settings changes, crash injection, EventKit permission changes, or sustained live development-app regression was performed for this baseline.
