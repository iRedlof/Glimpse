# Bounded QA acceptance — 2026-11-01

**Scoped QA passed for the first stability iteration.** This permits the bounded
changes to proceed through staged-source tests, hosted CI and signed-artifact
verification. It does not close the broader reliability goal or certify the
unperformed native scenarios below.

The final app log, `/tmp/glimpse-app-final.log`, records **57 passing tests in
nine suites**, `TEST SUCCEEDED`, exit 0, after version 1.4.4/build 11 and the
chosen-file diagnostics correction. Results:
`/Volumes/xHome/Github/Glimpse/build/validation/app-validation-final-4.xcresult`.
Core verification records **62 passing tests in five suites**, exit 0, in
`/tmp/glimpse-core-green.log`; core source was unchanged afterward.
Release tooling has **74 passing contracts** and monitoring has **27 passing
fixtures**. Independent review also ran the contracts in a nongit staged-archive
environment. A subsequent real-hook attempt exposed Git repository variables
leaking into temporary fixture repositories. The commit was rejected; clearing
those variables inside the archived-quality subshell and adding a nested-repository
regression produced the 59-contract passing rerun. Two subsequent fixtures cover
the canonical repository name and the exact pinned legacy feed after its rename,
bringing that snapshot to 61. Ten first-install recovery contracts and three
public-download contracts bring the current suite to 74. Independent QA reran
all 74 contracts and 27 monitoring fixtures after temporary storage was routed
through the selected external build root; both exited 0.

The first-install contracts reject mismatched run/attempt/source, publication,
successful build, changed main, missing/revoked/untrusted status and an invalid
first Release transition. Public-download fixtures exercise certificate-error
handling, partial-file removal, HTTP rejection and a stale latest feed.
They do not execute a TLS handshake. The release specialist separately used the
live strict curl helper to download the pinned v1.4.3 DMG, tagged feed and latest
feed and confirmed their expected hashes and identical feed bytes.

These regressions cover authoritative startup status and serialized registration,
malformed persisted values, selected-day/DST queries and stale responses,
permission revocation, input-routing decisions, diagnostics output/deadlines,
chosen destinations, partial reports and write failures. Delivery fixtures cover
release identity, retries, ownership-scoped recovery, changed staged source and
failure in an intermediate commit. They are not complete code coverage.

Live evidence in `docs/qa-live.md` establishes isolated startup, an enabled menu
extra and a 60.47-second closed-panel observation with sampled CPU at 0.0% and
resident memory 20.45–22.02 MiB. That older debug copy was ad hoc signed without
sandbox entitlements, retained 1.4.3/build 10 metadata and preceded the final
About/save-dialog corrections. It is not native validation of the final release.

CUA could not reach the isolated accessory application's panel after the recorded
fallback attempts. Delivered keyboard events, repeated panel lifetimes, AI text
editing, real EventKit permissions, signed SavePanel/Powerbox access, multi-monitor
behavior, sleep/wake and actual logout/login/restart remain **unperformed**.
The installed application, login registration and TCC settings were preserved.

All retained user/system crash-report directories, including Retired, were
searched without a Glimpse report. The reported crash occurred on another Mac
whose logs are unavailable; its root cause remains unknown.

Product, UX and code reviews accept the bounded source contract with these limits.
Exact staged-tree quality checks and hosted CI are mandatory independent gates.
Release publication must additionally pass the signed, notarized, downloaded
artifact and public-feed checks. Hourly local monitoring records meaningful
availability/crash-report changes while leaving unchanged observations quiet.
