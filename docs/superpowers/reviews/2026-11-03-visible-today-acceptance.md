# Visible Today candidate acceptance

2026-11-03 UTC. Candidate **v1.4.18/build25**, branch
`codex/calendar-today`, based on verified v1.4.17 source
`aa6009abf6c9ec46f21e66807d1a0ae635dddeae`.

**Product, UX, focused QA and independent source review passed at the
boundaries below. Exact staged-source quality, protected integration, signed
public delivery and installed interaction remain pending. This candidate is
unshipped.**

The calendar header now has a visible **Today** button in a quiet neutral
background. Its native target is at least 48pt wide and remains 28pt high.
The existing action, disabled predicate, keyboard ownership, accessibility
name and focus outline are preserved; native help says “Go to today.”
The two adjacent month controls retain their 28×28pt targets.

Only an obsolete view/fixture presentation input was removed. The reducer's
current-month predicate remains in use. This change does not modify panel
geometry, event queries, AI, preferences, permissions, startup or shortcuts.

| Boundary | Accepted evidence |
| --- | --- |
| Behavioral regression | Meaningful RED failed the new width/help checks. The affected five-suite GREEN passed 25 methods/79 executed cases, without failures or skips. |
| Native root states | The complete isolated keyboard ownership suite passed 14 methods/16 cases. The existing Today test additionally observed today's selection, another current-month selection, no selection and an away month in light/dark. Actual enabled actions dispatched once; disabled actions did nothing. Eight full-root native images were inspected. |
| Long titles | Current final test source passed both existing action methods/five cases, including a finite 96-title matrix: all twelve months, years 2026/9999 and explicit English, German, French and Finnish locales. Each exact native heading fit on one line inside the owned host and did not overlap controls. All 96 PNGs were copied with matching hashes and inspected in aspect-preserving contact sheets. |
| Accessibility and pointer behavior | Original Button order, native roles, five edge/center click positions, exact one-action receipts, disjoint targets/gaps and disabled Today no-op assertions remain. The month title retains its native `AXHeading` role. |
| Independent code review | The original four-file A1–A8 review, fifth-file observation supplement and final title-role supplement bind all five current source files. Zero Critical, Important or Minor findings remain. |

Evidence is retained outside tracked source under
`build/validation/diagnostics-fixture-implementation.yucljzsb/`.
The execution packet is `today-ux-execution.uskixy2m/`; root acceptance records
are `root-native-and-five-file-acceptance.json` and
`root-title-and-grid-design-acceptance.json`. The final independent supplement
is `today-ux-title-native-role-review.xvr3ks9v/review.md`.

The title fixture uses its actual native component rendering and default
appearance, with a transparent background. It is separate from the eight
light/dark full-root material renders and from the signed installed app.
All initial matcher, compilation and artifact-forwarding failures are retained.
The initial vertically stretched contact derivatives were excluded; acceptance
uses the original bitmaps and aspect-preserving native-scale contacts.

The existing native editor QoS warning remains recorded. A passing Today
run does not explain the failed maintenance candidate's earlier panel setup
checks. Full local and hosted quality gates remain mandatory.

Latest verified public/installed distribution is v1.4.17/build24.
Physical VoiceOver/keyboard checks, macOS14/Intel, real EventKit/cloud
interaction and longer endurance remain separate. The original other-Mac
crash is unexplained; the real restart check is user-deferred.
