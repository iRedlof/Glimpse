# A11Y-01 focused product/UX design

Design candidate, 2026-11-02. Source root: `/Users/rohit/.codex/worktrees/stability-ux/Glimpse`; inspected HEAD: `ec5e15c4f238e2d3eeb114bb2bdcf1cde04dfd96`, matching the brief. All source references below are relative to that root at that revision.

No implementation, builds, tests, app launch, native accessibility inspection, or user validation occurred. Root will supply an independent builder check before accepting this design.

## Intent and scope decision

Make existing preferences understandable without relying on adjacent text, color, or abbreviated labels, and make small icon actions easier to point at. Retain the compact menu-bar calendar, native control semantics, and current visual treatment.

The concrete names, target dimensions, and delivery split below are the designer's product calls under the autonomous brief. They are not reported user requirements. This work follows UX-01 acceptance and does not change its delivery order.

Choose two bounded implementation slices under A11Y-01:

1. **A11Y-01a: names, state, and icon targets.** Ready for an implementation plan after builder review. Correct four empty-label native controls, clarify the five display pills, name the AI dismiss action, and enlarge footer/header/AI-dismiss icon targets. No keyboard monitor or focus-policy change.
2. **A11Y-01b: date semantics and keyboard access.** Keep open as a separate interaction iteration. Native date-button semantics have a concrete proposal below; ordinary keyboard focus/activation needs a short native baseline and explicit routing design before implementation. A11Y-01a must not close A11Y-01 as a whole.

Options considered:

| Option | Benefit | Cost / decision |
| --- | --- | --- |
| Add labels everywhere | Small text patch | Reject: several controls already have useful names; this misses pill state and targets and can produce duplicate speech. |
| Focused semantic names/state plus existing icon target expansion | Direct value with local view changes and unchanged input ownership | Choose for A11Y-01a. |
| Convert all pills, dates, and icon controls into a new focusable control system | Could address broad keyboard navigation | Defer: requires resolving Return/arrows, visible focus, panel reuse, and editing ownership. Too much interaction change to bundle with names. |

## Source-grounded findings

These are source observations. An empty SwiftUI control title is not proof of what VoiceOver currently announces, and an absent explicit target frame does not establish its measured native hit rectangle.

| Finding and evidence | User outcome / proposal |
| --- | --- |
| `PreferencesView.swift:91–101` has sibling text “Filled background” and `Toggle("")`; `223–235` repeats that pattern for “AI date search.” Neither toggle has its own accessibility name. | Give each native toggle a meaningful title while retaining `.labelsHidden()`, mini switch styling, and its current binding. Expect native toggle role and native on/off value. |
| `PreferencesView.swift:154–171` has `Picker("")` for start of week; `240–250` has `Picker("")` for AI provider. Option text exists in both. | Name the pickers “Week starts on” and “AI provider”; preserve native selected-option values and menu behavior. |
| `PreferencesView.swift:115–146` uses actual text buttons: “Icon,” “Day,” “Mon,” “Date,” “Year.” On/off is represented by fill, weight, and foreground; no explicit accessibility value is present. | Keep the pills and actions. Expand their accessible names and expose On/Off. “Mon” means month in source, not Monday. This is state/clarity repair, not five unnamed controls. |
| `CalendarPopoverView.swift:348–360` has an image-only button without a name; it clears query and error and exits editing. While processing it is replaced by a progress view (`343–347`). The surrounding AI row has a label at `393`. | Name this action “Close date search,” with hint “Clears the query and closes date search.” “Clear” alone would incorrectly imply that editing stays open. Do not introduce cancellation during processing. |
| Footer buttons already have explicit names and native `Button` semantics (`CalendarPopoverView.swift:749–815`), including state-dependent Pin/Unpin and Open/Close preferences. Labels contain only an image with no explicit target frame. | Preserve names/actions and provide actual, nonoverlapping target rectangles. This is target repair, not a footer naming rewrite. |
| Header buttons already have names (`CalendarPopoverView.swift:282–313`); Go to today is an 8 pt symbol. | Apply the same modest target treatment to these three adjacent icon controls. This is a chosen small extension of the footer target work. |
| Date cells use full-frame `Text`, rectangular `contentShape`, hover, and `onTapGesture` (`CalendarPopoverView.swift:526–579`). They already have full dates, today/outside-month context, and selected traits (`577–594`). Grid containment/name already exists at `514–515`. | Preserve this information and cell geometry; native button activation is the proposed follow-on. Do not “fix” labels that are already present. |
| The key monitor owns unmodified arrows for month/year and Return for AI submit/today (`CalendarPopoverView.swift:149–214`). `.focusable(false)` is used on buttons throughout both views and required by `.claude/rules/swiftui-views.md:14`. | A label or button-role modifier alone cannot establish ordinary keyboard access. Keep this interaction issue explicit in A11Y-01b. |

Existing useful semantics are retained: workday pills have full weekday names/state at `PreferencesView.swift:190–216`; startup and shortcut controls have explicit names/status at `269–278` and `344–394`; header controls, event actions, and footer controls already have names. Text-labeled native buttons can supply meaningful names without duplicating the same text in a modifier. The A1.2 checklist's intent is meaningful names and roles, not repeated spoken wording.

## A11Y-01a control contract

| Control | Accessible name | Role / value / action |
| --- | --- | --- |
| Filled background | Filled background | Existing native switch; native On/Off; unchanged display binding and menu-bar notification. |
| AI preference toggle | AI date search | Existing native switch; native On/Off; unchanged preference action. |
| Start-of-week picker | Week starts on | Native picker; selected full weekday name supplied by existing option text. |
| Provider picker | AI provider | Native picker; selected provider's existing `displayName`. Present only when AI search is enabled. |
| Icon pill | Show icon in menu bar | Existing button; accessible value On/Off from `showIcon`; press toggles once. |
| Day pill | Show day of week in menu bar | Existing button; value On/Off from `showDayOfWeek`; press toggles once. |
| Mon pill | Show month in menu bar | Existing button; value On/Off from `showMonth`; press toggles once. |
| Date pill | Show date in menu bar | Existing button; value On/Off from `showDate`; press toggles once. |
| Year pill | Show year in menu bar | Existing button; value On/Off from `showYear`; press toggles once. |
| AI dismiss icon | Close date search | Button; clears query/error and returns to the existing collapsed prompt while keeping the panel open. Hint as above. |
| Footer | Existing Quit Glimpse; About Glimpse; Pin window/Unpin window; Open Calendar app; Open preferences/Close preferences | Existing native buttons and dynamic names. Quit still opens confirmation; it does not terminate immediately. |
| Header | Existing Previous month; Go to today; Next month | Existing native buttons. Preserve Go to today's disabled condition. |

Use nonempty native Toggle/Picker titles with hidden visual labels as the default implementation. Use explicit accessible labels where short pill text or image content needs replacement. Avoid manually overriding native switch/picker values or writing “button,” “switch,” or “picker” into names. Keep pill state in the value rather than redundantly in both the name and value.

The AI row's parent label and tap gesture can affect the resulting accessibility tree. Native acceptance must show the active text editor and Close date search as separate usable controls, with no extra row action that obscures either. Do not add a second blanket label to that parent. If observed grouping hides either child, the bounded repair is to place “Go to date using AI” on the actual collapsed button and active field and remove the conflicting container label/grouping; retain the field's example placeholder. This choice is conditional on the tree, not a claimed current defect. No query, provider, parsing, or network behavior changes are in scope.

Target dimensions are a compact desktop product choice, not a claim of formal accessibility-standard compliance:

- Five footer icons and three header icons: **28 × 28 pt** actual hit rectangles, icons centered with their existing size/color. Reuse an appropriate named AppDesign control token, adding one only if needed; do not reuse an unrelated calendar-circle token just because it also equals 28.
- AI dismiss: **24 × 24 pt** actual hit rectangle within the existing AI row. This keeps more width for text while exceeding the glyph's visible area.
- Put the frame and rectangular `contentShape` inside the button's label so the whole allocated rectangle activates its button. Do not use an overlay target that overlaps a neighbor or intercepts scrolling.
- Preserve footer order and leading Quit separation. Rectangles must remain disjoint, with at least the existing 8 pt standard spacing between adjacent footer/header buttons. The footer's 268 pt inner width can accommodate five 28 pt controls, four 8 pt gaps, and remaining spacer width; native layout must verify actual allocation.
- Preserve the 316 pt root / 300 pt body (`PanelGeometry.swift:9–16`). Extra natural height is handled by the existing persistent viewport. Do not shrink text, widen the panel, or set a fixed overall content height to compensate.
- Date cells remain 30 pt high, with the existing full-cell hit shape; pill/workday sizing remains unchanged in this slice.

## A11Y-01b: date activation and keyboard follow-on

The preferred semantic change is a native SwiftUI `Button` for each of the existing 42 date cells, using the same visual label content and `.buttonStyle(.plain)`, one action sending `.dateTapped(day.date)`, and no additional tap handler. Retain full-date label, today/outside-month wording, selected trait, hover treatment, 30 pt height, and grid containment. An outside-month date remains selectable exactly as now; do not add automatic month navigation. Pressing the selected date still deselects it and follows existing event behavior (`CalendarFeature.swift:143–151`; tests at `CalendarFeatureTests.swift:321–397`). Accessibility focus must not itself select or fetch a date.

For the date semantic substep, keep the existing `.focusable(false)` policy unless the separate keyboard design is being delivered with it. Required native evidence: each date is individually discoverable with a native button role/default press action; VoiceOver press selects exactly that date, repeated press deselects it, and it does not jump to today. The actual accessibility action is the success criterion; adding `.isButton` alone is insufficient.

Keyboard work remains a named open part of A11Y-01b, including the current footer/preferences focus policy. Do not claim that semantic date buttons complete keyboard access. Before choosing an implementation, record a native baseline for:

- VoiceOver movement/activation versus ordinary Tab/Shift-Tab and Space/Return in the reused nonactivating panel.
- Which native focus owner exists for an actionable control, a date, the AI editor, picker menus, and the shortcut recorder.
- Whether focused offscreen controls scroll into view in the constrained viewport and whether focus survives or resets correctly on hide/reopen.

The follow-on's required outcomes are concrete: users can reach a date and activate it without a pointer, discern focus independently of the selected-date ring, leave the calendar/control area without a trap, and use the editor/recorder without calendar interception. Native focused controls must own their activation keys; Return-to-today and month/year shortcuts apply only in the calendar navigation context. Modified commands and VoiceOver commands pass through; hidden/foreign windows consume no keys. Reopening keeps the existing current-month/today-selection reset and must not focus a stale hidden control.

Prefer native focus/activation before considering a custom roving grid. Do not introduce a 42-cell focus model, new shortcuts, focus timers, AppKit accessibility wrappers, or a blanket removal of `.focusable(false)` in A11Y-01a. The precise keyboard traversal scheme and narrow exception to the repository's no-focus-ring rule belong to the follow-on design after native evidence. This is a remaining product/interaction decision, not an implementation detail to guess while adding labels.

## Integration constraints

- Swift 6, macOS 14 deployment floor, current TCA stores/actions/bindings and native styles. No new package or Core UI imports. Names and hit areas belong in the app view layer.
- Preserve `displayBinding` and notification paths (`PreferencesView.swift:15–37`, `127–129`), persistence/actions (`PreferencesFeature.swift:85–137`), and current provider selection.
- Keep one persistent `PanelViewport` and guarded height observation (`PanelViewport.swift:13–45`; `PanelLayoutState.swift:18–37`). Keep scroll ownership and momentum suppression (`CalendarScrollRouter.swift:38–78`). Do not introduce nested scrolling or viewport replacement to accommodate larger targets.
- Preserve reusable show/hide cleanup, AI task/editor reset, monitor ownership, and scroll reset (`CalendarPopoverView.swift:75–127`, `238–247`; `CalendarPanel.swift:138–175`). Close date search must not call `deactivateTextInput`; its current comment records that as a panel-dismissal risk.
- Preserve pin behavior, shortcut recording/cancellation, startup status, event authorization and private data. Do not change global defaults, TCC, system keyboard navigation, VoiceOver settings, or production calendar state as a test convenience.
- Preserve the single-image menu renderer and shared preview (`StatusItemPreview.swift:5–25`). No renderer rewrite or added status-button subviews.
- UX-02 owns updater errors/retry. About, updater, diagnostics, external Calendar launch, and quit confirmation workflows retain their current semantics.
- A1 names/roles/actions and A2–A3 lifecycle/input are primary review areas; A4–A6 protected workflows must remain unaffected; A7 keeps local view code/tokens simple; A8 requires evidence at the behavior boundary. Do not manufacture a model just to unit-test literal labels.

## Acceptance and verification matrix

Everything below is proposed future validation, not completed evidence.

| Check / evidence level | Acceptance |
| --- | --- |
| Source review for A11Y-01a | Four native controls receive nonempty meaningful titles; five pill names/value bindings match the table; dismiss name describes its actual behavior; no duplicate native-role wording; actions, persistence, and focus/input code unchanged. |
| Hosted native-control fixture, Swift Testing on main actor | Enumerate actual accessibility elements for the affected production controls where macOS exposes them: meaningful name, native role/value, exactly one available press/toggle action, correct value after activation. Use existing controls or a small extracted local view shared with production, not a separate lookalike. No string-only helper tests as a substitute. If hidden-host AX is unavailable, record that limitation and move those assertions to native acceptance. |
| Target/layout regression | In a hosted view of the actual target treatment, test center and inset-edge hit points map to the intended button/action; adjacent points do not trigger two actions. Verify 28/24 pt hit bounds, disjoint controls, and body containment. Exercise normal and constrained height with legacy/overlay scrollers; retain existing convergence/viewport tests. Merely asserting a token equals 28 is insufficient. |
| Preference action safety | Retain `PreferencesFeatureTests.swift:37–160, 337–370`; use in-memory dependency spies if activation wiring changes. Assert each changed control sends the existing action once and native values match resulting state. No production defaults writes. |
| Date semantic slice | Hosted/native default press selects, repeated press deselects, outside-month press preserves current month behavior; existing reducer tests establish state/event semantics but do not prove AX activation. Full date/today/outside-month/selected information is retained. |
| Input regression | Retain `CalendarInputTests.swift:20–52`, `CalendarScrollRouterTests.swift:71–95, 107–221`, and `HotkeyPreferencesModelTests.swift:137–184`. For later keyboard routing changes, extend real routing/event tests to focused controls, Return/Space, recording, hidden/foreign panels, and modified keys. The current static navigation predicate tests alone do not verify native key delivery. |
| Native A11Y-01a acceptance | On macOS 14 and the available current supported macOS, inspect names/roles/values, use VoiceOver to activate affected controls, verify no duplicate/obscured actions, and click target edges. With preferences open and constrained height, reach each control through scrolling. Check AI typing, arrow movement, submit once, dismiss, Escape, reopen, pin/unpin, and recorder cancel using synthetic inputs/fixtures. |
| Native A11Y-01b acceptance | VoiceOver date discovery/press; selected vs focus distinction; ordinary keyboard traversal/activation according to the follow-on design; focused-control visibility while overflowing; preferences/pickers/editor/recorder ownership; repeated hide/reopen and pin behavior. |
| Integration / release | Independent A1–A8 review, focused regressions, then exact-source whole quality, synchronized versions and existing protected release/public-artifact gates. Signed installed smoke results and unperformed native cases recorded separately. |

Native fixtures must not quietly fall back to production dependencies. In particular, injecting a `PreferencesFeature` store alone does not isolate `PreferencesView`: its `@State HotkeyPreferencesModel()` at `PreferencesView.swift:342` reaches `.shared` hotkey and `.standard` defaults (`HotkeyPreferencesModel.swift:88–94`). Host isolated affected controls for focused tests, or use a deliberate minimal injection seam when whole-view validation requires one. Also inject calendar authorization, time, preferences and events; do not trigger live AI, EventKit, login registration, Calendar launch, About, or Quit from automated action tests. Footer action receipts can verify dispatch in an owned fixture. Actual signed smoke is separate and uses only already-authorized workflows.

Use an isolated QA fixture/account with synthetic dates/events and disposable preferences for mutation checks. Native checks needing VoiceOver or a different keyboard-navigation setting require an available authorized setup; do not alter this user's system preferences to create it. If macOS 14 or authorized assistive-technology interaction is unavailable, report that exact acceptance gap. A successful newer-OS build, accessibility-tree snapshot, or unsigned hidden host cannot establish macOS 14 VoiceOver behavior or signed panel lifecycle behavior. No all-platform or full-accessibility-compliance claim follows from this iteration.

## Dependencies, order, and retained backlog

| Work | Relative effort / dependency | Completion boundary |
| --- | --- | --- |
| A11Y-01a design acceptance and plan | Small; fresh builder check, then UX-01 accepted source/ordering | Resolve builder issues; verify final baseline before implementation. |
| A11Y-01a implementation | Small view/token change; moderate native validation effort | Names, values, targets and protected interactions meet the matrix. Can ship independently while A11Y-01b remains open. |
| A11Y-01b date semantics | Small source change, moderate interaction/native risk; follows A or separate reviewed commit | Native date role/default activation plus regression evidence. Does not by itself close keyboard access. |
| A11Y-01b keyboard/lifecycle | Moderate, baseline-dependent | Native traversal/focus/routing design and evidence; remains open until the specified outcomes are demonstrated. |

No user clarification is needed to plan A11Y-01a. Remaining uncertainty is native behavior and the keyboard traversal policy for A11Y-01b. Proposed roadmap wording after Slice A acceptance: “Names, pill state and icon targets accepted at recorded evidence levels; date native activation and keyboard/focus lifecycle remain open.” Do not mark the entire A11Y-01 row complete or allow these design artifacts to imply UX-01 has passed pending CI/native gates.
