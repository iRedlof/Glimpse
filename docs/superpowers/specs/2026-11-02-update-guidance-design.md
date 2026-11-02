# UPD-03 — update guidance design

2026-11-02 · Lead-accepted design after independent builder review.
**Status: accepted for implementation planning and execution under the autonomous master goal.**
The lead accepts the marked team calls; the human user has not supplied or approved their detailed copy. Exact-source quality, independent review and delivery gates remain required.

## Intent and evidence

A deliberate update check should explain why nothing can be installed and offer a useful next step.
Today every `showUpdateNotFoundWithError` input becomes the green latest result for five seconds.
That source-confirmed behavior loses Sparkle's newer-version, OS, hardware and unknown reasons.
Official-feed exposure, incident frequency and real incompatibility reproduction remain unverified.

This design reuses the retained UPD-03 product investigation and source/SDK hash evidence under `build/validation/accessibility-implementation.xeeb2lu6/upd03-product-discovery/`. The independent builder-reviewed draft has SHA-256 `0d5df28b49568587f372ce918772b835c37bf638f8bc428c06792b9d88c68ab7`; the externally accepted design has SHA-256 `dacd6f7830bf431b61a7162c878d0d8936599479225fb41f638f7df37fef1c4c`.
Inspected source is candidate `6c8d3d566260e1fe64cbf7a09693f5b4f6db6c5f` in `/Users/rohit/.codex/worktrees/stability-ux/Glimpse`.
The lead reports the same source tree is now main `1ee8f7ec96c524544cd089aae635488b46c40737`, tree `51a8820a1918e4a5cb2fccc6159c19ef3b3fc2ab`.
The lead also reports v1.4.11 publicly verified and officially installed; this drafting pass does not re-verify delivery.
No app/update/UI operation, build, test, dependency installation or external mutation is part of this pass.

## Goals and non-goals

- Preserve the six declared no-update meanings and provide a safe fallback for absent/malformed metadata.
- Preserve existing `.latest` behavior for Sparkle's explicit latest reason.
- Keep actionable non-latest guidance visible without weakening UX-02 freshness or native callback ownership.
- Reuse the existing About section, guarded check control, official release link and design tokens.
- Cover reason classification, transitions and About projection with meaningful fixtures before any later integration.

This slice excludes information-only/major upgrades, release notes, cancellation, progress redesign and termination retry.
It excludes feed/channel/server changes, updater configuration, signature bypasses and direct compatibility downloads.
It excludes startup/crash diagnosis, calendar behavior, restart validation and the external AI proxy.
No additional platform, package, persistence layer, update center or settings deep link is needed.

## Selected approach and team calls

**Our product call:** keep explicit latest transient; make every other no-update reason persistent and neutral.
**Our UX call:** show Check for Updates plus View Releases; explain OS recovery in text.
**Our engineering call:** project NSError into small value state; treat the SDK reason as authoritative.
**Our scope call:** keep current English copy conventions; use `No newer update was found` for the explicit latest result.
**Lead revision:** this reports the actual check outcome without claiming equality with the newest global release.
These are proposed defaults for review, not statements that the user approved the detailed behavior.

Rejected alternatives: a generic message still hides recovery; raw SDK alert prose is long and can overclaim latest.
Handling only an old OS leaves other declared reasons misleading; a complete update center expands this small slice.

## Platform and dependency constraints

Target the existing macOS 14+ Swift 6 AppKit/SwiftUI app; GlimpseCore and the proxy need no change.
Preserve both immutable lock graphs, including Sparkle 2.9.4 at `b6496a74a087257ef5e6da1c5b29a447a60f5bd7`.
The inspected retained Sparkle framework is 2.9.4/build 2059; no SDK upgrade is proposed.
Preserve HTTPS feed, EdDSA key/verification, permission response, profile-collection behavior and release settings.
All driver mutation and native reply handling remain on the existing main-actor boundary.
Use one engineer as source owner for the updater/About files; independent review follows implementation separately.

## Swift-facing state and classification

Proposed internal names below are our engineering defaults; renaming them cannot change the behavior contract.
Declarations only are specified here; no implementation bodies or source edits are included.

| Surface | Shape |
| --- | --- |
| `UpdateNoUpdateReason: Equatable` | Cases: `unknown`, `newerThanFeed`, `systemTooOld`, `systemTooNew`, `requiresAppleSilicon`. |
| `UpdateNoUpdateGuidance: Equatable` | `reason: UpdateNoUpdateReason`; `requirementVersion: String?`, copied validated display data. |
| `UpdateStatus` | Add `.noUpdate(UpdateNoUpdateGuidance)`; retain `.latest`, `.error(UpdateFailure)` and all existing phases. |
| `InlineUpdateDriver` | Internal classifier `noUpdateStatus(for: Error) -> UpdateStatus`; callback exercises this boundary in tests. |
| `AboutUpdateSection` | Deterministic reason-to-copy projection; reuse existing text/check/link helpers. |

Trust a reason only when NSError domain equals `SUSparkleErrorDomain` and code equals `SUNoUpdateError`.
Read `SPUNoUpdateFoundReasonKey` as a valid boxed integral SDK enum value using exported constants/cases.
Reject Bool, fractional/overflowing numbers, strings, NSNull and future raw values; never truncate into latest.
Only trusted `OnLatestVersion` maps to `.latest`; every invalid/untrusted case produces guidance with reason `unknown`.
Do not infer a reason from localized text, underlying errors, display-version equality or machine architecture.

| SDK reason | Projected state | Optional item field |
| --- | --- | --- |
| `OnLatestVersion` | `.latest` | None; missing item is allowed. |
| `OnNewerThanLatestVersion` | `.noUpdate`, `newerThanFeed` | None. |
| `SystemIsTooOld` | `.noUpdate`, `systemTooOld` | `minimumSystemVersion`. |
| `SystemIsTooNew` | `.noUpdate`, `systemTooNew` | `maximumSystemVersion`. |
| `HardwareDoesNotSupportARM64` | `.noUpdate`, `requiresAppleSilicon` | None. |
| `Unknown` or defensive fallback | `.noUpdate`, `unknown` | None. |

Read `SPULatestAppcastItemFoundKey` only when it contains an actual `SUAppcastItem`.
Missing/wrong-type item data omits detail; it never changes a valid reason to latest or to another reason.
**Our display-validation call:** trim outer whitespace; accept one–three ASCII numeric components separated by periods.
Require at most 32 characters after trimming, nonempty components and no internal whitespace/control characters.
Otherwise set `requirementVersion` to nil. Validate display data only; do not compute OS eligibility.
Copy the applicable field during the callback; retain neither NSError nor SUAppcastItem as observable UI state.
Do not add candidate display/build versions; Sparkle ordering uses build numbers, which can share marketing versions.
`SPUNoUpdateFoundUserInitiatedKey` introduces no new UI policy; preserve the existing callback-driven presentation.

Public headers define the reasons/optional item; pinned implementation confirms NSNumber payloads and domain/code.
Pinned Sparkle acknowledges then asynchronously dismisses/aborts; preserve guidance through that dismissal.
Its latest reason can also mean no applicable item exists in the feed, including channel/platform filtering.
The internal `.latest` model remains; its proposed headline reports the check outcome without claiming global release equality.

## Exact proposed copy and controls

Copy below is our product/UX default. Non-latest uses primary headline and secondary wrapped detail/recovery text.
Keep the existing 300-point About window, centered text, AppDesign spacing and action padding.
**Our visual call:** no additional icon for non-latest; text alone avoids a new color-only status distinction.
Retain the existing green check icon/text for `.latest`, with its decorative icon accessibility-hidden.

| Result | Headline | Optional detail | Recovery |
| --- | --- | --- | --- |
| Latest | `No newer update was found` | None | None. |
| Newer than feed | `You’re running a newer version.` | None | `Your installed version is newer than the version in the update feed. You can keep using this version.` |
| OS too old | `This update needs a newer macOS version.` | `Requires macOS {minimum} or later.` | `Check Software Update in System Settings, then check again.` |
| OS too new | `Your macOS version is newer than this update supports.` | `This update supports up to macOS {maximum}.` | `View releases for compatibility details, or check again later.` |
| Requires Apple silicon | `This update requires Apple silicon.` | None | `It can’t be installed on this Intel Mac. View releases for compatibility details.` |
| Unknown | `No installable update was found.` | None | `Check again or view Glimpse releases on GitHub.` |

Show exactly two controls for every non-latest result:

- **Check for Updates**; accessibility label **Check for updates**; existing `updater.checkForUpdates()` admission.
- **View Releases**; accessibility label **View Glimpse releases on GitHub**; existing fixed official destination.

Destination: `https://github.com/iRedlof/Glimpse/releases/latest`.
When Check is disabled, keep the link enabled and add `Checking is temporarily unavailable.`
No install/skip/relaunch/dismiss action belongs to this result; ordinary check errors retain UX-02's Retry UI.
The OS-old recovery route is System Settings → General → Software Update, expressed in text without a new button.
Do not promise an OS upgrade/compatible Intel download, advise downgrading macOS/app, or imply the link bypasses checks.

## Ownership, acknowledgement and expiry

| Event | Required behavior |
| --- | --- |
| Latest callback | Publish `.latest`, schedule the existing five-second delay, then acknowledge exactly once. |
| Other no-update callback | Publish guidance through the common cancelling `publish` path; no timer; acknowledge exactly once. |
| Native dismissal | Clear native pending replies/UUIDs as today; preserve latest/error/initialization/no-update terminal state. |
| About close/reopen | Preserve in-memory guidance; no new start/check/acknowledgement/timer merely from view recreation. |
| App restart | Normal initialization/idle; no no-update result written to UserDefaults. |
| Admitted Check | Publish `.checking` synchronously before native invocation; remove old guidance; second rapid press rejected. |
| Ineligible Check | Keep prior guidance; no backend check or reply consumption. |
| New native phase | Replace old guidance through common publication; the new presentation owns current state. |
| Old latest delay returns | Cancellation/current-status protections prevent erasing guidance or any replacement phase/new latest timer. |
| View Releases | Open fixed URL only; keep status/choice ownership; no check or additional acknowledgement. |
| Acknowledgement publishes replacement | Preserve it; no post-acknowledgement mutation may overwrite the new state. |

Non-latest results have no automatic deadline; persist until the next admitted check/native presentation or process end.
This describes the last check, not a permanently current compatibility claim; no extra dismissal preference is needed.
Add `.noUpdate` to allowed terminal check phases, retaining initialization/native eligibility/no-choice gates.
Re-read live native eligibility at invocation as today; observation alone cannot authorize a rendered stale Check.
Retain any native choice closure/UUID until matching consumption or Sparkle dismissal, even if guidance replaces its view.
No guidance action invokes an install, skip, relaunch or termination reply; old controls cannot consume newer identities.
Do not restart SPUUpdater, add an independent result timer, or relax existing active-phase protection.

## Acceptance criteria

1. All six current reasons and defensive fallbacks match the exact state/copy matrix.
2. Latest alone remains green and expires after five seconds; other results survive that interval and native dismissal.
3. Invalid reason/item/detail data never traps, produces raw/null prose or claims latest; missing detail remains useful.
4. Check admits only initialized, currently eligible, choice-free permitted phases; rapid/stale presses cannot duplicate I/O.
5. New check/native outcomes immediately replace guidance; cancellation and reentrant acknowledgement cannot overwrite them.
6. One acknowledgement per callback; pending choice identity/consumption semantics remain unchanged.
7. About reopen preserves guidance without additional start/check/ack; release link opens only the fixed official URL.
8. All result text is accessibility-readable; controls expose correct roles/names/enabled state and valid action sets.
9. Full About light/dark rendering fits wrapped copy, optional OS details and disabled footnote without clipping/overlap.
10. Source/pins/security/settings remain within scope; later exact-source quality, A1–A8 review and release gates still apply.

## Fixture plan and native limits

Reuse `UpdaterFixture`, `UpdateBackend`, `ControlledUpdateDelay` and `AboutUpdateHost`; no duplicate updater framework.
Latest fixtures must use genuine Sparkle-domain/SUNoUpdateError/explicit-latest metadata, replacing the arbitrary fixture error.
Keep the arbitrary error for ordinary failure tests and add its no-update-path unknown-fallback regression.
Cover each reason, wrong domain/code, missing/future/raw-type values, Bool-to-1 coercion and fractional/overflow cases.
Cover absent/wrong item, valid/malformed thresholds and conflicting item data without recalculating the supplied reason.
Cover latest↔guidance, all guidance replacements, cancelled delay returning successfully and reentrant acknowledgement.
Cover pending offer/ready choices, native dismissal/reopen, observed/live eligibility disagreement and rapid presses.

Use scalar-model tests plus one actual public-SDK item adapter fixture for copied metadata.
A deprecated public dictionary initializer may be used only for plain metadata, with an explicit limitation note.
Its system-dependent flags cannot establish compatibility; no private headers, KVC mutation or fake native item types.
If unsuitable, mark that adapter boundary pending for a controlled parser fixture; do not silently claim native coverage.
Owned About accessibility presses verify copy/actions/link receipts and state/I/O isolation; inspect full-window renders too.

Injected errors/rendered hosts do not reproduce real feed selection, Intel incompatibility, install/relaunch or VoiceOver.
Later signed native latest-check acceptance must observe real metadata, dismissal, expiry and restored eligibility.
Other reasons need a separate controlled native SDK/feed harness; never alter the official updater's feed/security settings.
ARM64-ineligible native acceptance needs Intel hardware; translation on Apple silicon is not equivalent evidence.
Physical keyboard/VoiceOver discovery and activation remain separate acceptance; source fixtures cannot prove those outcomes.
Existing real update/retry/install/relaunch, restart and calendar-native checks remain open at their recorded scope.

## Review decisions and remaining questions

No genuine unresolved user-behavior choice prevents planning this bounded slice under the proposed defaults.
Lead/builder review must accept or revise the marked calls: persistence, copy, fixed link/manual OS route and English scope.
Unperformed native cases and the SDK-item fixture boundary are validation dependencies, not invented product questions.
Lead acceptance permits the bounded implementation workflow; it does not claim implementation, tests, native acceptance or delivery.
