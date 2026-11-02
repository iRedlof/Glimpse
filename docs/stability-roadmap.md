# Glimpse stability roadmap

Updated 2026-11-01.

## Requirements and assumptions

The user reports that Glimpse disappears from the menu bar without notice, may remain unavailable for days, and is often absent after restarting the Mac. The reported crash occurred on another machine whose logs are unavailable. They want crashes fixed, reliable startup, better performance, iterative UX and useful features, repeatable monitoring and testing, and automated continuous delivery with release verification and recovery.

Availability, truthful startup status, and actionable diagnostic evidence take priority. This ordering is the team's product decision based on those reports. Proposed performance budgets and test counts below are initial acceptance targets, not user-specified requirements. “After restart” means after signing into macOS; a menu bar app cannot be visible before login.

Source observations establish risks and behavior, not the cause of the reported crashes. No crash report or reproduced termination has established that cause yet. The local retained-report search included historical and retired reports, with no production Glimpse match. A successful build or passing unit test does not verify startup after reboot.

## Source evidence

- `GlimpseCore/.../LaunchAtLoginClient.swift` reduces `SMAppService` status to a Boolean. `PreferencesFeature` optimistically shows the requested value and does not reconcile the actual status after successful registration. Approval still required by macOS can therefore look like successful setup.
- `Glimpse/DiagnosticsExport.swift` drains the log pipe only after the child process terminates. Sufficient output can fill the pipe and prevent termination; there is no deadline. This is a diagnostic hang risk, not a proven crash cause.
- `Glimpse/GlobalHotkey.swift` converts persisted integers directly to `UInt32`. `PreferencesClient` accepts an unrestricted start-of-week integer that reaches weekday indexing in `CalendarPopoverView`. Malformed settings are candidate trap paths.
- `CalendarPopoverView` installs application-wide local key monitors without checking the originating window or active text editor. Its reused panel does not reliably receive SwiftUI disappearance callbacks.
- `CalendarFeature.dateTapped` queries today's events and then filters for another selected date. The UI continues to label the result “Today.” Event effects have no cancellation or request identity.
- The existing renderer and panel already contain guards for documented redraw and resize loops. Their effectiveness on the user's machine still needs measurement.
- The original `.github/workflows/release.yml` ran on pushes to `main`, with app test output piped through `tail`. Delivery needs explicit failure propagation, exact source/artifact verification, checks before merge, and verified recovery before remediation proceeds.

## First iteration: restore confidence in availability

| Priority and work | Accountable owner | Acceptance |
| --- | --- | --- |
| P0: establish why the app disappears; validate malformed preferences and startup paths | Developer; QA reproduces | Preserve available termination evidence with version, time, and reproducible action. Negative/oversized hotkey values and weekday values outside 1–7 recover to safe defaults without trapping. Launch, 100 open/close cycles, preferences, hotkey, About, and diagnostics complete without a new crash. Call the reported crash fixed only when its evidence or reproducer supports that claim. |
| P0: truthful launch-at-login UX | Developer; UX Designer reviews; PM accepts | Show actual enabled, disabled, approval-required, or unavailable/error state. Registration completion re-reads macOS status. Approval-required state explains the next step and provides “Open Login Items.” Refresh after returning from settings and on reopening preferences. Rapid toggles do not leave stale success. Tests cover every status, failures, and external status changes. |
| P0: bounded, useful diagnostics | Developer; QA verifies | Export cannot hang on more than 1 MiB of log output or a stalled subprocess. It completes or reports a bounded failure within a proposed 15 seconds. Version, OS, startup status, and collection errors remain available when logs fail. A failure provides retry; success reveals the saved file. |
| P1: window-scoped input and correct event results | Developer; QA verifies | Navigation shortcuts affect the calendar window only and preserve normal text editing and About-window input. Hidden panels consume no keys. Selected-day events use that day's local interval, handle all-day/multiday and DST boundaries, and show the selected date in the heading/empty state. Latest selection wins when queries finish out of order; permission revocation clears stale results. |
| P1: repeatable regression and availability checks | QA owns protocol; Developer owns tooling; Integrator owns CI/monitor configuration | One documented command runs appropriate app/core tests and records failures. A deliberately failing test makes CI fail. Checks run before merge. A repeatable health check distinguishes a missing expected process, duplicate instances, and disabled/approval-required startup. It retains timestamped evidence and alerts on meaningful disappearance/failure, with unchanged healthy checks quiet. |
| P1: verified continuous delivery and recovery | DevOps/Release Orchestrator; Tech Lead integrates; Reviewer audits | All pushed revisions execute quality checks. App releases require product, UX, code and QA evidence; exact source, version/build, signed/notarized assets, Sparkle signature and public feed are verified. A failure withdraws only the release owned by that run and proves the previous distribution is healthy before remediation is unlocked. Configured local commits/pushes and hosted main integration must respect the previous-release gate. |

**Small user-facing feature for this iteration:** a startup status row beneath “Launch at login,” with a clear approval-required explanation and an “Open Login Items” action. It directly addresses the user's uncertainty after restart and is independently testable.

## Release gates and subsequent iterations

- QA verifies the signed app installed in `/Applications` through three consecutive login/restart checks, with an enabled login item and a visible, responsive menu bar item within a proposed 60 seconds after login. Explicitly record checks requiring user participation rather than claiming they ran.
- QA records CPU, memory, responsiveness, and crash evidence across idle, open panel, preferences, light/dark change, sleep/wake, date rollover, and display changes. Proposed budgets: mean CPU below 1% idle and 3% with a static panel over 60 seconds, no sustained resize/redraw loop, and no continuing memory growth after repeated cycles. Adjust budgets only with recorded baseline evidence.
- Reviewer applies `.claude/rules/pre-production-review.md` A1–A8. Integrator ships only after required checks and version/build synchronization.
- DevOps measures commit-to-release time, release outcome and recovery time from GitHub run evidence. Targets are a release cycle under 24 hours and a success rate above 99%; neither can be established from a single release. “100% automated test coverage on commits” means every pushed revision executes checks; it does not mean all code paths have test coverage.
- PM and QA review monitoring evidence after the first iteration before selecting more work. Next useful feature: selected-day agenda improvements, such as opening an event in Calendar, once date correctness is reliable. Broader AI or visual features follow availability and performance evidence.

Product Manager owns prioritization and acceptance language; Developer owns implementation; UX Designer owns clarity and accessibility; QA owns repeatable runtime evidence; Reviewer owns production review; DevOps owns delivery and recovery; Tech Lead integrates and owns final verification. Tests, documentation, and source changes alone must not be presented as proof of unattended availability.

The first release can ship verified, bounded fixes without claiming the historical
crash or unattended restart criteria are satisfied. Its checked-in readiness evidence
must list unperformed restart, sleep/wake and other-machine checks. Those remain open
goal criteria for subsequent monitoring and user-assisted validation.
