# UPD-03 update-guidance acceptance

2026-11-02. Candidate **v1.4.12/build 19** on `codex/update-guidance`.

**Status: implemented; focused driver, About action and full-view visual evidence accepted. Candidate whole-source quality, independent A1–A8 review, protected integration and delivery remain pending.**

## User-visible behavior

About distinguishes an installed version newer than the feed, macOS too old or too new, an Apple silicon requirement and an unknown no-update result. Each provides Check for Updates and the fixed official View Releases link. Valid optional macOS requirements appear as detail; malformed/missing detail is omitted without losing the reason.

Explicit latest says “No newer update was found,” retaining its green presentation and five-second expiry. Other results persist through native dismissal and About recreation until a new check/native phase or process end. The result is not persisted to settings.

The [accepted design](../specs/2026-11-02-update-guidance-design.md) records the exact copy, requirements and team-owned product decisions. The [implementation plan](../plans/2026-11-02-update-guidance.md) records execution and remaining delivery steps.

## Source and verification identity

- Base main: `1ee8f7ec96c524544cd089aae635488b46c40737`.
- Scoped driver commit: `c8292523791547c4ff4132bc500c430a4f67a7c5`; its normal hook tested exact staged tree `d33129781723590146ab7ef4fb7d162ae1e921ea`.
- Candidate UI/readiness/version work follows that commit. Both lockfiles remain unchanged; 15 matching app/Core pins include Sparkle 2.9.4.
- Core, calendar/AI behavior, production feed, signature verification, startup preferences and permissions are outside this change.

Retained evidence lives under `build/validation/update-guidance-implementation.bpo8vktn/` in the shared build root. JSON acceptances retain source/pin identities and artifact digests. These files are not shipped with the app.

| Gate | Observed result | Evidence |
| --- | --- | --- |
| Driver RED | Original non-latest/untrusted callbacks falsely claimed latest; stronger tests also exposed reason, metadata, numeric and terminal-gate regressions | `task1-red-1` through `task1-red-3` receipts/logs/xcresults |
| Driver precision regression | First GREEN exposed an `NSDecimalNumber` fraction rounded to latest; Foundation probe reproduced comparison precision loss | `task1-green-1`, `decimal-reason-comparison-probe.*` |
| Final driver GREEN | 32 named tests / 151 cases; zero failures/skips/xcresult runtime warnings | `task1-green-2`, `task1-focused-acceptance.json` |
| Driver normal whole-quality hook | 459 named tests: app197/461 cases, Core70, tooling165, monitoring27; zero failures/skips | `task1-commit-run`, `task1-hook-quality-summary.json`, `task1-whole-quality-acceptance.json` |
| About behavioral RED | 3 names / 12 cases failed on expected reason/detail/latest copy; eligibility freshness already passed | `task2-red-1` |
| Final About GREEN | 11 named tests / 72 cases; zero failures/skips/xcresult runtime warnings | `task2-green-2`, `task2-focused-acceptance.json` |
| Actual full About rendering | 36 light/dark reason/detail/eligibility cases; width300, actual fitting/content height332–413; text/control bounds visible and nonoverlapping | `task2-renders-2`, `task2-render-manifest.json` |
| Visual review | Lead inspected all 36 layouts in contact sheets1–3; header, wrapping, actions, diagnostics and footer fit | Original transparent PNGs retained; contact sheets use neutral light/dark backgrounds for inspection |
| Candidate metadata/pins | Four marketing versions1.4.12, four build numbers19 and README badge synchronized; version and dependency checks passed | `task2-version-before.json` plus final whole-quality metadata check still required |

Named tests and parameterized cases are distinct counts. Focused gates overlap the whole gate and must not be summed as unique whole-product coverage.

## Acceptance mapping

| Design criterion | Evidence / remaining boundary |
| --- | --- |
| 1. Reason/state/copy matrix | Genuine SDK-domain/code/reason callbacks plus owned rendered About copy/actions |
| 2. Latest-only deadline and persistent guidance | Controlled actual driver delay, cancellation, native dismissal and About expiry/reopen |
| 3. Safe malformed metadata handling | Bool, fractions including high precision, non-finite/overflow/future values; real public item adapter; validated optional details |
| 4. Fresh admitted check | Driver observation/live disagreement and actual owned accessibility presses; rejected stale presses cause no backend call |
| 5. Replacement freshness | Reentrant acknowledgement, old delay return, new checks and native presentations |
| 6. Callback/choice ownership | One acknowledgement, pending UUID preservation, matching consumption, disabled/old controls |
| 7. About reopen and official link | Recreated view preserves state/I/O/UUIDs; actual link press records only official releases/latest |
| 8. Readable text and valid actions | Owned accessibility roles, names, values, enabled sets and geometry; physical VoiceOver/keyboard unperformed |
| 9. Full light/dark fit | Actual injected production About view, complete header/diagnostics/footer, optional and 32-character details, disabled footnote; signed native fit unperformed |
| 10. Scope and delivery gates | Pins/security/settings preserved at current source; candidate whole gate/review/integration/public/install verification pending |

## Fixture investigation and diagnostics

The first full-view run and a stage probe timed out at30 seconds while creating a render-output directory on the external volume. Layout/accessibility had completed. The exact owned test-host sample shows `FileManager.createDirectory` → `_mkpath` → `mkdirat`; the Xcode timeout attachment itself contained no samples.

Changing artifact output to the test app's ordinary temporary directory passed all36 cases. Temporary stage markers were removed, and the complete About suite passed again. Exact reported artifacts were copied into validation storage. No production sizing, sandbox/TCC permission, official feed or installed-app setting was changed. The deeper filesystem cause was not inspected; this is not evidence about the original reported crash.

Expected public `SUAppcastItem(dictionary:)` deprecation is retained: the fixture exercises scalar min/max metadata only, not system-dependent compatibility flags or native feed selection. Existing Sparkle nil-coalescing, CalendarPanel activation and `linkd.autoShortcut` diagnostics remain in the normal driver-hook log. No xcresult runtime warning was reported in the focused gates. Earlier retained AppKit accessibility diagnostics and their unknown production effect remain open.

## Native and delivery limits

These are unsigned owned fixtures on macOS27.0.1/arm64. They do not establish real incompatible-feed selection, Intel eligibility, older macOS behavior, physical keyboard/VoiceOver, real retry/install/relaunch or signed native About fit. Intel acceptance requires Intel hardware; translated execution on Apple silicon is insufficient. Official feed/security settings remain unchanged.

Latest verified public/installed distribution remains **v1.4.11/build18**. Candidate1.4.12 is not released. Whole quality, independent review, protected admission, terminal exact-source Release/Recovery, public signed/notarized DMG/appcast verification and official installation/launch must be recorded separately before delivery is claimed.

The user's other-Mac termination is unexplained, restart testing is user-deferred, and controlled performance/endurance acceptance remains open.
