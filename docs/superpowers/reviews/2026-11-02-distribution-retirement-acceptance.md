# Distribution retirement and operating-docs candidate acceptance

2026-11-02. Candidate **v1.4.18/build25**, based on verified v1.4.17 source
`aa6009abf6c9ec46f21e66807d1a0ae635dddeae`.

**Product and UX acceptance cover the maintenance scope. Independent A1–A8 code
review accepted the expanded eight-file candidate at tree
`a75fa406ca985602204ce52e4f6bdce963015ec5`, including release metadata.
Its complete local quality gate and both hosted Quality runs passed and were
independently accepted. This note corrects the earlier, stale pending-review
statement; the amended candidate must pass exact-source integration checks before
protected integration and promotion. v1.4.18 is unshipped; installed
v1.4.17/build24 remains preserved.**

## Value and scope

Retire the dormant 483-byte root `glimpse.rb`, which pins v1.1.2 to an
unchecked ZIP, and reconcile operating documents with accepted v1.4.15–17
delivery. This removes an obsolete repository installation descriptor and
prevents shipped diagnostics, keyboard and AI work from being mistaken for
unfinished work. Official GitHub DMG installation and Sparkle updates continue.

The original reviewed source scope is two updated documents (`docs/product-inventory.md` and
`docs/stability-roadmap.md`), one added dated v1.4.17 status note and the cask
deletion. The expanded candidate adds synchronized project/README/readiness
metadata and this dated acceptance note. There are no production or fixture Swift
changes. Descriptor SHA-256 is
`541b5a4fab13297bea8d40f5748f358d2f2cb80c09894ea290deb7bacaab5e00`.
Private/unindexed tap copies and actual users remain unknown; a direct-path
recipe user may need the documented DMG route. No external tap, existing app,
preference or historical release asset is removed.

## Accepted source evidence

[Independent A1–A8 review](/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-fixture-implementation.yucljzsb/operating-roadmap-independent-review.sqf3y75i/review.md)
accepted the four-file source, with three minor corrections.
[Focused correction review](/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-fixture-implementation.yucljzsb/operating-roadmap-minor-review.o5m18_pr/review.md)
closed all three with no new findings at staged tree
`e96ba167ef51361511a900bb6ce07a5941210931`. It verified qualified Shortcuts
wording, the 593-method historical breakdown, readable spacing and preserved
history. This does not review later release metadata or an added fixture change.

[Expanded independent A1–A8 review](/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-fixture-implementation.yucljzsb/operating-roadmap-expanded-source-review.etxge57y/review.md)
subsequently accepted the full eight-file candidate at tree
`a75fa406ca985602204ce52e4f6bdce963015ec5`, with zero Critical, Important or
blocking findings. The lead accepted its two Minor documentation findings:
compressed prose and an omitted account of the metadata-tool collision. The
collision and recovery are recorded below. No production or fixture Swift change
was introduced.

| Role | Current bounded decision |
| --- | --- |
| Product — Lead | Passed for the maintenance scope: truthful distribution and operating status are useful. No selected-event handoff or new app behavior is promised. |
| UX — Lead | Passed for the maintenance scope: supported DMG route, migration caveat and acceptance limits are explicit. No new native interaction acceptance is claimed. |
| Code — independent reviewers | Passed for expanded tree `a75fa406…`, including project, README and readiness metadata; zero Critical, Important or blocking findings. |
| QA — independent reviewer and Lead | Complete local quality and hosted branch/PR Quality passed for `d40a0f5…` / tree `a75fa406…`, with 593 distinct methods per tested source. The earlier ordinary failure is retained. The amended candidate still requires fresh exact-source checks. |

## QA and release boundary

The first [ordinary commit receipt](/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-fixture-implementation.yucljzsb/operating-roadmap-implementation.qnop355g/ordinary-commit.ws9p7oqc/supervisor-receipt.json)
records exit 1 and unchanged HEAD. The retained
[keyboard summary](/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-fixture-implementation.yucljzsb/operating-roadmap-implementation.qnop355g/ordinary-commit.ws9p7oqc/quality-results/keyboard-ownership-summary.json)
failed `focusedLogicalDateStaysVisibleInCappedViewport(maximumHeight:)` at the
visibility/key-window opening precondition; the lead identifies the 312pt case.
This is an unresolved native fixture result, not proof that descriptor removal
caused a product failure. Original failure evidence stays retained.

Root retained an observation-only mirror, an initial Swift6 instrumentation
compile error and its correction. The instrumented suite passed14/16; actual
`hidesOnDeactivate` was false. The [unmodified-source contrast](/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-fixture-implementation.yucljzsb/keyboard-visibility-observation.cssu9gtx/unmodified-source-contrast/root-contrast-adjudication.json)
then passed14/16 with all222 source files equal to the frozen archive. Both native
children were actually joined, metadata/artifacts checked, and owned host absence
confirmed. The compound assertion does not isolate visibility from key loss; its
post-cleanup trace cannot do so. No cause, fixed failure or product defect is
established. No activation, hide policy, assertion or fixture change enters this
candidate. The final ordinary gate remains the integration requirement.

Concurrent metadata reads against the same instrumented result bundle initially
exited 64 with a SQLite collision. Those failures remain retained. A copied bundle
was then read sequentially: summary, tests, checker and collector all exited 0.
This was a metadata-tool recovery, not a product fix or an additional passing
test.

The later [ordinary local quality acceptance](/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-fixture-implementation.yucljzsb/operating-roadmap-implementation.qnop355g/root-local-quality18-independent-qa-acceptance.json)
and [hosted quality acceptance](/Volumes/xHome/Github/Glimpse/build/validation/diagnostics-fixture-implementation.yucljzsb/root-hosted-quality18-independent-acceptance.json)
cover candidate `d40a0f5e38082e3802953bee232cfc36daf671e6`, tree `a75fa406…`.
Hosted branch run `41558675943/1` and PR run `41558742267/1` passed; the PR also
tested merge commit `983858669bca1cf604c5684d8093f2489ddc3979` with the same tree.
Each tested source passed 593 distinct methods: 255 ordinary app methods
(629 cases, with 22 duplicate isolated methods skipped), 14 keyboard methods
(16 cases), 8 AI methods (17 cases), 70 Core, 219 release-tooling and 27 monitoring
methods. Native/compiler warnings and the original keyboard failure remain in
the retained evidence. These results do not claim a cause for the earlier
failure or verification of a new public release.

`tools/scripts/release-control.py:183` excludes root `glimpse.rb` from its
internal-only allowlist. The earlier internal-only recommendation is superseded:
this candidate follows the normal **v1.4.18/build25 release**. Do not relax the
classifier or split the deletion to evade release requirements. All four
marketing/build pairs, README badge and matching readiness evidence must be
synchronized; static version/pin checks and scoped source review apply to that
metadata. Readiness records completed domain acceptance, including the expanded
code review. Fresh complete staged-source quality remains required before normal
protected admission/integration, terminal exact-source release, independent
public artifact verification and recoverable installation. These delivery steps have not been accepted for this candidate.

## Historical evidence and open outcomes

The [v1.4.17 status note](2026-11-02-installed-v1417-status.md) records historical
public/installed verification, native interactions and bounded performance.
Its 593 passing methods and native/performance results do not pass candidate18
quality or establish a new runtime outcome. v17 remains the latest accepted
public/installed release until candidate18 delivery is verified.

The original other-Mac crash remains unexplained; real restart is user-deferred.
Longer endurance, sleep/wake, loaded/private-calendar work, physical keyboard,
VoiceOver, macOS14/Intel and Shortcuts runtime identity/hidden opening remain
open. Finder remains the accepted autonomous navigation route. No new app
behavior, event handoff, permission expansion or whole-product completion is
promised by this maintenance release.
