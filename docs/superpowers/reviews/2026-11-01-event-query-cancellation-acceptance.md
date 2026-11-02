# Event query cancellation: scoped acceptance

Target: **1.4.7 / build 14**. Base:
`09f8257b1184e2f9df420eafee180b0967eeec9c`.

Product, UX, implementation and independent QA have passed for the
[bounded design](../specs/2026-11-01-event-query-cancellation-design.md).
This improves obsolete query handling. It does not explain the inaccessible
crash on the other Mac or certify installed availability, restart/login,
native UI interaction or sustained native performance.

## Accepted behavior

The production serial actor checks cancellation before authorization, interval
creation and native query work. Already canceled requests throw
`CancellationError`. After an active synchronous query returns, a second check
discards canceled results before conversion and sorting. EventKit's active
synchronous call itself remains noninterruptible.

Permission gating, native object ownership, Sendable model boundaries, local
day/DST bounds, event identity, conversion, sorting and reducer request identity
are preserved. The internal authorization provider defaults to the same native
status lookup; no production unsafe Sendable or query override was introduced.

Product/UX accepted the source against these requirements. No UI or persistence
behavior changes; separate panel overflow and formatter findings remain deferred.

## Regression and independent QA evidence

The real-actor denied-authorization fixture reproduced the old behavior:
two cancellation tests failed with 23 assertion issues. All 20 obsolete tasks
still checked authorization and returned the access error. The minimal fix
passes all five focused tests and all **65 core tests in five suites**, including
existing DST, conversion, reducer cancellation and stale-request coverage.
Synthetic authorization always denies access, preventing native calendar reads.

Independent Swift 6 complete-concurrency probes use byte-identical production
actor/helper/model source with only the SDK boundary replaced:

| Condition | Before | Accepted result |
| --- | --- | --- |
| 20 canceled requests while actor occupied | 20 canceled queries; 22 total queries | Zero canceled queries; only blocker and newest query execute |
| Cancellation during active synchronous query | Query completes, maps and returns results | Query completes once; zero mapping, actor returns or delivery |
| Already canceled task | Authorization/query/mapping still execute | All three counts remain zero |
| Valid request | Literal fields, fallback identity and chronological sort | Identical valid results and local 25-hour DST day bounds |
| Uncanceled denied access | Access error, no query | Identical error, no query |

Three synthetic 10 ms queue trials reduced newest completion from 290–296 ms
to 27–30 ms. This measures the controlled fixture, not real EventKit latency
or SwiftUI frame time. Cancellation arriving after the second check remains
covered by the reducer's cancellation and request-identity defenses.

Final production SHA-256:
`114a97fb572352a1e99af4639573844d0f4e66c51594b462fa5e796117f43246`.
Final test SHA-256:
`4a15ae31640ba30cff8fd416639d28ec78840cc68ed63c3fdb8aae4c828a9acf`.
Both 15-pin lockfiles remain byte-identical to base.

## A1–A8 review

Fresh independent task review passes spec compliance and code quality with no
P1/P2/P3 findings. A1 retains permission gating and performs no permission request.
A2–A5 introduce no panel, Carbon, Sparkle or AI behavior changes. A6 retains
serial native ownership and model semantics. A7 verifies minimal cancellation
checks and lock-protected test synchronization without sleep synchronization.
A8 confirms behavioral RED/GREEN and independent active-query coverage.

Private evidence remains under the configured external validation root:
`event-query-implementation.BEEwgn0d`,
`event-cancellation-independent-qa.t535mq21` and
`event-query-delivery.fkpef5ez`. Source hashes match the tested frozen files.
Owned implementation/probe scratch is removed; logs and receipts are retained.

Ordinary full commit/push quality, protected merge and exact-main automated
Release/Recovery checks remain required before publication acceptance. Native
acceptance and the broader reliability goal remain open.
