# Event Query Cancellation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skip obsolete queued EventKit queries and discard canceled active results.

**Architecture:** Preserve the serial `EventStore` actor and its native SDK ownership. Check cancellation before its work and after its synchronous query; use an internal authorization provider to test cancellation without querying real calendars.

**Tech Stack:** Swift 6 complete concurrency, Swift Testing, TCA, EventKit, macOS 14.

**Spec:** `docs/superpowers/specs/2026-11-01-event-query-cancellation-design.md`

## Global Constraints

- Keep macOS 14, Swift 6 complete concurrency and all 15 dependency pins unchanged.
- Only Sendable models cross the actor boundary; no production unsafe Sendable workaround or test-only query override.
- No installed app, login, preferences, TCC or native calendar query side effects.
- Source-only claims: the synthetic query cost does not measure native UI latency or explain the other Mac's crash.
- Ship one accepted revision as 1.4.7/build 14 through the existing full gates and automated release; controller alone commits after scoped acceptance.

## Review Focus

- Already canceled fetch: cancellation precedes even the authorization provider; new actor regression.
- Canceled queued fetches: they do no authorization/query work after the actor becomes available; new controlled queue regression.
- Uncanceled access denial: existing `accessUnavailable` behavior remains; new actor denial regression.
- Valid current request: local day bounds, mapping, sort and latest reducer response remain correct; existing EventKit/reducer tests and source-verbatim SDK probe.
- Cancellation during a synchronous query: the call finishes, then results are discarded before conversion; independent controlled SDK probe, with no claim of interrupting the native call.

---

### Task 1: Cancel obsolete actor work

**Files:**
- Modify: `GlimpseCore/Sources/GlimpseCore/Dependencies/EventKitClient.swift`
- Modify: `GlimpseCore/Tests/GlimpseCoreTests/EventKitClientTests.swift`

**Interfaces:**
- Consumes: `EventKitClient.eventsInterval(for:calendar:)`, `EventKitClient.calendarEvent(from:)` and `EventKitClient.QueryError.accessUnavailable`.
- Produces: existing `EventStore.fetchEvents(for date: Date) throws -> [CalendarEvent]` cancellation behavior; actor may become internal with `init(authorizationStatus: @escaping @Sendable () -> EKAuthorizationStatus = { EKEventStore.authorizationStatus(for: .event) })`.
- Existing `EventKitClient.liveValue` must use the same production actor and default native authorization provider.

- [ ] Add the minimal internal authorization seam without changing query behavior, then write `canceledFetchSkipsAuthorization`, `queuedCanceledFetchesSkipAuthorization` and `uncanceledDeniedFetchPreservesAccessError`. Assert `CancellationError` and zero authorization calls for canceled fetches; assert the existing permission error and one call for an uncanceled denied fetch. Controlled synchronization must release every waiter; use no sleep as synchronization.
- [ ] Run `swift test --filter EventKitClientTests --scratch-path <owned-private-scratch>` from `GlimpseCore`, retaining private logs. Establish a behavioral RED on canceled-work assertions, not a compile failure. Never permit synthetic authorization to return full access.
- [ ] Add cancellation checks before authorization/work and immediately after `store.events(matching:)`; preserve conversion and ordering. An already running synchronous query completes normally before the second check.
- [ ] Run the focused suite and full `swift test --scratch-path <owned-private-scratch>`; existing DST, conversion and reducer cancellation/request-identity tests must pass. Verify both resolved pin files remain unchanged.
- [ ] Write the implementer report, including RED/GREEN evidence, source hashes, synchronization design and limitations. Do not stage, commit, push or spawn helpers.

### Task 2: Accept and deliver the bounded fix

**Files:**
- Modify: `Glimpse.xcodeproj/project.pbxproj` (four marketing and four build versions)
- Modify: `README.md` (version badge)
- Create: scoped acceptance note under `docs/superpowers/reviews/`
- Modify: `.github/release-readiness.json`

**Interfaces:**
- Consumes: reviewed Task 1 production actor and tests, independent source-verbatim queue probe, current verified main `09f8257b1184e2f9df420eafee180b0967eeec9c`.
- Produces: scoped readiness approval and publicly verified 1.4.7/build 14.

- [ ] Obtain fresh task spec/quality review across A1–A8, independent before/after SDK probe and product/UX scoped acceptance. Resolve findings before delivery.
- [ ] Set all version occurrences to 1.4.7/build 14 and record scoped acceptance/readiness without closing native acceptance or the overall goal.
- [ ] Obtain fresh whole-branch review, inspect the exact staged paths/tree and run the ordinary actual pre-commit hook. Confirm full suite evidence, pin integrity and cleanup.
- [ ] Push through the ordinary pre-push hook, open and attach a PR, verify whole Push/PR Quality runs and all introduced head/synthetic revisions, then use an ordinary protected squash merge.
- [ ] Wait for the whole exact-main Release/Recovery run; independently verify public source identity, signed/notarized installer and app, feed/Sparkle signature and cleanup. Reopen the next-iteration gate only after success.
- [ ] Fast-forward the clean original checkout while preserving configuration; report the scoped result and still-open native acceptance.
