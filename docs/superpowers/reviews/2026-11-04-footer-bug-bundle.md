# Reported UX bug bundle — v1.4.26/build33

Status: implementation accepted within the scope below; exact-staged Quality and release delivery pending. The official installed app remains v1.4.24/build31.

The user reported a washed-out calendar, inconsistent footer actions, an excessive update-button focus border, excessive Quit-confirmation spacing, and poor footer aesthetics. Their reference requests a connected full-width bar with full-cell hover; it does not request the reference app's orange color. Reported bugs take priority, with Show more and direct-date feature work paused.

## Implementation

- Inherit the opaque adaptive calendar surface and stronger text from the unshipped readability candidate.
- Give Quit, About, Pin/Pinned, Calendar and Settings equal 44pt-high cells, consistent captions and native symbols, short visible separators and full-cell transient feedback.
- Keep confirmation in the same footer height, with adjacent 28pt Cancel/Quit buttons and no elastic gap.
- Preserve native Button/Link focus while replacing the stock About-action halo with an About-only 1pt inset outline, visible only while its own window is key. Calendar/footer focus stays 2pt.
- Reserve the full native scrollbar width only when the calendar overflows, preserving Settings containment and edge clicks on short screens.

Independent A1–A8 production source review and narrow overflow/separator addenda found no confirmed production defect. Three final production hashes were reviewed. Release metadata and the five-file native-fixture correction have also received independent source review with no remaining actionable finding.

## Verified scope

Final focused ordinary checks passed 17 methods and 97 argument products with zero failures, skips or runtime warnings. They cover 13 footer/header products, 12 viewport products and 72 About semantic products. The three original legacy-scrollbar overlap/action failures now pass with their original predicates.

The same-root production calendar render check passed two light/dark products: normal footer, opening confirmation through the owned accessibility action, and Cancel recovery. It verifies stable panel/bounds, 28pt buttons, 8pt interbutton spacing, prompt adjacency and zero protected external effects. UX directly viewed all four normal/confirmation images and found no blocking visual issue.

These are synthetic offscreen hosting renders, not installed desktop captures or keyboard-focus proof. Earlier 38-state calendar renders predate the final separator correction and remain qualified earlier-source evidence.

One subsequent serialized keyboard diagnostic cohort passed all 41 methods / 94 products. All 15 footer windows acquired exact key ownership, and all 18 lifecycle/Quit control queries found one owned match. This run retained one runtime QoS warning and did not reproduce the earlier admission failures. It does not establish their historical cause or cover the newly mandatory About focus check.

The native fixtures now explicitly activate ordinary footer and About windows, matching production presentation, and initialize their owned accessibility tree before root-control queries. The About keyboard check has moved into the existing mandatory keyboard suite, making its manifest 42 methods / 96 products. Native assertions and the 30-second limits remain intact; the tooling fixture and receipt expectations use the same complete manifest.

The corrected focused native run passed four methods / 22 products with zero failures, skips or runtime warnings. It covers all fifteen footer actions/key combinations, three Quit key combinations, two lifecycle cases and two About appearances. Its About captures were visually rejected: the 2pt outline still dominated the small action, and the initial nonkey captures retained control focus and were byte-identical to the key captures. This prompted the About-only 1pt/key-window refinement below; the earlier keyboard pass is retained at its original source scope.

The final About-only refinement passed both light/dark native products with zero failures, skips or runtime warnings. Full production About captures show a focused enabled Check action in the key window, a visibly slimmer 1pt cue, and no cue in the nonkey state despite retained logical focus. Native Space invokes the injected check exactly once. UX directly reviewed all four full-view captures and their metadata, accepting the focus correction and stable 300×290pt layout without clipping, overlap or displaced controls. These remain hosting captures with transparent backgrounds, not installed compositor screenshots.

The About-only refinement received independent A1/A3/A7/A8 source review with no actionable finding. Shared calendar/footer focus remains 2pt; native Button/Link eligibility and routing are preserved. The final run's wrapper omitted an empty keyboard-staging retain marker, causing collector cleanup to exit 1 after a zero-error receipt. That wrapper error is retained and is not reported as a successful collection phase. All eight About files were separately copied and hash-verified after exact test-host absence; no native test was retried. The ordinary Quality controller already creates its retain marker.

## Bounded role acceptance

- Product: the next candidate addresses the user's reported calendar/footer/About bugs; new-feature rollout remains paused.
- UX: calendar readability retains its earlier bounded acceptance; current normal/Quit renders and refined full-About light/dark focus renders are accepted.
- Code: independent production reviews and the final About/fixture addenda report no remaining actionable source defect.
- QA: the relevant ordinary geometry/accessibility/semantic scope, native footer/Quit/lifecycle scope and refined About activation/captures pass. Existing 239 tooling checks pass with the complete 42-method/96-product manifest.

These reviews accept the implementation at the stated scope. Exact-staged whole Quality, required hosted checks, protected integration and signed release verification remain separate mandatory gates.

## Open acceptance gaps

- The original twenty footer and two About native admission failures remain retained. Corrected focused native ownership/actions now pass; historical causes remain unproved.
- Full-cell native hover, current-source whole Quality, hosted required checks, signed release artifacts and installed behavior remain unverified.
- The original other-Mac crash cause remains unknown. The user deferred a real machine restart; enabled login registration does not prove restart launch.

Original failed results are retained. No ownership guard or timeout was weakened, and no failed release is marked successful. QA runs in the separate verification chat. Installation and delivery are not accepted until the corresponding gates and live checks complete.
