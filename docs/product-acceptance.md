# Product acceptance — 1.4.4 / build 11

Reviewed 2026-11-01 against `docs/stability-roadmap.md`, `docs/ux-audit.md`, current app/core source, and recorded test evidence.

**Scoped product review complete; passed for the bounded first-release improvements below.** This passes the product phase only. It does not approve release readiness, replace independent UX/code/QA gates, close the broader reliability goal, or establish that the reported crash or restart failure is fixed. Readiness settings were not changed by this review.

## Evidence and accepted behavior

| Area | Accepted product behavior and evidence |
| --- | --- |
| Truthful startup | `LaunchAtLoginClient` preserves enabled, approval-required, unregistered, not-found, and unavailable states. `PreferencesFeature` derives the switch from observed status, serializes changes, and re-reads status after completion/error and activation. `PreferencesView` explains the state and offers **Open Login Items**. Successful registration is no longer presented as proof that macOS enabled startup. Reducer tests cover statuses, rapid changes, failures, and external changes. |
| Safer persisted settings | Hotkey values are validated before unsigned conversion; invalid weekdays fall back and invalid workdays are discarded. Tests cover negative, oversized, out-of-range, and valid values, including preservation of an empty workday selection. These fixes address source trap paths; they do not identify the other Mac's crash cause. |
| Reliable event presentation | EventKit queries the selected local day through a serial actor. Selection, AI navigation, Today, deselection, and reopen refresh matching results. Date plus request identity and cancellation prevent stale responses from replacing current results. Loading, empty, error/retry, and authorization states are distinct; revoked access clears results. Tests exercise DST boundaries, overlap preservation, stale responses, cancellation, failures, and permission changes. |
| Input lifecycle | Calendar navigation is scoped to its visible panel, editor arrows and modified navigation pass through, recording suspends calendar handling, and explicit hide/show notifications remove/reinstall monitors. Pure routing tests support the contract; native focus and monitor lifetime remain QA work. |
| Actionable diagnostics | Export opens an asynchronous standard save dialog for a plain-text file, suggesting Desktop and a timestamped filename. The user chooses the destination; cancellation returns to idle without collecting logs or writing a report. The sandbox entitlement grants access to user-selected files rather than relying on automatic Desktop writes. `export(to:)` preserves metadata when log collection fails. Collection avoids pipe backpressure, has a ten-second subprocess deadline, and limits the in-memory excerpt to 1 MiB. Reports include app path, PID, version/build, startup status, and effective settings. Regression tests cover chosen destinations, partial reports, write failures, output volume, deadlines, and collector failures. About retains **Show in Finder**, **Export again**, and failure **Retry**. Native save-dialog permission and destination behavior remain unverified. |
| Repeatable evidence | Monitoring distinguishes the exact installed process from development/test processes, retains timestamped availability/crash/resource observations, and emits meaningful state-change events. Quality tooling retains logs and result bundles with pipeline failure propagation. Monitoring does not itself schedule checks, send notifications, query login disposition, or prove menu-item visibility. |

Inspected successful summaries: `/tmp/glimpse-app-final.log` records **57 tests in 9 suites** and `TEST SUCCEEDED` after the save-flow correction; `/tmp/glimpse-core-green.log` records **62 tests in 5 suites**. Final integrated quality checks remain a separate integration requirement. This product review did not duplicate those builds.

The local baseline in `docs/qa-baseline.md` is installed **1.4.3 / build 10**, alive for approximately 33 days with sampled `0.0%` CPU. It supports a healthy local baseline only. It is not 1.4.4 endurance evidence and cannot explain another machine's failure. The reported other Mac's logs are unavailable; the local retained-report search found no matching production report.

## Deferred validation and release gates

- Finish isolated native QA: repeated panel cycles, AI editing/Return/Escape, shortcut recording, About, preferences, pin/unpin, settings return, diagnostics actions, screen fit, and menu-item visibility. At this review, the isolated app was running but the interaction matrix was unfinished because of the UI tool's window constraint.
- Verify the diagnostics save dialog and macOS Powerbox grant in the signed sandboxed app: cancel without collection, choose Desktop or another location, save and inspect a full/partial report, reveal the chosen file, export again, and retry a destination failure. Fixture writes to temporary destinations do not prove user-selected access or native save-dialog behavior.
- Verify the signed installed build through actual login/restart, approval-required recovery, sleep/wake, multiple displays, date rollover, and live EventKit scenarios. Unit tests do not substitute for these checks.
- Measure sustained 1.4.4 CPU, memory, responsiveness, availability, and unexpected exits after interaction. Do not claim improved performance from the old installed process's idle samples.
- Complete final quality, UX/code/QA evidence, and exact source/artifact/feed verification before publication. Delivery/recovery fixtures and source review do not establish an executed healthy 1.4.4 release, successful rollback, a greater-than-99% release success rate, or checks for every intermediate commit in a batched push.

## Next iteration

1. **QA + Developer:** finish native checks and collect controlled login/restart evidence against the roadmap's three-run target. Investigate any discrepancy before extending features.
2. **Integrator + QA:** configure the authorized recurring availability check, observe the new installed build over time, and distinguish missing processes from hidden/overflowed menu items. Capture version, path, timestamps, and termination evidence when failure occurs.
3. **Developer + PM:** use evidence from the affected Mac when available to reproduce the reported failure. Keep the original crash and unattended-startup criteria open until supported by relevant evidence.
4. **UX Designer + Developer:** address reachable preferences on small/scaled displays, remaining accessible control labels/targets, shortcut-registration recovery, and update-error retry. Then consider opening selected-day events in Calendar.
5. **DevOps + Reviewer:** verify delivery/recovery in executed runs and close documented repository enforcement and per-commit coverage gaps; measure release-cycle and recovery outcomes across multiple releases.

The first release provides clearer state, safer boundaries, and useful evidence. The ongoing goal remains dependable availability across the user's machines.
