# Isolated Glimpse live QA — 2026-11-01

## Tested binary and isolation

The parent signaled build readiness after the complete app suite passed **54 tests in 9 suites**, exit `0`, in `/tmp/glimpse-app-green.log`.

The copied product was `/Volumes/xHome/Github/Glimpse/build/validation/app-build/Build/Products/Debug/Glimpse.app`, version **1.4.3 / build 10**. Its source executable SHA-256 before QA re-signing:

```text
177c9ea9fa04fb43cb43ca40169db216679c0db313a31187200e152a4e640c88
```

The isolated copy is `/tmp/glimpse-qa/live/Glimpse QA.app`, with bundle identifier `com.rohit.Glimpse.QA`, a separate preferences domain, and automatic update checks disabled in its copied plist and launch arguments. At this stage `/tmp/glimpse-qa` resolves to `/Volumes/xHome/Github/Glimpse/build/validation/qa`; artifacts are in the ignored build tree.

The copy and its embedded frameworks were signed ad hoc; `codesign --verify --deep --strict` passed. This debug copy has **no entitlement payload** and does not validate the distributed app's sandbox or hardened runtime behavior.

Initial launch disabled the global hotkey. A later, explicitly authorized QA-only relaunch enabled `Cmd+Shift+Option+Control+9` using temporary arguments: `-hotkeyEnabled YES -hotkeyKeyCode 25 -hotkeyModifiers 6912`. The installed application's shortcut was never invoked or changed.

Source bookkeeping later changed to version 1.4.4/build 11. The product copy tested here retained 1.4.3/build 10. The subsequent About-window change retaining “Show in Finder” alongside “Export Again” was not in this copy and was not validated natively.

## Actual runtime observations

| Check | Actual result |
| --- | --- |
| Initial isolated startup | QA PID `17507` started and remained alive; accessory activation policy, not hidden. |
| Menu extra | Enabled `AXMenuExtra`, position `(1741, 3)`, size `102 × 24`, within the active right display `(0, 0, 2560, 1440)`. |
| Idle measurement | **13 samples spanning 60.47 seconds** with the panel closed; sampled `ps` CPU median and maximum both **0.0%**. |
| Cumulative CPU | `0:00.26` at both ends of the measurement window. This is unchanged at `ps` reporting precision, not proof of exactly zero CPU use. |
| Resident memory | **20.45–22.02 MiB** during that window. These are resident snapshots, not total or peak memory. |
| Temporary QA hotkey | Relaunched as PID `20955`. QA preferences contain key code `25` and modifiers `6912`; the implementation saves these only after successful Carbon registration. |
| Hotkey-triggered opening | CUA's bound Finder key command did not produce a QA window. The remaining menu extra was enabled; no application crash was inferred. |
| Cleanup | QA PID `20955` terminated after its exact development executable was verified; its temporary hotkey registration ended with the process. |
| Installed app preservation | Installed PID **2805** remained `/Applications/Glimpse.app/Contents/MacOS/Glimpse`, approximately **33 days 8 hours** uptime. No installed preferences, TCC access, login registration, or executable were changed. |
| Finder restoration | Its original `config` window and focused outline/list view were verified after the fallback attempts; no file operation was performed. |

Raw scoped runtime evidence:

- `/tmp/glimpse-qa/live-runtime-initial.txt`
- `/tmp/glimpse-qa/live-runtime-after-cua.txt`
- `/tmp/glimpse-qa/live-runtime-after-hotkey.txt`
- `/tmp/glimpse-qa/live-idle-samples.json`

The closed-app idle observation showed no sustained CPU loop during the measured minute. It is too short and too limited to establish long-term availability, memory-leak absence, open-panel performance, or restart reliability.

## Native interaction limitation

CUA `getApp` timed out with `-10005: timeoutReached` when selecting the isolated accessory application by bundle identifier, path, and display name. Its read-only accessibility tree remained available through a scoped runtime query, but it had no windows.

Two explicit fallback approaches were attempted:

1. A Finder binding succeeded. Its screenshot was cropped to its own window, with no menu bar. A CUA coordinate click using the independently observed QA menu-extra center did not create a QA window; selecting the QA app still timed out.
2. The QA copy was relaunched with the unique temporary shortcut above. CUA sent `super+shift+alt+ctrl+9` through the Finder binding, followed by fresh state reads. No QA window appeared, and QA app selection still timed out.

These outcomes limit this automation path. They do not establish a product menu-item or hotkey defect. No AppleScript, synthetic CGEvent, or direct accessibility press was substituted for CUA actions.

## Conditional native acceptance matrix

The code reviewer identified these as the highest-priority native checks. They remain **unperformed**, rather than passed:

| Scenario | Required observation before native acceptance |
| --- | --- |
| Reused panel lifecycle | At least 20 open/hide/reopen cycles; preferences collapse; today resets; one action per navigation key; no monitor multiplication. |
| AI text input | Left/right moves the caret without month navigation; Return submits once; Escape clears AI, then preferences, then closes the panel. |
| Hide during AI work | A late result cannot change the reopened today's selection. Use a safe test query with no confidential content. |
| Pinned panel + About | About receives its own keys while the calendar is pinned; hidden-panel navigation does not intercept them. |
| Preferences/hotkey recording | Calendar navigation stays suspended while editing; Escape and hide cancel recording; use a QA-only shortcut. |
| Today in the same month | After selecting another day in the current month, Today remains enabled and restores actual today and the events-date heading. |
| Calendar access/loading/error UI | No access request without the explicit events action; permission, loading, denied/restricted, retry and stale-result states accurately reflect reality. Do not alter the installed app's TCC grants. |
| Diagnostics UI | Export completes or presents a bounded failure; startup/version appear; retry works; success exposes the saved file and allows another export. The distributed sandbox configuration must be tested separately. |
| Static open-panel performance | CPU returns to idle after resize/preferences changes; measure a minute with the panel open and repeated cycles. |
| Login/restart/display/wake | Signed installed app on a disposable test account or later authorized session; record actual startup/visibility after repeated logins, display changes and sleep/wake. |

The automated 54-test app result exercises diagnostics collector output/deadline/failure paths and the pure keyboard-routing contract. These support the bounded changes but cannot substitute for the native matrix above. Reducer and dependency test evidence is tracked by the parent task.

QA supports proceeding with the tested code and clearly stated limitations. Broad native interaction, restart, distributed sandbox, and unattended availability acceptance remain open; neither the other-machine crash nor those release gates should be described as resolved by this run.
