# Cancel obsolete queued calendar queries

## Problem and evidence

The calendar reducer cancels obsolete effects and rejects stale responses, but
`EventStore.fetchEvents(for:)` still executes when an already canceled task reaches
the serial actor. Independent QA reproduced this with the production actor body
and a fake EventKit boundary: all 20 canceled requests queried the store. Synthetic
10 ms queries delayed the newest result to 294–314 ms, versus 11–15 ms alone.
These timings establish avoidable queued work, not actual EventKit or UI latency.

## Required behavior

- Check task cancellation at actor entry, before authorization, interval creation
  or native queries. An obsolete queued request throws `CancellationError`.
- After an active synchronous query returns, check cancellation before converting
  and sorting its results. A synchronous EventKit call cannot be interrupted.
- Keep native EventKit objects owned by the same serial actor. Only Sendable
  calendar models cross its boundary.
- Preserve permission gating, local calendar day/DST bounds, event identity,
  conversion, sorting and reducer request identity checks.
- Add Swift Testing regressions against the production actor, using a narrow
  internal authorization provider if needed. Denied synthetic authorization must
  prevent all test calendar queries; no TCC requests or real calendar reads.
- Independently repeat the source-verbatim fake SDK queue probe before and after
  the fix, including cancellation during the active query and a valid newest
  result. Retain its evidence and limitations outside the repository.

## Scope and constraints

Swift 6 complete concurrency, macOS 14 minimum, TCA and all 15 dependency pins
stay unchanged. No unsafe Sendable production workaround or test-only query
override. Panel sizing and date formatting improvements are separate work.

The current signed installed app, login settings, preferences and permissions
stay untouched pending native acceptance authorization. This change does not
explain the inaccessible crash on the other Mac or prove restart reliability.

One accepted source revision will ship as 1.4.7/build 14. Before committing,
product, UX, implementation and QA for this bounded change must be complete.
Use the ordinary full pre-commit/pre-push gates, protected PR merge and automated
release. No further commit or push until the exact merged Release/Recovery run
is successful and its published assets independently verify.
