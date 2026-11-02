# Actionable update failures: scoped prepublication acceptance

Target: **1.4.10 / build 17**. Base:
`06e48b4fcf10c4af7abbe6a457c63c33ed73bb83`.

Product, UX, source review and focused QA pass for the implementation under the
[accepted design](../specs/2026-11-02-update-retry-design.md) and
[execution plan](../plans/2026-11-02-update-retry.md). The four readiness checks
refer to this scoped prepublication acceptance. Whole exact-staged-source
quality, protected integration, terminal exact-main Release/Recovery, public
signed artifacts and signed native acceptance remain separate required gates.
This document does not claim those gates passed or close the broader stability
goal. Current public distribution remains v1.4.9/build 16.

## Accepted behavior

About keeps check failures visible, offers an explicit eligible Retry and an
official native release link, and explains when Retry is temporarily unavailable.
An update failure offers a new guarded check, without replaying an install choice.
Initialization failure is terminal for this launch and offers View Releases
without another start attempt. No automatic retry or update is introduced.

Production retains one native updater. The same predicate controls presentation
and activation, with a live eligibility read and synchronous checking admission.
Owned offer/ready replies block checks until native dismissal. Install, Skip and
Relaunch use captured choice identities, retire ownership before invoking once,
and perform no old-state write after the callback. Error/latest/finished
acknowledgements likewise follow publication or cleanup. Only the current latest
result dismisses after five seconds; canceled old tasks cannot erase a successor.

All updater controls have explicit accessibility labels and padded hit targets.
Decorative icons are hidden from accessibility. Failure text wraps and conveys
meaning without depending on red. Native focus suppression is removed only in
the update section, with no global Return binding or calendar/input change.
The native release link supplies
`https://github.com/iRedlof/Glimpse/releases/latest`.

## Independent review and focused evidence

One independent senior reviewer read the complete frozen source, A1–A8, all
13 design acceptance rows, actual RED/GREEN evidence and all owner rulings.
Verdict: **source accepted; zero Critical, Important or Minor findings**.
All seven changed-file and five preserved-file hashes matched before and after
review. Review report SHA-256:
`f4c5c4f789f0ecfff1b007131c8d475122c959cd2b7250282b613bde958a3eb7`.
Metadata was synchronized afterward; reviewed app/test bytes were preserved.

Retained evidence root:
`/Volumes/xHome/Github/Glimpse/build/validation/update-retry-implementation.czvpigwr`.
It contains complete logs, command/exit and source/lock receipts, xcresults,
summaries, frozen source, `review/final-review.md`, its machine verdict and
`metadata-baseline-and-source-acceptance.json`.

| Contract group | Actual evidence |
| --- | --- |
| Initialization, persistent failure, live eligibility and double admission | Task1 behavioral RED: 5 failed named tests and 15 issues. GREEN: 6 named tests / 7 cases. |
| Choice replacement, retirement, progress failure and resumed manual checks | Task2 behavioral RED: 4 failed names and 13 issues. Cumulative GREEN: 15 names / 23 cases. |
| Five-second deadline, cancellation and acknowledgement replacement | Task3 behavioral RED: 4 failed names and 37 issues. Cumulative GREEN: 20 names / 51 cases. |
| Real hosted buttons/links, dynamic Retry, reconstruction and all rendered states | Task4 meaningful RED: existing Check press passed, 5 other names failed with 18 issues. Final cumulative GREEN: **26 named tests / 72 cases** across four suites. |

Final GREEN reports zero failures, skips and xcresult runtime warnings. Source
and lock hashes were identical before and after each accepted run. The system
log includes existing `linkd.autoShortcut` connection messages; zero xcresult
warnings does not imply pristine system logging. Counts overlap and must not be
added together.

The UI fixture uses the actual section, per-test injected native I/O, a controlled
awaited delay, owned offscreen windows and public accessibility methods. A
test-local public accessibility environment setting exposes SwiftUI nodes; public
Objective-C method dispatch accommodates nodes without full protocol conformance.
The existing Check positive control proved real activation before UI RED was
accepted. The Link action is intercepted and its exact URL asserted. No browser,
native updater, feed, production defaults, calendar access, TCC setting or real
update is used in these tests. Earlier compile, bootstrap, empty-tree and
zero-test-filter attempts are not product RED or success evidence.

## Requirements still needing distinct evidence

- Ordinary whole app/Core/tooling/monitoring quality and staged-source mutation
  checks, followed by protected delivery and public artifact verification.
- Signed visible About wrapping, content height/window fit, light/dark contrast,
  VoiceOver names/roles and readable status.
- Native keyboard traversal, focus indication, focused and disabled activation,
  normal close/editing/shortcut routing and absence of accidental default Return.
- Signed close/reopen for both runtime failures and outstanding choices, Check/
  Retry responsiveness and real browser handoff.
- Real network failure/recovery, deferred/resumed update prompts, Install/Skip,
  termination retry, successful installation and relaunch.
- macOS 14/Intel execution beyond inspected API availability; focused evidence
  comes from one arm64 macOS 27.0.1 host.

Safe injected fault presentations must stay labeled as controlled evidence.
They cannot establish real native fault or relaunch behavior. No production debug
switch was added. Existing alternative no-update reasons, information-only/major
updates, release notes, cancellation controls and termination recovery were
preserved; follow-on discovery is tracked as UPD-03 rather than claimed complete.

The original other-Mac crash is unexplained. Real restart testing is user-deferred.
Installed v1.4.9 screen-fit/scroll, endurance and other physical/native scenarios
remain separately open. Read-only process presence does not prove startup or a
visible menu-bar item.
