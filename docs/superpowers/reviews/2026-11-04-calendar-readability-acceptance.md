# Calendar readability — v1.4.25 / build 32

Accepted for **bounded release preparation** on November 4, 2026. Publication and installation are still separate gates. The latest accepted public/installed version at this checkpoint is v1.4.24/build31, canonical source `a283ca697c6885893c5abbd5ba0c217277472688`.

The user's calendar looked washed out. This change gives its body and caret the same opaque adaptive surface, strengthens essential and supporting text, makes Today/selected-date/Quit labels readable, clears the search focus outline from its label, and adjusts essential Light accent marks while retaining the native Dark accent. Calendar layout, control ownership, provider policy, permissions and the delivered single categorized Settings page remain preserved. Show more and direct date entry are separate forthcoming features.

## Accepted scope and independent reviews

| Role | Accepted evidence and boundary |
| --- | --- |
| Product | Independent Product accepts this small visible paint correction using all 19 paired Light/Dark full states and three real active/inactive desktop conditions. Its final UX condition is satisfied by the report below. The broader application/document backdrop matrix remains explicitly pending. |
| UX | Independent final review reports zero Critical, Important or Minor visible findings. All 150 fresh PNG/JSON pairs were identity-checked; all 88 distinct PNG hashes were directly reviewed: 36 full documents, 32 constrained row/footer images and 20 semantic images. Separately reviewed actual desktop, Yellow-accent and accessibility-setting captures retain their own scope. |
| Code | Independent A1–A8 review reports zero Critical, Important or Minor findings for the three final production files against delivered Settings. Fixture-only manual sizing and placement were separately reviewed; production geometry and actions are unchanged. |
| QA | Complete unmodified working-source Quality passed. Fresh final-source render methods and six actual desktop cases passed. Final technical QA supports release preparation conditional on this accurate scope, final UX and mandatory exact-staged checks. Those first two conditions are satisfied; staged checks remain mandatory. |

Root accepts the four roles **for the stated release scope**, after reading their terminal reports, verifying the complete frozen source and sealed evidence, and independently recomputing the current bounded text samples. This does not declare an unexecuted check passed or substitute earlier release evidence for this candidate.

## Exact source

The reviewed base is `a283ca697c6885893c5abbd5ba0c217277472688`, tree `b172d0424b52e20fcc5a0c58c36121693d8b57bb`. The working-source Quality/render freeze contains 236 inputs, manifest SHA-256 `d215368ea9f27f0e702d6ff0bbccc2da11dfb0f40e8d55126e3f60e77c2f8202`. Final release metadata/documentation are prepared afterward and must pass the normal exact-staged hook.

| File | SHA-256 |
| --- | --- |
| `Glimpse/AppDesign.swift` | `8dd217a5c591a6d63c39a42cf4f158bc0a054588d2fbf5146a88a82bf9aaaf6b` |
| `Glimpse/CalendarPopoverView.swift` | `5ff542c7a5023ef61fbaa8a299747ad32833e1c35749c25e1f24443e5ed95889` |
| `Glimpse/CalendarKeyboardFocus.swift` | `e095a41f0a3f1261bc02b0410307421fbe45d328082cd1a46a48cee75ed0fa65` |
| `GlimpseTests/AccessibilityViewportTests.swift` | `67bd2b421ccc61f989b3972e92a3476d2f8477a8841ba8f1cbbec84cf97d8290` |
| `GlimpseTests/AppDesignTests.swift` | `1f200c364e6db974760b81bc21937c63b54800293f7b0ee18897c2fd40aa96e6` |
| `GlimpseTests/CalendarControlAccessibilityTests.swift` | `66248e8517dfaf74eff7febaba4b1ab0f9838dcbe5e898eeab733e8b72dc4b4f` |

## Observed acceptance

- Full Quality returned actual exit 0: tooling 239 tests and monitoring 27 passed; ordinary App 269 methods/717 observed passed products, with 66 accounted-for native opt-in skips; Core 70 methods/86 observed products in five suites passed. Mandatory keyboard 41/94, AI 8/17 and Agenda 13/23 each passed without failures or skips. All 52 required copied native artifacts and both dependency lockfiles were verified.
- The three existing final-source render methods passed 46 parameter cases, without failures or skips: 38 full-state, four constrained-row and four semantic cases. They produced 38 full documents, 72 row/footer images and 40 semantic images. All 150 PNG/JSON pairs were verified.
- The 19 full scenarios cover selected result/empty/loading/query-error, today/no selection, multiple events, authorization/status/error, open/closed search, AI processing and AI error states in Light and Dark. Both existing scroller styles reveal required agenda rows and footer controls within the 312-point cap.
- Semantic images distinguish today's fill, another/outside-month selection circle, logical grid focus, enabled/disabled Today, search/header/footer and Cancel/Quit focus. Actual metadata has 32 key and eight non-key images, all with the app active. Peer-named focus/confirmation aliases do not establish non-key confirmation or app inactivity.
- Six real compositor cases each passed: original Black/Dark Multicolor, Silver/Light Yellow and patterned Macintosh/Light Yellow, each active and genuinely app-inactive. These are three paired conditions, not a theme-by-background cross-product. The matched synthetic panels remain 316×454; active cases bind physical Tab input and activation/refresh completion, inactive cases use no injected input. Protected and invalid effects remain zero.
- Retained real Increased Contrast and Reduce Transparency evidence has both settings ON and native Brown accent. Its prior fixture differs only in reviewed horizontal placement; this is qualified evidence, not a fresh independent four-way toggle matrix.
- All 168 current-source bounded text samples across 34 role labels meet 4.5:1, minimum **4.66068978:1**. Root independently reproduced their fixed-region foreground/background counts and ratios from 64 sealed originals after embedded-profile conversion to sRGB. White Quit focus samples exceed 3:1; Light and Dark desktop essential marks exceed 3:1 at their measured solid cores. Antialiased edges and whole-app AA are unclaimed.
- Final UX finds readable text, intact wraps, distinct focus/selection/disabled states, clear body/caret and reachable footer controls. One-page Settings continuity is source-verified; separate live installed v1.4.24 Settings checks remain evidence for that delivered version.

## Explicit scope decision and remaining limits

Product, UX and root accept the observed full-state and controlled desktop evidence as proportionate for this opaque-surface and paint-only release. **The original broader matched bright-document/dark-app/full-state backdrop matrix remains pending and unproved.** It is retained as background QA work rather than labeled passed. Opacity and the observed interior isolation explain this bounded scope decision; they do not supply missing imagery. A newly demonstrated defect requires targeted correction.

Two native QoS priority-inversion warnings remain in the passing keyboard/AI cohorts. No performance repair follows from their passing results.

The original other-Mac disappearance is unexplained, and the user deferred a real restart. Physical VoiceOver/Full Keyboard Access across supported OS versions, older macOS/Intel, endurance, all accents/backgrounds, arbitrary long event titles and live provider/TCC behavior are not certified here. No production automatic-sizing repair is claimed by successful manually sized fixtures.

The [earlier contrast development record](2026-11-03-calendar-contrast-acceptance.md) retains the original 3.407:1 Light empty-text RED, later weak-label/focus/Yellow REDs, exit-65 timeouts, external capture-file block, activation-fetch mismatch, Sendable compiler failure, acknowledgment misses and geometry failures. Those failed runs remain failed; later passing captures do not explain every original cause.

OS appearance and both original Black wallpapers were restored. Installed v1.4.24 remained running. Finder remained minimized and Preview hidden after background preparation; exact original document visibility was not proved. Protected UserNotificationCenter was untouched.

## Retained report identities

Reports and private/synthetic native images remain outside tracked source in the retained `settings-delivery-integration.clgw7zwe` evidence directory. File names and SHA-256 values identify the exact reports:

| Evidence | SHA-256 |
| --- | --- |
| `calendar-readability-product-acceptance.xq77kxdg/PRODUCT-ACCEPTANCE.md` | `63aa80d283d5adfdf62f9b2b50e086ce36e24ecb7eb9059d2937a4923055fd02` |
| `calendar-final-source-ux-adjudication.oocp42yp/FINAL-UX-REVIEW.md` | `2a4af41d6b917de15d59135e177648fbe322db59d92c43b0fde36c77c099701e` |
| `calendar-readability-final-code-review.8dd217-5ff542-e095a4.md` | `01594d566fd0c3e6b839a9f93a1f05e72077dd6b4b2f19d50fd0740b96e375a7` |
| `calendar-final-qa-adjudication.4q5fnq1x/STOPPED-FINAL-QA-ADJUDICATION.md` | `df733aec3595126b3bcb722c0bc0bee9ae3cdb139faff475a364cba63b69fd43` |
| `calendar-v1425-complete-quality.ftb4aifp/STOPPED-FULL-QUALITY-HANDOFF.md` | `03df620a30e383b093d34b4823435ddec685380e29d6ffd7ecaaf5781deef6b1` |
| `calendar-final-source-three-renders.1gwxkbv3/STOPPED-FINAL-RENDERS-HANDOFF.md` | `5884ecce9152f90e61825e7acf6c5ee40bd091743d360dd2617db429c9860eef` |
| `qa-quarter-desktop-preflight.jw5ts4cz/STOPPED-DESKTOP-HANDOFF.md` | `e721511ce48372e8f4e97afe66ad56315666c7cc38ca6cbd61a8b192f69d94ea` |

Root independently verified all 5,068 Quality, 432 final-render and 340 desktop sealed files, including their recorded byte counts and modes. These working-source records do not replace **normal exact-staged precommit, fresh protected PR admission, terminal exact-source Release/Recovery as applicable, independent signed public artifact verification, recoverable official installation and an actual installed after-capture**. Complete those before describing v1.4.25 as delivered.
