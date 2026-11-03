# Calendar query feedback: focused acceptance

Candidate v1.4.23/build30 replaces a technical Calendar query error with
“Couldn’t load events.” and retains the existing Retry action. The production
change is two lines in `CalendarPopoverView.swift`. Raw query errors remain in
the store; query, permission, selection, cancellation and refresh behavior are
unchanged.

Product acceptance covers understandable failure copy and the existing recovery
path. The retained specification is
`calendar-failure-copy-assessment.00o14h0u/spec.md` under the validation root.
UX acceptance covers the selected-date heading, failure/loading/empty distinction,
Retry, existing layout and accessibility text in light and dark appearances.
The independent A1–A8 source and QA review accepts the two-line view change and
the seven-line regression addition to the existing recovery scenario.

The original view with the new assertions produced four expected failures in
the two recovery cases. With the fix, the focused native suite passed all
13 methods/23 cases, with zero failures, skips or runtime warnings. Both Retry
and later store-change recovery still issue one additional query, retain the
selected date and week, show the recovered event and request no new permission.
The test confirms raw technical error text is absent from visible accessibility
labels and string values while the store retains it.

All 14 native captures were inspected. Twelve are byte-identical to the RED
captures; the selected-error light/dark images use the shorter friendly copy.
The existing centered state layout is retained. All 15 locked dependency pins
are unchanged.

Focused binaries used the pre-bump **v1.4.22/build29** metadata. Their 233-file
source manifest binds the view/test fix before the later candidate version and
documentation edits. Root accepted the independently sealed QA/code and UX
reports after rehashing 104 report inputs, nine outputs, all 233 source files,
71 original result inputs, 72 copied-reader inputs and 14 captures. The only
added copied-reader input was the recorded generated SQLite cache; producer,
export and cache provenance remain retained.

Evidence lives under
`build/validation/diagnostics-fixture-implementation.yucljzsb/` in the retained
original workspace:

- `calendar-failure-copy-internal-runtime.802ghhkr/root-focused-GREEN-acceptance.json`,
  SHA256 `867766447a6fb8e81d1ac6ea72918e65a6b73cad2b877291583861f1d5abefe7`.
- `calendar-query-focused-green-review.LIsDZK/report.md` and its sealed inputs.
- `calendar-failure-copy-ux-review.xoWWkZ/review.md` and its sealed inputs.
- `calendar-failure-copy-internal-runtime.802ghhkr/green/graph-export.6f2o9wm9/`
  and the retained RED graph/producer results.

**This is focused fixture and source acceptance.** The four readiness roles
refer to that scope. Final v1.4.23/build30 source still requires its own complete
Quality gate, independent review, protected integration, terminal exact-source
Release, signed public verification and official installation. Earlier Agenda
646-method/1,079-invocation or 52-image results are not fresh v1.4.23 results.

Canonical v1.4.22 was integrated at
`22dd6f7be495dc9c2ed0101bedcbd1b1ac6673b3`. Release 41648803423/1 was cancelled
before tests during the build-storage investigation; the previous internal
build-root route was restored. The one full same-run attempt2 then completed
successfully. Independent complete canonical QA accepted 646 methods/1,079
invocations, all 52 fresh captures and 15 unchanged pins; exact attempt2 signed
public artifacts and recoverable official installation/process launch passed.
Latest accepted public/installed distribution is v1.4.22/build29. Native Agenda
interaction remains separate. No Calendar query-feedback delivery is accepted
yet, and no canonical22 result is substituted for final v1.4.23 Quality.

The historical other-Mac termination, user-deferred reboot/login check,
endurance, physical keyboard/global shortcut, VoiceOver, macOS14/Intel and live
private-calendar/cloud behavior remain open. Passing fixtures and the release
storage investigation do not establish their outcomes.
