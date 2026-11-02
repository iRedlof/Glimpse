# Shortcut recovery: independent code review

Date: 2026-11-01. Base: `e0096f0e381fed6a55b8a72b26eac76afbb9704b`
(`main`). Target metadata: version 1.4.6, build 13.

**Disposition: scoped code review accepted; no remaining source findings.**
The two P2 findings and one P3 finding were repaired and independently checked
against the final frozen files and 93-test app result. This acceptance covers
the reviewed source contracts. It does not establish product acceptance,
native acceptance, release readiness, or completion of the broader stability
goal.

The review follows every applicable A1–A8 section of
[the required checklist](../.claude/rules/pre-production-review.md), `CLAUDE.md`,
the related repository rules, [the design](superpowers/specs/2026-11-01-shortcut-recovery-design.md),
[the implementation plan](superpowers/plans/2026-11-01-shortcut-recovery.md), and
[HK1–HK10](shortcut-product-ux-acceptance.md). It includes the actual changed
application files, actual view-used model, added tests, project membership and
version metadata, plus unchanged integration call sites.

## Findings resolved in this iteration

1. **P2 — A6/A7/A8: requested intent now notifies the view.**
   `HotkeyPreferencesModel.swift:71` stores observable `isRequested`, initializes
   it from the existing saved/default intent at `84–85`, updates successful
   enable/record at `101`/`140`, and saves explicit off at `105–107`. The
   unchanged-cleanup-error case no longer depends on an incidental error
   change to redraw the **Keep shortcut off** action or next-launch text.
   `HotkeyPreferencesModelTests.swift:343–370` exercises the previously failing
   path. The independent exact-source consumer check now observes one
   notification for requested intent and one for all row values, while actual
   registration stays inactive and the same pending error remains.

2. **P2 — A3/A6/A8: recovery copy now reflects operation and usable state.**
   `GlobalHotkey.swift:79–94` and `HotkeyPreferencesModel.swift:52–56,75–77`
   distinguish reported collision, generic enable/replacement failure, failed
   disable with a usable key, and cleanup uncertainty. Prior-shortcut copy is
   conditional on actual usable registration. `GlobalHotkey.swift:214` now
   classifies failure retiring the old key as `replacementRetirementFailed`
   when candidate rollback succeeds, so it cannot inherit disable copy.
   Cleanup failure still takes precedence. Tests at
   `HotkeyPreferencesModelTests.swift:233–339` assert displayed messages,
   successful retry, and replacement failure during recording, after
   cancellation and on reopen. The independent consumer check also preserves
   the old callback, configured combination and one-time capture removal.
   Native adapter bytes and transaction policy are unchanged apart from this
   failure classification.

3. **P3 — A1.2/A3: the recorder now has a state-specific hint.**
   `PreferencesView.swift:394,431–437` gives recording instructions for a
   modifier and Escape/button cancellation, plus enabled/inactive action hints.
   The source requirement is satisfied. Actual VoiceOver output remains native
   QA.

## A1–A8 disposition

| Section | Scoped review result |
| --- | --- |
| A1 — Permissions and accessibility | No new permission request or TCC mutation path. Diagnostics still reads EventKit authorization status. New switch/recorder/opt-out names are explicit and the recorder has a state-specific hint. Existing calendar accessibility and actual VoiceOver/panel fit are outside this scoped result. |
| A2 — Panel and menu bar | The startup call now uses the shared observable coordinator. Panel positioning, renderer, midnight timer, pinning and activation policy are otherwise unchanged. Recorder cancellation is connected to disappearance and the existing panel-hide notification, which matters because reused panels do not reliably disappear in SwiftUI. Actual hide/reopen/About/focus behavior remains native QA. |
| A3 — Carbon and event handling | Candidate registration precedes retirement of the old key; accepted identity, callback and persistence advance only at the commit point. Same usable combo reuses native ownership. Status errors and missing handles fail; failed cleanup references are retained and retried. Old callback remains usable after failed unregister; successful key removal with failed handler removal reports inactive plus retained cleanup ownership/error. Callback context is owned by the process-lifetime shared coordinator/backend at the live call sites. Native parsing rejects missing/invalid parameters and foreign signatures before a main-actor hop; delivery rechecks accepted identity after that hop. Fake dispatch tests cover stale/foreign IDs, not real Carbon parsing/delivery. Recording acquires its monitor before publishing true, removes it idempotently, guards visible/key/owner input, and preserves the existing reserved subset. Contextual copy separates replacement retirement, disable and uncertain cleanup. Carbon options=0 is intentionally nonexclusive; no universal conflict guarantee is claimed. |
| A4 — Sparkle | No updater/feed/driver behavior changes. HTTPS feed and EdDSA public key remain present. Four app/test marketing versions and four builds are synchronized to 1.4.6/13; README badge matches. Publication, exact source, signing, notarization and feed verification remain separate gates. |
| A5 — AI | AI provider/security/fallback code is unchanged. Recording priority still suspends ordinary calendar local handling through the existing notification, without adding AI/network behavior. Native AI editing while recording and after cancellation remains open. |
| A6 — Preferences and EventKit | Saved request, accepted configuration and usable registration are separated. Startup failure preserves opt-in. First-enable failure does not introduce successful opt-in. Explicit disable cancels capture and saves observable off intent even when native teardown fails. Diagnostics receives a value-type Sendable snapshot with requested/registered/saved/active/error facts. No new secret storage. The unchanged-error request mutation and contextual messages are now exercised. |
| A7 — Code quality | Coordinator, model and native ownership operations are main-actor isolated. Failed resource cleanup retains retry ownership; callback closures use weak owner references. New code adds no delay workaround, force unwrap in production views, subprocess argument construction or source secret. Existing diagnostic collection code is unchanged apart from snapshot reporting. Source/hash and whitespace checks are recorded below. No remaining scoped finding. Sustained performance is untested. |
| A8 — Tests | Actual app tests cover coordinator failures, nil handles, rollback, retained cleanup, callback identity, same combo, recorder guards/cancellation/monitor failure, explicit opt-out, and diagnostic requested/actual output. Added regressions now assert Observation invalidation, displayed context, retry, and replacement-retirement copy through cancellation/reopen. Fake native operations and private defaults prevent added tests from using the live singleton. Existing test-host guard skips application startup. Native lifecycle/delivery assertions cannot be inferred from these tests. |

## Evidence inspected

External evidence directory:
`/Volumes/xHome/Github/Glimpse/build/validation/shortcut-regression.YvSxPH`.
The reviewer read the logs/receipts and extracted xcresult summaries
independently; the full suite was not unnecessarily rerun.

- `GlobalHotkey-RED-internal.xcresult`: actual coordinator baseline regression,
  12 tests, 11 failures; retained log reports 44 assertion issues.
- `model-red-harness.log` and `cleanup-red-harness.log`: baseline model and
  additional cleanup regressions, using the documented unused AppDelegate and
  notification boundary stubs. These are harness evidence, not native app QA.
- `Diagnostics-RED.xcresult`: actual diagnostic baseline, 9 tests, 2 failures
  for missing requested/actual output; 7 existing tests passed.
- `green-harness.log`: 27 tests in 2 suites passed before the additional
  explicit-opt-out characterization.
- `App-GREEN.xcresult` and `app-green.log`: historical unsigned app result,
  87 Swift Testing tests in 11 suites, zero failures. It predates the review
  fixes and is retained with the original receipt.
- `review-red-harness.log`: four displayed-copy consumer tests failed with
  nine issues against the initial frozen source. The initially passing
  Observation fixture in this run changed the error; it is not the Observation
  RED proof.
- `observation-red-harness.log`: corrected fixture first primes
  `cleanupFailed`, then repeats the identical failure during explicit off;
  one test, one issue, zero notifications instead of one.
- `replacement-red-harness.log`: one test, three issues for replacement
  retirement mislabeled as disable during recording, after cancel and on
  reopen. Baseline source manifests preserve the exact bytes for these runs.
- `App-Acceptance-GREEN.xcresult` and `app-acceptance-green.log`: final actual
  unsigned app result, 93 Swift Testing tests in 11 suites, zero failures,
  skips or expected failures, `TEST SUCCEEDED`. Parameterized executions
  explain the separate device-level count of 105. The reviewer extracted the
  summary directly and checked all 11 source/project/dependency hashes against
  the identical before/after manifests and final developer receipt.
- `independent-review-observation.log`: exact production coordinator/model
  interpreted through stdin with the actual fake backend and unused boundary
  stubs; exit 0. Requested=true→false, actual=false, unchanged cleanup error,
  zero requested/all-view-property Observation notifications, one retained
  pending candidate. This original failing observation result is preserved.
- `independent-review-final-consumers.log`: the same exact-source fake-only
  check now emits one requested-property and one all-row-property notification.
  Additional assertions pass for replacement copy during recording/cancel/
  reopen, old callback and configuration preservation, and one-time monitor
  removal. Exit 0; no native operation or standard-defaults mutation.
- `independent-code-final-review-receipt.json`: final hash and test-summary
  audit, plus byte comparison confirming unchanged Carbon/snapshot adapter,
  recorder adapter, and coordinator policy apart from the typed replacement
  failure classification.
- `git diff --check` and project `plutil -lint`: clean. Both dependency-lock
  files are byte-identical to the base commit.

## Reviewed SHA-256

These hashes identify the final source for this review and the 93-test result.
Any further application/test/project change needs appropriate checks and review.

| File | SHA-256 |
| --- | --- |
| `Glimpse/GlobalHotkey.swift` | `b26f49972ebc44a6bf8cba049d0026d126afbe8f010f67293f14c6e2284ca6c0` |
| `Glimpse/HotkeyPreferencesModel.swift` | `10de8ec31126d3808ee5d3c0042161cd319a9a0d274e8edcbb25a78b38190856` |
| `Glimpse/PreferencesView.swift` | `5d1a4cf57b94ef87387beb91ceb83b2c5003bf58600268cb1e05f63105ef254f` |
| `Glimpse/CalendarStatusItem.swift` | `039110e26e4b0c9f8e3b6a4cfc82b5a1ae98f9fa60a4dba20666c1ba19976b13` |
| `Glimpse/DiagnosticsExport.swift` | `75e7ec8b64f99e1a96f499373ac13c1872e198f7b2648c4422f0d360e51fba11` |
| `GlimpseTests/GlobalHotkeyTests.swift` | `0bbb8c725ff7ed7dd500c93d7fbc4ba071bc819112a865c78e63d256033dfd46` |
| `GlimpseTests/HotkeyPreferencesModelTests.swift` | `b78694350becd906a8a793d02be8672bec06282789c30ca78fe18ddd9b6fc74a` |
| `GlimpseTests/DiagnosticsExportTests.swift` | `b19bf1b6ed53ffecdb48e62858c0399f810287077b70336d1bc12d178495e75d` |
| `Glimpse.xcodeproj/project.pbxproj` | `0c64b41e5123090c5a99500c4d90990cb1b52f614936f9909dfe22618e7267c8` |
| `README.md` | `2ec43a04c46b0205c99305275c6c8d4bb23f82530c8d315085db426ef375476a` |
| `GlimpseCore/Package.resolved` | `ffeaf49b65ce3dd7b6a95db730357b03546883dc7fd20ba8e05cdb9aed529e6d` |
| `Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | `5a5b283530b0e02190ce66eb50ac5817f037e0d2ac7ab99af10cdc6e931e54b7` |

## Remaining gates and native limits

An accepted native-ID event can still invoke the normal panel toggle while the
recorder is active; the recording notification gates calendar local monitors.
The design retains the prior usable shortcut and allows panel hide to cancel
capture. Source/fake dispatch does not establish Carbon/keyDown ordering or
failure of native same-combo recording. Verify that interaction on an
authorized signed build without treating another app's shortcut alone as a
guaranteed collision.

Native delivery/retirement, conflict rejection when reproducible, recorder
monitor lifetime, panel/About/AI interaction, VoiceOver, wrapped copy and
small/scaled-display fit remain open. So do the unexplained other-machine
crash, installed startup/login/reboot, sleep/wake, multi-display/date rollover,
Powerbox diagnostics, endurance and sustained performance.

The normal staged hook, checks for each introduced revision and merge source,
independent scoped acceptance, protected integration, and exact signed/public
artifact checks remain required. This review does not change readiness or
authorize installation, restart, registration probes, release or publication.
