# Glimpse roadmap — November 4, 2026

Reported bugs lead the current rollout. New feature work is paused until the bug bundle ships. QA and release investigation run in the separate **Glimpse QA and release verification** chat. No date below is a shipping promise.

| Priority | Deliverable | Current state | User benefit |
|---|---|---|---|
| Delivered | One categorized Settings page | v1.4.24/build31 published and installed; Settings open, scroll, preview and reopen checked | Settings stays in a separate window; no tabs or calendar expansion/jump |
| Now | Reported UX bug bundle | v1.4.26/build33 implementation accepted within documented scope; footer/Quit and refined About images UX-reviewed; native actions pass; exact-staged Quality and delivery pending | Clear calendar surface/text, five equal footer actions, full-cell hover, visible separators, compact Quit prompt, scoped update focus styling and short-screen Settings clearance |
| Paused | Show remaining loaded events | Source implemented and independently reviewed; native acceptance pending | Reach events beyond five without another calendar request; collapse from the same button |
| Paused | Jump directly to a known date | Source implemented and independently reviewed; combined native acceptance pending | Enter Gregorian YYYY-MM-DD locally in the existing field; phrases retain AI behavior |
| Reliability | Crash/disappearance, restart launch and performance | Diagnostics available; original other-Mac crash unreproduced; real restart deferred by user | Reliable availability and lower resource use, measured rather than assumed |
| Research | Useful event actions | No permitted exact-event/occurrence reveal API found; Open Calendar remains the app launcher | Truthful Calendar launch; exact-event navigation is not promised |

## Release status

The official installed/public app is [v1.4.24/build31](https://github.com/iRedlof/Glimpse/releases/tag/v1.4.24), canonical source `a283ca697c6885893c5abbd5ba0c217277472688`. Its signed public artifacts and installed Settings behavior were verified.

The unshipped readability candidate passed its bounded local acceptance, but PR32's original push and pull-request Quality runs failed native window ownership. Those failures are retained. The current bug bundle inherits its readable surface and adds the requested footer, confirmation and About changes. Earlier readability acceptance does not establish acceptance of the new bundle.

Corrected native footer/Quit/lifecycle checks passed twenty products. The first two passing About keyboard products were visually rejected; the refined About-only 1pt/key-window outline then passed both light/dark native products and direct full-view UX review. Original admission failures and rejected images remain retained. Bounded product/UX/code/QA implementation acceptance is established; exact-staged whole Quality, protected delivery, signed artifacts and installed hover/after-captures remain pending. Predicates/timeouts remain strict. See [bug-bundle acceptance](superpowers/reviews/2026-11-04-footer-bug-bundle.md) and [bounded earlier readability evidence](superpowers/reviews/2026-11-04-calendar-readability-acceptance.md).

## UX feedback loop

1. Preserve the user's actual screenshot and exact complaint.
2. Give UX the image; examine glance reading, low vision, keyboard use, first-time discovery and native light/dark appearance.
3. Implement the focused correction and capture the actual production view from that source.
4. Have UX review those pixels, then verify relevant interaction and installed appearance before calling the rollout delivered.

The current four light/dark normal-footer/compact-Quit images passed direct UX review. They are synthetic offscreen hosting renders, explicitly separate from installed desktop proof. Background validation is necessary delivery work and does not count as a shipped feature.
