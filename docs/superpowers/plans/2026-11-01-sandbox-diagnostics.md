# Sandbox-compatible Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Fix the confirmed sandbox error while keeping diagnostics responsive, bounded and useful on failure.

**Architecture:** Read current-process logs through OSLogStore in a single background worker. Independently bound the report's wait and keep ownership until any native call actually finishes. Write the existing metadata report to the selected destination.

**Tech Stack:** Swift 6, Foundation, OSLog, AppKit, Swift Testing; existing Xcode and release tooling.

**Spec:** `docs/superpowers/specs/2026-11-01-sandbox-diagnostics-design.md`

## Global Constraints

- macOS deployment floor `14.0`; Swift language mode `6`, complete strict concurrency.
- Default deadline `10` seconds; finite timeout range `(0, 60]`.
- Default and absolute maximum output `1_048_576` UTF-8 bytes; positive custom limits no greater than this maximum.
- Scan at most `10_000` candidates; exact current PID, subsystem `com.rohit.Glimpse`, five-minute cutoff.
- One unfinished native read per process, including after timeout/cancellation; no locks around native work.
- No dependencies or entitlement changes. Existing team `5D7M37QQLU`, signing policy and Sparkle key remain unchanged.
- Preserve all 15 pins and both lockfiles byte-for-byte: core SHA-256 `ffeaf49b65ce3dd7b6a95db730357b03546883dc7fd20ba8e05cdb9aed529e6d`; app SHA-256 `5a5b283530b0e02190ce66eb50ac5817f037e0d2ac7ab99af10cdc6e931e54b7`.
- Changes stay in diagnostics source/tests and necessary release evidence/metadata. Do not modify startup registration, hotkeys, EventKit, panel layout, or unrelated UI.
- Target release `1.4.8`, build `15`, after source, product/UX and QA acceptance.
- Controller-only accepted commit; normal hooks, protected delivery and exact-main publication verification remain mandatory.

## Review Focus

1. A native call never returns: export deadline still delivers metadata; another export starts no second native worker.
2. Timeout/cancellation races with completion: each waiter receives exactly one result; ownership stays with its own worker until actual exit.
3. Multibyte Unicode at the byte boundary or many rejected entries: valid UTF-8 and both byte/scan limits remain enforced.
4. Foreign PID/subsystem or old entries: no unrelated/historical process data enters the report.
5. Empty retention or SDK failure: report remains truthful and useful; a successful save does not imply useful messages were retained.

---

### Task 1: Replace the collector and verify bounded ownership

**Files:**
- Modify: `Glimpse/DiagnosticsExport.swift`
- Test: `GlimpseTests/DiagnosticsExportTests.swift`

**Interfaces:**
- Keep `DiagnosticsExport.export(to:hotkey:collect:)` and its Sendable injected `LogResult`.
- Produce nested `DiagnosticsExport.LogEntry: Sendable` with `date: Date`, `processIdentifier: Int32`, and `subsystem`, `category`, `level`, `message: String`.
- Produce independently instantiable `DiagnosticsExport.LogCollector` with `collect(timeout: TimeInterval, outputLimit: Int, read: @escaping @Sendable () throws -> AnySequence<LogEntry>) async throws -> LogResult`.
- Produce `DiagnosticsExport.CollectionError: Error, Equatable, Sendable` cases `invalidLimits` and `alreadyCollecting`.
- Production `collectLogs(timeout:outputLimit:)` uses the shared collector and current-process OSLogStore provider; no subprocess API remains.
- Return only Sendable report values across concurrency boundaries. `LogResult` keeps output/timeout/truncation and removes subprocess-only exit status.

- [x] **Step 1: Add meaningful failing regressions.** Preserve existing metadata, destination error and hotkey snapshot assertions. Replace process fixture cases with controlled entry/blocked-provider cases; use an injected collector instance per test. Cover all five Review Focus conditions plus invalid limits, cancellation before start/during a read, eventual ownership release, and provider throws.

| Regression name | Observable assertions |
| --- | --- |
| `currentProcessEntriesAppearInReport` | A valid current-PID/subsystem/recent fixture message appears; SDK privacy placeholder remains unchanged. |
| `unrelatedAndOldEntriesAreExcluded` | Foreign PID, foreign subsystem and an entry older than five minutes do not appear; a valid entry still appears. |
| `emptyEntriesProduceValidEmptyResult` | Empty output, no timeout, no truncation; report identifies current-launch scope and empty retention. |
| `unicodeByteBoundaryRemainsValid` | UTF-8 output is within a small requested byte cap, contains no replacement character, and reports truncation. |
| `candidateScanIsBounded` | A lazy provider with more than 10,000 candidates consumes at most 10,000, without lookahead, and reports the limit reached. |
| `blockedProviderDoesNotBlockDeadline` | A started provider remains blocked when collect returns `timedOut=true`; test's deferred release always unblocks it. |
| `timedOutWorkerRetainsExclusiveOwnership` | A second collection throws `.alreadyCollecting`, with provider-start counter still one; after actual worker exit a new read succeeds. |
| `blockedIteratorDoesNotBlockDeadline` | Iterator `next()` remains blocked when deadline delivery returns; later completion is ignored safely. |
| `cancellationBeforeStartDoesNotRead` | Pre-canceled task throws `CancellationError`, provider-start count zero. |
| `cancellationDuringReadRetainsOwnership` | Canceled waiter receives `CancellationError`; blocked worker still owns the slot, no duplicate read starts, and eventual release allows reuse. |
| `providerFailureReleasesOwnership` | Injected provider error reaches caller; metadata export still works; subsequent collection succeeds. |
| `invalidLimitsDoNotStartReader` | Zero/negative/nonfinite/>60 timeout and zero/negative/>1MiB byte limits throw `.invalidLimits`, provider-start count zero. |

- [x] **Step 2: Record RED.** Use only the minimal compilable seam necessary to observe behavioral failures. The installed production report with sandbox error is the platform baseline RED; preserve it. Record named failures and exit status privately, including the exact tested source identity.
- [x] **Step 3: Implement the current-process provider and collector.** Read the spec first. Create/consume the OSLogStore and lazy enumerator inside the worker, use independent deadline/cancellation delivery, keep one native read active until actual exit, and enforce scope/output/scan bounds. Remove the obsolete Process/temp-file/child-signal collector. Update report scope and limit wording.
- [x] **Step 4: Run focused GREEN and inspect results.** Allocate uniquely owned external paths into `DIAGNOSTICS_DERIVED` and `DIAGNOSTICS_RESULTS`, with a separate private temporary directory and log files. Resolve once with `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -derivedDataPath "$DIAGNOSTICS_DERIVED" -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation`. Run `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -destination 'platform=macOS' -derivedDataPath "$DIAGNOSTICS_DERIVED" -skipMacroValidation -disableAutomaticPackageResolution -only-testing:GlimpseTests/DiagnosticsExportTests -resultBundlePath "$DIAGNOSTICS_RESULTS" CODE_SIGNING_ALLOWED=NO test`. Redirect output privately; confirm named failures/passes, actual xcresults and unchanged pins. Do not weaken the repository's settings.
- [x] **Step 5: Freeze source and return report.** No worker commit/push. Report changed files, exact commands, RED/GREEN counts, source/lock hashes, native-call limitations and safe owned-scratch cleanup. Controller dispatches fresh spec/code review before accepting.

### Task 2: Accept and deliver the scoped fix

**Files:**
- Create: `docs/superpowers/reviews/2026-11-01-sandbox-diagnostics-acceptance.md`
- Modify: `.github/release-readiness.json`
- Modify: `Glimpse.xcodeproj/project.pbxproj` version/build occurrences only
- Modify: `README.md` version badge only

**Interfaces:**
- Consumes the frozen Task 1 source/tests, fresh independent review, sandbox diagnosis and product/UX acceptance.
- Produces one accepted controller commit, protected PR/main release, public/native artifact receipts and real installed-app re-export evidence.

- [ ] **Step 1: Independently inspect the frozen collector and acceptance.** Confirm current-process SDK wiring, no subprocess, real background ownership and deadline/cancellation behavior. Verify source evidence and sandbox probe limitations; do not relabel fixtures as platform retrieval proof.
- [ ] **Step 2: Synchronize metadata.** Set all existing marketing/build occurrences to `1.4.8` / `15`, update badge, and bind all four scoped readiness phases to the acceptance document after they pass. Keep wider stability/reboot acceptance open.
- [ ] **Step 3: Stage only approved paths and request a fresh whole-branch review.** Resolve actionable findings through the implementer and scoped review. No coauthor trailers or external discussion messages.
- [ ] **Step 4: Run the actual normal commit/push hooks.** Preserve retained exact-revision test results, actual xcresults, source/pin identity and cleanup. Create and attach the PR; independently verify every push/head/synthetic merge quality artifact and strict protected status.
- [ ] **Step 5: Merge ordinarily and verify the whole exact-main release.** Validate approved tree and parent, signed source, notarization, trust, Sparkle signatures, public tagged/latest bytes and manifest identity. Reopen the next admission gate only after whole Release/Recovery success and native/public artifact checks.
- [ ] **Step 6: Use existing installation authorization.** Preserve preferences/backup and install only the newest verified release, restarting the app. Perform the real About > Export flow, record current-process scope and metadata, and confirm the sandbox subprocess error is absent. Keep permission grants/logout/reboot outside this authorization.
- [ ] **Step 7: Close this scoped plan with durable evidence.** Preserve the managed heartbeat worktree and wider goal. Record unresolved platform retention/endurance/other-device limits and remove only this plan's own scratch after retaining its ledger/reviews.
