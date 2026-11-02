# Shortcut recovery: scoped QA acceptance

Independent QA accepted the final **1.4.6 / build 13** source and injected
contracts against base `e0096f0e381fed6a55b8a72b26eac76afbb9704b`.
The production Carbon adapter also passed a bounded process-local ABI check.
No actionable blocker remains within this scope. This does not certify
desktop shortcut delivery, native preferences interaction or broader reliability.

## Final evidence and fidelity

The retained actual app result, `App-Acceptance-GREEN.xcresult`, independently
reports **93 passed tests in 11 suites**, 105 parameterized executions, zero
failures, skips, expected failures or runtime warnings. Its log contains
`TEST SUCCEEDED`. All 11 before/after source, project and pin hashes are
identical and match the final frozen files. QA inspected this result without
duplicating the whole app run.

Independent focused verification passed **37 tests in three suites**:
34 production coordinator/model tests and three supplementary boundary tests.
Production source and tests were copied byte-for-byte to a private CLI harness.
Native operations and recorder monitors were fake-backed; preferences used
disposable private suites. The only supporting stubs are unused AppDelegate
and notification declarations. Supplementary tests cover rejected-candidate
dispatch while cleanup fails, re-enabling after handler-removal failure, and
cancellation preserving startup retry intent and cleanup error.

The retained RED evidence reproduces the defects: actual registrar 12 tests,
11 failures and 44 assertion issues; model harness 12 tests/26 issues; cleanup
harness three tests/12 issues; actual diagnostics nine tests/two failures/nine
issues. Subsequent copy regressions have four failing functions/nine issues;
the corrected intent-only Observation regression has one failure/one issue;
replacement-retirement wording has one failure/three issues. These use
behavior-retained injected seams to induce failures, not real desktop conflicts.
Earlier 87/92-test app and 36-test independent results remain historical
snapshots and are superseded by the final results above.

## HK1–HK10 disposition

| ID | Verified source/injected-contract boundary |
| --- | --- |
| HK1 | Replacement registers the candidate before retiring the old key and commits saved/displayed state afterward; accepted callback delivery is tested. |
| HK2 | Rejection retains the exact old key, handler, callback and saved/displayed combination; recording stays active. Failed candidate rollback retains ownership and suppresses candidate dispatch. |
| HK3 | Same usable combination performs no duplicate native registration or unregistration. Inactive enable/re-enable attempts registration. |
| HK4 | Initial/native-handle/handler failure reports inactive, preserves configured preferences and exposes recovery error/action state. |
| HK5 | Startup failure retains requested intent; reconstructed preferences models expose actual inactive state. “Keep shortcut off” is wired only for inactive/requested=true and updates observed intent even when cleanup repeats the same error. |
| HK6 | Cancel/Escape are idempotent; source routes recorder click, panel hide and view disappearance through cancellation. Private monitor traces prove one removal/inactive notification; native monitor delivery remains untested. |
| HK7 | Disable cancels capture and saves off intent before teardown. Failed key removal retains usable active state/error; successful key removal with failed handler cleanup reports inactive and retains cleanup ownership for retry. |
| HK8 | Inactive recording changes intent only on acceptance. Rejection/cancellation preserve configuration and applicable error; opt-out covers normal and pending-cleanup paths. Nil monitor acquisition cannot leave recording active. |
| HK9 | Status and handle failures cannot publish usable registration. Pending resources block new transactions until cleanup succeeds; stale/foreign/rejected IDs cannot invoke the accepted callback. |
| HK10 | Diagnostics distinguish requested, registered, saved and active state/error. Options=0 remains nonexclusive; source and acceptance make no comprehensive cross-app conflict-detection claim. |

The custom switch binding uses actual registration. Contextual copy distinguishes
failed replacement, failed disable and uncertain cleanup; consumer tests assert
the text during recording, cancellation and reconstructed preferences state.
Accessible names/value/hints and recovery visibility are source-reviewed.
Actual VoiceOver, wrapping, focus, panel fit and click behavior remain untested.

## Native process-local ABI boundary

An immutable copy of the complete final `GlobalHotkey.swift` and actual
`AppLogger.swift` compiled with a standalone probe. The entry point only calls
`CarbonHotkeyBackend.installHandler/removeHandler` and Carbon EventRef APIs
against its own application event target. It never instantiates the coordinator,
accesses its shared registrar/defaults, calls register/unregister, creates a
local monitor, activates NSApp or injects desktop keys.

The 0.488-second run passed: install/remove returned `noErr`; matching IDs were
decoded; foreign signature and missing parameter returned `eventNotHandledErr`
without callbacks; queued delivery after removal and subsequent delivery were
suppressed. All six local EventRefs were released and the owned handler was
removed. Valid-signature foreign IDs are forwarded by the adapter; accepted
generation filtering is established separately by coordinator fixtures.
No global shortcut was acquired. The exact private internal executable/build
scratch `/tmp/glimpse-shortcut-qa.cp5_hj2a` has been removed.

## Retained identity and remaining gates

Private receipt (mode 0600), source hashes, probe source and logs:
`/Volumes/xHome/Github/Glimpse/build/validation/shortcut-independent-qa.x52oj3w0/qa-receipt.json`.
Actual app and RED receipts:
`/Volumes/xHome/Github/Glimpse/build/validation/shortcut-regression.YvSxPH/developer-final-receipt.json`.

Final production hashes include:

- `GlobalHotkey.swift`: `b26f49972ebc44a6bf8cba049d0026d126afbe8f010f67293f14c6e2284ca6c0`
- `HotkeyPreferencesModel.swift`: `10de8ec31126d3808ee5d3c0042161cd319a9a0d274e8edcbb25a78b38190856`
- `GlobalHotkeyTests.swift`: `0bbb8c725ff7ed7dd500c93d7fbc4ba071bc819112a865c78e63d256033dfd46`
- `HotkeyPreferencesModelTests.swift`: `b78694350becd906a8a793d02be8672bec06282789c30ca78fe18ddd9b6fc74a`

No app was installed, launched or replaced by independent QA; no installed
preferences, permissions, login settings or global native shortcuts changed.
Real desktop key delivery/conflicts, native recorder/focus/monitor cycles,
startup/login/reboot, sleep/wake, multi-display, rollover, Powerbox, endurance
and the other Mac’s crash cause remain open. Normal exact staged-source and
hosted commit/merge checks, followed by signed public 1.4.6 verification, remain
separate mandatory gates. Historical public 1.4.5 acceptance is unchanged.
