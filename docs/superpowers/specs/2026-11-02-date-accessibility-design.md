# Individually actionable calendar dates

This is the date-semantic substep of the existing A11Y-01b design in
[accessibility-controls-design.md](2026-11-02-accessibility-controls-design.md).
The lead selects this bounded implementation under the user's autonomous brief.

## Evidence and scope

The signed v1.4.13 calendar was opened autonomously through Finder. Its native
accessibility tree exposed all 42 dates in one combined text node, without
individual date-button actions. Arrow/month/year navigation, Return-to-today
and AI draft dismissal passed the separately recorded native baseline.
This does not establish VoiceOver failure or ordinary keyboard focus behavior.

Use a native SwiftUI `Button` for every existing date cell. Its single action
sends `.dateTapped(day.date)`; remove the extra tap gesture. The existing reducer
continues to select, deselect and enforce calendar authorization. Retain the
visual label, 30-point cell height, full-cell rectangular target, hover, today
fill, selected ring/trait, full-date/today/outside-month label and grid container.
Outside-month selection does not change the displayed month.

Keep `.buttonStyle(.plain)` and `.focusable(false)` as required by the view
rules. No focus model, key-monitor change, new shortcut, permission change,
system accessibility setting or production preference mutation is included.
Ordinary keyboard traversal and VoiceOver interaction remain separate outcomes.

## Validation and delivery

Host the actual `CalendarPopoverView` in the existing owned offscreen
accessibility host, with fixed synthetic dates, injected stores, pure calendar
generation, disabled AI UI, unauthorized event fixtures and no live preferences.
Never press footer, grant-access or preference actions in these fixtures.
Record unexpected external I/O as a test failure.

Before changing production code, prove that individual native date actions are
missing in this real view. Then verify 42 distinct button nodes, their bounds
and contextual labels, actual default press selection/deselection, outside-month
behavior, selected state and single dispatch from center/inset-edge pointer
presses. Accessibility enumeration alone must not select or fetch a date.
Retain current input/layout/selection regressions and run the mandatory whole
quality gate through the ordinary commit hook.

An independent A1–A8 review precedes protected integration. Synchronize the
candidate's version/build and record actual Product, UX, Code and QA decisions.
Release/public signatures/official installation are separate gates. Use the
verified Finder route for signed native date discovery and activation; record
VoiceOver, macOS 14, broader focus and constrained-display gaps truthfully.
Do not call A11Y-01b or the whole stabilization goal complete from this slice.
