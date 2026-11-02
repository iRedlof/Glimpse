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
Release tooling has **100 passing contracts** and monitoring has **27 passing
fixtures**. Independent review also ran the contracts in a nongit staged-archive
environment. A subsequent real-hook attempt exposed Git repository variables
leaking into temporary fixture repositories. The commit was rejected; clearing
those variables inside the archived-quality subshell and adding a nested-repository
regression produced the 59-contract passing rerun. Two subsequent fixtures cover
the canonical repository name and the exact pinned legacy feed after its rename,
bringing that snapshot to 61. Ten first-install recovery contracts and three
public-download contracts brought that snapshot to 74. Independent QA reran
all 74 contracts and 27 monitoring fixtures after temporary storage was routed
through the selected external build root; both exited 0.

The normal staged hook subsequently passed all 57 app, 62 core, 74 tooling and
27 monitoring tests for commit `1125158df09bf9dc6ab3f1e31465d6961d920938`.
Push Quality run `41370154800` passed. PR Quality run `41370175946` attempts 1
and 2 stalled before app entry in dyld and ran no test assertions. Attempt 3
used fresh internal scratch without changing source; its artifact `13109491830`
records both that source commit and merge revision
`a781f5dcea1cd4dcb9e598e83403f9d8e500b6ac` passing 57 app and 62 core tests each,
with result bundles and unchanged dependency hashes.

The subsequent cleanup correction adds three contracts for successful and failed
quality runs and `/tmp` fallback, including both default and supplied result
paths. Independent QA passed all 77 tooling contracts and 27 monitoring fixtures.
Scoped ShellCheck, Bash syntax and diff checks passed. These command fixtures
verify private workspace removal while retaining logs, partial result bundles,
hashes, caches, archives and unrelated temporary files. The normal staged hook
then passed 57 app, 62 core, 77 tooling and 27 monitoring tests for commit
`4b41fbb489bf38fd941e79dc4c730e9f6bc36a62`; independent QA verified the
retained evidence, unchanged pins and removal of external source/internal scratch.
Push Quality `41372558066` passed that commit. PR Quality `41372562579`
passed both introduced commits and merge snapshot
`801adb28c8724f621e29e345f069e83f3eb31eb9`, each with 57 app and 62 core
tests, result bundles and unchanged pins. Forced kills can bypass shell cleanup;
the CI runner manages its temp directory at job boundaries.

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
An additional unified-log error/fault query for the exact installed production
image requested the previous 90 days and returned no matching entries.
Available log retention may be shorter than that requested window. Its private
local evidence is
`/Volumes/xHome/Github/Glimpse/build/validation/local-production-history-90d.log`.

Product, UX and code reviews accept the bounded source contract with these limits.
Exact staged-tree quality checks and hosted CI are mandatory independent gates.
Release publication must additionally pass the signed, notarized, downloaded
artifact and public-feed checks. Hourly local monitoring records meaningful
availability/crash-report changes while leaving unchanged observations quiet.

The first modern main Release `41373019433` attempt 1 passed quality for merged
source `75b68685b2de1690cb4b78f71150d654ed17e359`, then failed at archive
signing before export or publication. Xcode selected a login-keychain development
identity instead of the imported Developer ID identity. Automatic Recovery
`41373225077` attempt 1 succeeded, verified the unchanged public v1.4.3
distribution and bound its proof to the exact failed source/run/attempt.
The live remediation gate passes; v1.4.4 is still unpublished.

Independent QA reviewed the signing follow-up under A4/A7/A8 and ran the full
91-contract suite and 27 monitoring fixtures successfully. The fourteen new
regressions exercise valid distribution-identity selection, ambiguity and team
failures, command timeout and sanitized errors, exact keychain paths with spaces,
consistent manual archive/export inputs, signing/verification failures stopping
archive, private probe cleanup, certificate mode 0600, original-keychain
restoration and certificate cleanup even when restoration fails. Bash syntax,
ShellCheck for all five changed workflow blocks, actionlint and diff checks
passed. These tests use fake signing commands; actual private-key access,
archive/export and notarization remain hosted release requirements.

The signing correction's real staged hook passed 57 app, 62 core, 91 tooling
and 27 monitoring tests for `ee60a1f1b1fa3e2be014f0be6a865a3adbe11fdb`.
Its push and PR Quality workflows passed the source and PR merge snapshot.
PR #6 merged as `b9017a70b1f09142755cd988af180884b4e3e321`.
Release `41374516171` attempt 1 then passed 57 app and 62 core tests,
the exact signing probe, Archive, Export and app notarization. It failed before
DMG notarization when create-dmg's cosmetic Finder AppleScript timed out.
Automatic Recovery `41374986732` attempt 1 passed and bound healthy v1.4.3
to the exact failed release/source. Public v1.4.4 remains unverified.

A real harmless DMG fixture using the supported `--skip-jenkins` option passed
packaging. Read-only mounting confirmed exact app content and a `/Applications`
shortcut; no Finder customization script ran, and the fixture was cleaned up.
This is independent packaging evidence, not notarization or public-release proof.

Independent A4/A7/A8 review passed 95 tooling contracts and 27 monitoring fixtures
for the archived-tooling correction. Its real Git archive/history regressions
verify all four component paths, rejection of intermediate failures before
builds, recorded SHA provenance and private cleanup with retained evidence.
The signing selector regression uses the real helper with a deliberately broken
intermediate implementation. Validator and monitoring cases include synthetic
fixtures; Xcode/Swift commands are stubbed. Actual staged-source and hosted
app/core checks remain required.

Five packaging regressions execute the workflow's extracted app-notarization and
DMG shell with fake packaging/notary tools. Four failed before the headless
option was added; all five then passed. They verify staged app content and the
Applications link, optional icon arguments, unchanged app/DMG notarization and
ticket validation, packaging failure before notarization, notarization failure
before stapling, exhausted stapling retries and failed ticket validation. These
command fixtures complement the real harmless packaging check; they do not
contact Apple's notarization service.
Independent final A4/A7/A8 QA passed all 100 tooling contracts and 27 monitoring
fixtures, scoped shell checks, actionlint and whitespace checks. It found no
code blocker. Exact staged app/core and hosted/public checks remain mandatory.
