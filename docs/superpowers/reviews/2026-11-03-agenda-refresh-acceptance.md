# Agenda context and visible refresh: scoped candidate acceptance

2026-11-03 UTC. Candidate **v1.4.22/build29**, branch
`codex/agenda-canonical21`, based on delivered canonical v1.4.21 source
`c9afe67ffa1e3dfab1d245a502c8d8f025b55f56`.

**Product, UX, A1–A8 source review and complete implementation-preflight QA
are accepted. Final staged-source Quality, protected integration, Release,
public signed verification and installed Agenda checks remain pending.
The candidate is unshipped.**

The events area keeps one date heading through access, loading, result,
empty and failure states. A selected day's week context appears once.
With existing full Calendar access, an EventKit change refreshes the
current query day while the calendar panel is visible. Selection, month,
pin, AI draft and independent Settings ownership are preserved.

One subscription belongs to the retained calendar root. Its work checks
current visibility at main-run-loop delivery; hiding does not create a
new subscription, and removing the root cancels the subscription. No
notification payload is retained or forwarded. The existing reducer
rechecks authorization, cancels superseded queries and rejects stale
responses. This change does not request access, reopen a hidden calendar,
activate a window or send an AI query.

Independent PM/UX and architect/security reviews found no new actionable
blocker. The common heading retains accessible full-date/selected-week
context; the existing five-event preview, permission actions and Retry
remain. Constrained layouts scroll; the heading is not sticky.

The frozen implementation tree
`aec3cfe4459565d40266edae514765a963f9606c` used v1.4.21/build28 metadata.
Its unchanged complete archived Quality gate joined exit0:
ordinary app 261 methods/641 invocations, isolated keyboard/Settings28/46,
AI8/17, Agenda13/23, Core70/86, tooling239 and monitoring27.
Total: **646 methods/checks and 1,079 passing invocations**.
All49 ordinary skips are exactly covered by the mandatory isolated phases.
All15 dependency pins and232 source files were unchanged.

Independent QA inspected all52 native PNGs: Settings24, Today8,
viewport6 and Agenda14, in light/dark and constrained states.
Actual Settings key-window/responder, draft, pin and refresh predicates
pass without changing the original keyboard fixture or acceptance oracle.
Injected fixtures exercise event edits/additions/deletions, current
selection, queued hide, root reuse/removal, burst/late results,
permission loss and failure recovery. No private Calendar data is used.

Earlier failed/cancelled native activation controls remain retained.
This passing full run does not establish their cause or explain the
original other-Mac termination. Existing QoS/compiler diagnostics and
technical synthetic NSError copy remain documented follow-ups.
Signed Settings opening/four-section rendering in installed v1.4.21 is
separate evidence; CUA close selection cannot prove no-calendar-reopen.
Real restart/login is user-deferred; physical VoiceOver, macOS14/Intel,
live private EventKit/cloud behavior and endurance remain unverified.

Candidate metadata advances all four marketing versions and build
numbers, the README badge and readiness together. The operating inventory
and roadmap distinguish delivered v1.4.21 from this unshipped candidate.
App behavior, startup guard, immutable pins and physical key oracle remain
unchanged from the accepted implementation. The ordinary exact-source
commit hook and fresh protected admission are mandatory; the earlier
implementation preflight does not replace their final-source checks.

Retained evidence is under the ignored
`build/validation/diagnostics-fixture-implementation.yucljzsb/` root:
`agenda-canonical21-whole-quality-review.jzfd5ja4/`,
`agenda-implementation-architect-review.cn15z4om/`,
`agenda-release-product-review.tyuj8y1a/` and
`agenda-final-release-preparation.nuujrul5/`.
