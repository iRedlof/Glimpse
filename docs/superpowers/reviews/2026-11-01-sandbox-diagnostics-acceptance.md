# Sandbox-compatible diagnostics: scoped prepublication acceptance

Target: **1.4.8 / build 15**. Base:
`0f3614ca67d6f085af0aac616c7e9a82c202f10b`.

Product, UX, code and independent QA have passed for the frozen source
implementation under the
[binding design](../specs/2026-11-01-sandbox-diagnostics-design.md).
The four passed checks in `.github/release-readiness.json` refer to this
scoped prepublication acceptance. Normal whole-revision quality, protected
delivery, exact-main Release/Recovery verification and the signed installed
v1.4.8 About > Export flow remain required. This document does not close
the wider stability goal.

## Confirmed regression and accepted behavior

The real installed, signed v1.4.7/build 14 saved its metadata report, but
the production `/usr/bin/log` subprocess returned exit 64 with
`log: Cannot run while sandboxed`. The app's sandbox entitlement is enabled.
The retained app-generated report is
`/Volumes/xHome/Github/Glimpse/build/validation/native-live-v147.fcfannzu/Glimpse-Diagnostics-v147.txt`,
SHA-256 `dbe77034fbcf286eedd589a38d35694c6c8d12a95d2d06ae9d68b39b37fa7bbc`.

The new production default uses one shared collector and
`OSLogStore(scope: .currentProcessIdentifier)`. Store creation, lazy
enumerator creation/advancement, filtering and formatting stay within one
utility DispatchQueue worker and autorelease pool. The iterator retains
the store for its lifetime. Native non-log entries become rejected
candidates, so they consume the scan budget. No store or enumerator crosses
an actor boundary; only Sendable entry/report values cross the seam.
No subprocess launch, `/usr/bin/log`, child signal, temporary log file or
subprocess exit-status API remains in the diagnostics source/tests.

The report identifies the current launch, exact current PID, subsystem
`com.rohit.Glimpse` and five-minute window. The default deadline is ten
seconds; accepted custom deadlines are finite values in `(0, 60]` seconds.
Output defaults to and cannot exceed 1,048,576 UTF-8 bytes; positive smaller
limits are allowed. The collector scans at most 10,000 candidates without
lookahead. Reaching either cap reports possible incompleteness even when
no further entry is known. Truncation preserves valid UTF-8, and messages
use the SDK's `composedMessage` without replacing privacy placeholders.

Deadline and cancellation delivery are independent of the synchronous
native worker. A request arbitrates one continuation delivery using short
lock sections. No provider call, iteration, formatting, timer cancellation
or continuation resume occurs under the state locks. The worker releases
only its own reservation after its native/sequence scope actually ends.
Late completion cannot deliver twice or release another request's slot.
Native synchronous calls have no interruption API: a timed-out or canceled
read may continue, and the one active reservation remains occupied until
it exits. A subsequent export starts no second read and saves metadata
with a collection-in-progress explanation.

The existing selected-destination flow and injected
`DiagnosticsExport.export(to:hotkey:collect:)` interface are preserved.
Empty completed reads, SDK failures and deadlines still save useful
metadata; destination write errors remain caller-visible. The report
distinguishes empty retained results, partial excerpts, timeout and busy
collection. Optional result limit metadata describes actual supplied
bounds without inventing limits for arbitrary injected results. The About
flow still offers progress, Show in Finder, Export again and write-error
Retry. Reading the existing calendar authorization status requests no
new permission.

## Independent acceptance

Three independent roles accepted the exact frozen implementation:

| Role | Verdict and scope |
| --- | --- |
| Fresh spec/code reviewer | Approved with no critical or important findings. Verified SDK wiring, worker ownership, deadline/cancellation arbitration, scope and bounds, source identities and retained RED/GREEN evidence. One minor evidence-noise note was recorded and clarified. |
| Product/UX reviewer | Product PASS and UX PASS for the actual source, report wording, partial results, selected destination, preserved About flow and permission behavior. Signed installed-app export remains open. |
| Independent QA reviewer | PASS for scoped prepublication evidence; 51 passing acceptance checks. Fresh reads of the actual xcresult bundles matched retained summaries/test trees, source snapshots, manifests and pins. No tests or helper probes were rerun by that reviewer. |

The assigned review records and implementation ledger are retained at
`/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-sandbox-delivery.lvw2e_sj`
as `task-1-review.md`, `product-ux-acceptance.md`,
`independent-qa-acceptance.md` and `task-1-report.md`. Their original authoring
location was the ignored workspace
`.superpowers/sdd/2026-11-01-sandbox-diagnostics/`; the external copies retain
the evidence through later workspace cleanup. This durable acceptance
records their conclusions and limits for release readiness.

## Regression and independent QA evidence

Actual focused results, logs, exact source snapshots and hash manifests
are retained privately at
`/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-task1.u_vwvzlz`.

| Attempt | Recorded result |
| --- | --- |
| Initial RED compilation | Exit 65; build failed, no behavioral test run. |
| Behavioral RED against a deliberately empty compilable seam | Exit 65; build succeeded; 17 distinct tests, 12 failed and 5 passed, with 28 expectation failures. |
| Initial GREEN compilation | Exit 65; build failed, no passing-test claim. |
| Final focused GREEN | Exit 0; build succeeded; 17 passed, 0 failed, 0 skipped; Swift Testing suite duration 0.252 seconds. |

All twelve new regressions failed behavioral RED and passed final GREEN:
valid current-process entries, foreign PID/subsystem and old-date exclusion,
empty retention, Unicode byte boundary, exact candidate cap, blocked provider
and blocked iterator deadline delivery, retained ownership after timeout,
cancellation before/during a read, provider failure/reuse and invalid bounds.
The five preserved metadata, selected-destination, write-error and hotkey
snapshot tests passed both. Blocked fixtures remain active when the waiter
returns; deferred release and subsequent successful collection establish
eventual reuse and safe late completion. These tests use injected entries
and independently owned collectors. They establish collector behavior,
not native retained-message retrieval or a measured native ten-second
upper bound. Final tests add fixture watchdog and timeout-report assertions
after the original behavioral RED; the final exact test source is separately
snapshotted.

Independent QA freshly read summary/test trees from the actual
`red-behavior.xcresult` and `green-final.xcresult`, and build results from
all four attempts; all eight reads exited 0. Those reads exactly matched
the retained evidence. The QA receipts and 51-check ledger remain at
`/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-task1-independent-qa.ozc2cc1a`.
Source snapshots and manifests establish consistent provenance; they
are not a cryptographic compiler attestation of every input.

Final GREEN records zero build errors, compiler/analyzer warnings and
xcresult runtime warnings. Its raw log still has the multiple matching
macOS destination warning, `com.apple.linkd.autoShortcut` connection and
intents/Process Instance Registry re-registration errors, separate XPC
invalidation messages and expected injected-failure logging. The host/service
noise was not causally diagnosed; no collector defect is established by it.
Zero xcresult runtime warnings does not mean a diagnostic-free raw log.

## Platform evidence and remaining limits

The independent sandbox diagnosis receipt remains at
`/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-sandbox-independent-qa._6yd2150/diagnostics-sandbox-diagnosis-receipt.json`,
SHA-256 `9400a086c4a31efa40a1ea6c92086c8661b000d005b4c82cb992581af7075651`.
An owned ad-hoc signed helper with only the sandbox entitlement reproduced
the CLI refusal. Strict signature verification and an outside-write EPERM,
with a successful unsandboxed control, established actual sandbox activation.
Current-process SDK initialization, `getEntries` and iteration succeeded
on the tested macOS 27.0.1 host.

All helper SDK reads and bounded external controls for its own PID/subsystem
returned zero entries, including while the helper was alive. Four relevant
logging environment keys were unset. These observations prove sandbox SDK
API access, but do not prove useful retained messages, native privacy
redaction or a logging-disabled environment. Supplied fixture `<private>`
preservation is not native redaction evidence. The compiled production
default was inspected, while focused tests exercised injected providers.
macOS 14 runtime behavior has not been separately exercised.

After verified publication, the authorized verified update must be installed
and restarted, preserving preferences and backup, then the real
About > Export flow must save a report to the user's selected destination.
Acceptance must record actual v1.4.8/build 15 metadata, current-process scope,
observed responsiveness, and absence of `Cannot run while sandboxed` and
subprocess exit status. Empty retention or native errors must be recorded
exactly. This gate is still open; neither a fixture save nor helper API
access substitutes for the signed installed-app export.

This scope excludes earlier launches/crash history, useful native retention
guarantees, a guarantee that native calls cannot hang, and crash-free
operation. Reboot/login reliability, sustained endurance, real EventKit
latency and the other-Mac crash remain separate work. The reported human
confirmation that v1.4.7's global shortcut opens the calendar is a separate
observation, not diagnostics or reboot acceptance. New permission grants,
logout and reboot are outside the installation authorization.

## Identity, compatibility and cleanup

| Frozen file | Accepted SHA-256 |
| --- | --- |
| `Glimpse/DiagnosticsExport.swift` | `cd8f00f1c4e964176531b61cd75ccd8b6583eb9f34639ac51a8f8b8abf894344` |
| `GlimpseTests/DiagnosticsExportTests.swift` | `628217731892b262b734ab9e2ff795a2db8fb17be9665111ea75987d787fe257` |
| `GlimpseCore/Package.resolved` | `ffeaf49b65ce3dd7b6a95db730357b03546883dc7fd20ba8e05cdb9aed529e6d` |
| App `Package.resolved` | `5a5b283530b0e02190ce66eb50ac5817f037e0d2ac7ab99af10cdc6e931e54b7` |

Both lockfiles and all 15 pins remain byte-identical to base. Deployment
floor 14.0, Swift 6 and complete strict concurrency are preserved.
Entitlements, team `5D7M37QQLU`, signing policy and Sparkle public key are
unchanged. Project edits are limited to four marketing versions and four
build numbers; the README edit is limited to its version badge. No startup,
hotkey, EventKit, panel, AI or unrelated UI implementation is changed.

Developer-owned inactive DerivedData/tmp were removed after retained
empty open-file/process audits; all four actual xcresults, logs, snapshots
and manifests remain. No process was stopped. Helper compiler scratch
was removed, but its uniquely owned macOS-managed container remains:
ordinary deletion of `.com.apple.containermanagerd.metadata.plist` was
denied. No protections, TCC settings or permissions were changed to remove
it. This known cleanup limit is unrelated to the production app container.

Only prepublication metadata and evidence are accepted here. Controller
staging, fresh whole-branch review, normal commit/push hooks, protected
merge, exact-main Release/Recovery verification, public/native artifact
verification and installed-app re-export remain later gates.
