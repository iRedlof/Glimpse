# Glimpse stabilization and delivery design

The user needs Glimpse to remain available as a menu bar calendar, start reliably
after macOS login, and ship improvements through verified automated releases.
The reported crash occurred on a different machine without accessible reports.
No fix in this iteration can honestly establish that crash's cause.

## First delivery

Keep Swift 6, TCA, macOS 14+, the current calendar layout and signing identity.
Do not install a watchdog that overrides an intentional quit or a disabled login
item. Treat macOS as the authority for startup status.

1. Expose enabled, approval required, disabled, missing and unknown login-item
   states. Reconcile actual status after a registration operation and returning
   from System Settings. Serialize changes and give approval a recovery action.
2. Bound diagnostic log collection to ten seconds and 1 MiB in the report.
   Never wait for process exit before draining a bounded pipe. Keep version,
   application path, startup status and collection failure in the exported report.
   Preserve a retry action after export failure.
3. Validate persisted weekday and hotkey values before arithmetic or conversion.
   Invalid values use documented defaults. Prevent local calendar event monitors
   from consuming another window's events or normal text editing.
4. Query the selected local day rather than filtering today's results. Clear
   unauthorized and stale data; latest date selection wins. Reflect the queried
   date and loading state in the UI.
5. Pin the same dependency graph for app and core tests. Run tests and quality
   checks for pushes and PRs. Serialize releases, enforce previous-release
   verification, publish only verified assets, and withdraw a failed new
   publication without modifying older releases.
6. Provide repeatable local health sampling and quiet recurring monitoring that
   reports meaningful absence, new crashes, release failures or required action.

The Tech Lead owns integration. Product and UX provide acceptance documents;
Developer owns startup state; QA owns independent tests and live evidence;
DevOps owns release gates, artifacts and failure recovery. Ownership and
priorities are in `docs/stability-roadmap.md`; UX criteria in `docs/ux-audit.md`.

## Verification and limits

Use Swift Testing and TCA TestStore. Demonstrate failing regressions before fixes
and run both complete suites. Smoke-test a separate development bundle without
changing the installed app's preferences, login registration or hotkey.

Record idle/open CPU and memory, repeat open/close/input flows, and inspect
retained Glimpse reports. Actual restart/login tests remain required on a signed,
installed release; do not reboot the user's computer automatically.

Release withdrawal can restore the previously published update feed. It cannot
downgrade an already installed app without a newly signed release with a higher
build number. Local hooks enforce commit/push gates only in configured clones;
repository rules require GitHub administrator permissions for universal control.
100% automated commit testing means every commit is checked, not 100% line coverage.
99% release success and 24-hour lead time need historical measurements.
