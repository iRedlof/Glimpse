# Calendar date action acceptance

2026-11-02. Candidate **v1.4.14/build21**, branch `codex/date-accessibility`,
based on accepted canonical v1.4.13 source
`10cd533daa7f377ac7c4484b1441576441794d02`.

**Status: implementation, affected owned-fixture verification and independent
source review accepted. Final mandatory whole-source quality, protected
integration, public delivery and signed native date checks remain pending.**

Each existing date cell is a plain native SwiftUI Button with one
`.dateTapped(day.date)` action. The extra tap gesture is removed. Existing
30-point full-cell targets, fonts, backgrounds, hover, date context, selected
trait, grid containment and `.focusable(false)` policy are retained. No reducer,
dependency graph, key monitor, permission, startup or updater change is included.

[Design](../specs/2026-11-02-date-accessibility-design.md) and
[plan](../plans/2026-11-02-date-accessibility.md) define this bounded substep.
Ordinary keyboard focus/traversal and VoiceOver interaction remain open.

## Observed evidence

Evidence is retained outside tracked source under
`build/validation/update-guidance-implementation.bpo8vktn/date-accessibility-implementation.gumn3kpn/`.

| Boundary | Actual outcome |
| --- | --- |
| Signed baseline | Finder opened v1.4.13 autonomously; repeated Show preserved the viewed month. The actual date accessibility tree was one combined text node. This is not a VoiceOver failure claim. |
| First fixture attempt | Executed zero tests because the new test file lacked explicit Xcode registration. Excluded from acceptance. Registration was added before production changes. |
| Second fixture attempt | One name/two cases exposed zero date buttons, with two unimplemented preference reads per case. Excluded from clean RED acceptance; relevant pure reads were then supplied explicitly. |
| Accepted unchanged-view RED | Four names/nine cases executed and failed on absent date buttons. The production date view was unchanged. No unimplemented dependencies or xcresult runtime warnings; source/pins unchanged. |
| Affected GREEN | 48 names/109 actual execution cases across seven suites passed, including four date names/nine cases. Zero failures, skips, expected failures or xcresult runtime warnings; source/pins unchanged. |
| Date actions/layout | The complete production root exposed 42 distinct native button names, enabled 30-point disjoint targets in light/dark appearances. Default press selected the exact synthetic date; repeated press deselected it. Outside-month press preserved the month and event-access boundary. Center/four inset corners dispatched exactly once. Enumeration alone did not select/fetch. |
| Protected inputs | Existing calendar input, scroll router, panel layout, icon/search accessibility and persistent viewport regressions passed in the same affected run. This does not prove native focus/traversal. |

Raw AppIntents/linkd4097 startup diagnostics are retained separately. No claim
that all raw system diagnostics disappeared follows from the empty xcresult
runtime-warning list.

The actual root has injected calendar/preferences stores, fixed synthetic time,
pure calendar generation, disabled AI UI and `.notDetermined` authorization.
Unexpected event access or preferences actions fail the fixture. Only owned
test windows receive synthetic pointer events; system accessibility settings,
production preferences, calendar data and the installed app are untouched.

## Scoped decisions

| Role | Actual decision |
| --- | --- |
| Product — Lead acting PM | Passed: native date activation directly addresses an observed usability gap, without inventing a new feature or changing selection semantics. |
| UX — Lead against existing A11Y-01b design | Passed at source/owned-fixture scope: dates expose separate actions/context and retain measured targets, selection and outside-month behavior. Signed visual/assistive interaction remains separate. |
| Code — independent reviewer | Passed at frozen staged tree `8e95cdb897cff23a038ca6590d206561aded85ed`: whole-candidate A1–A8 review found zero Critical/Important issues and one Minor test-locale follow-up, deferred by the lead. Subsequent edits only record readiness, plan progress and this decision; the ordinary hook still must accept the final staged tree. |
| QA — Lead against raw receipts | Passed at affected fixture scope: actual unchanged-view RED followed by 48/109 GREEN, no unexpected I/O and unchanged dependency pins. Mandatory staged-source quality and hosted/native delivery remain separate required gates. |

Public/installed latest is v1.4.13/build20, with exact-source terminal release,
independent signed public verification and recoverable official installation
accepted. The original other-Mac crash remains unexplained; restart is deferred
by the user. The 180-second resource baseline does not establish optimization,
leak freedom or endurance.

macOS 14, VoiceOver press, ordinary focus/traversal, constrained display/focus,
sleep/wake and signed date activation are unperformed. This date semantic
iteration does not close A11Y-01b or the whole stabilization goal.

## Review adjudication

The lead accepted the independent review's source-level verdict and all five
review-focus assessments against the retained RED/GREEN evidence. The reviewer
did not rerun tests or operate native UI. Final: minor (deferred): fixed English
Foundation date expectations can fail under a different test locale/calendar;
no production action defect was established. A separate test portability change
can use locale-aware expectations or owned process configuration.

| Declined boundary | Lead decision and cost |
| --- | --- |
| D1 signed VoiceOver discovery/press | Remains open: direct owned selectors do not prove spoken context or assistive interaction. |
| D2 macOS14/Intel/other OS runtime | Remains open: build compatibility does not prove native behavior on unavailable environments. |
| D3 ordinary traversal/activation/focus ownership | Remains a separate keyboard design: unchanged routing and `focusable(false)` leave traversal unaccepted. |
| D4 today/selected/hover pixels | Keep signed visual follow-up; source styling and geometry pass, while pixel equivalence is unmeasured. |
| D5 exhaustive input matrix | Accept bounded native repeat/outside and five pointer cases for the uniform single action; untested combinations remain, with no established defect. |
| D6 authorized EventKit/DST/revocation | Preserve separate private-event acceptance; no fresh authorized live cases were exercised. |
| D7 arbitrary footer/preferences/AI actions | Preserve the exact fixture action boundary; it does not accept all root workflows or arbitrary fuzzing. |
| D8 physical display/Spaces/sleep/rollover | Remains open with unchanged owners; cross-environment behavior is unverified. |
| D9 prior v1.4.13 navigation/public evidence | Retain the lead's independently accepted receipts without repeating unchanged checks; Shortcuts hidden opening remains unresolved. |
| D10 downstream quality/integration/release/install | Required gates remain pending; source review alone cannot release this candidate. |
| D11 crash/restart/endurance | Preserve the whole-product backlog; the other-Mac cause, deferred real restart and long-duration metrics remain unmet. |
| D12 proxy/updater/cask/diagnostic timing | Keep existing separate backlog entries; this date change does not fix those systems. |
| D13 inherited prose/unused argument | Defer bounded cleanup; inherited wording and an unused parameter remain without a new functional regression. |
| D14 raw AppIntents/linkd4097 diagnostics | Retain raw diagnostics without suppression; cause and production effect remain unknown. |
