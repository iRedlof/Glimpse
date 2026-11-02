# Product inventory and validation boundaries

Updated 2026-11-02. This inventory describes discovered components; it does not imply access to their external operations. Current priorities live in the operating section of [stability-roadmap.md](stability-roadmap.md).

Glimpse provides a menu-bar calendar: open by click/shortcut, navigate/select a day, optionally show authorized events or enter an AI date query, configure presentation/startup/shortcut settings, pin the panel, and use About for updates/diagnostics.

| Component / platform | Dependencies and procedure | Verified status / boundary |
| --- | --- | --- |
| macOS app (`Glimpse/`) | Swift 6 complete concurrency, SwiftUI/AppKit, TCA, Carbon, EventKit, ServiceManagement, AppIntents. Xcode project/scheme Glimpse; macOS 14 deployment floor. | Latest verified public distribution v1.4.9/build 16/source7b1f1815, signed/notarized public artifacts and installed signature/launch accepted; installed fit/scroll interaction pending. Last accepted diagnostics/live-interaction baseline remains v1.4.8. Published arm64 DMG; Intel support was not separately verified. No additional client platform was discovered. |
| Local package (`GlimpseCore/`) | Calendar/preferences reducers, Sendable models and dependency clients. `swift test --force-resolved-versions`; shared app delivery. | Both locked graphs contain 15 matching immutable pins, including TCA 1.26.1 and Sparkle 2.9.4. Manifest minimums are not resolved versions. |
| Native presentation / local state | Reused NSPanel, single-image status renderer, focus/monitor lifecycle, UserDefaults and system-managed calendar/startup authorization. | Panel-fit source shipped in v1.4.9; installed physical checks remain pending. Update recovery is the current iteration. Existing resize/redraw guards remain necessary. Calendar records and stored secrets are outside routine discovery. |
| Shared AI proxy | Client's HTTPS date-query transport to the documented Auris proxy; 15-second request deadline. Optional FoundationModels on supported macOS 26+ systems. | Server source, operator access, deployment, upstream models and retention policy were not inspected. Client release deploys only the client. Auto proxy selection remains intentional. |
| About / diagnostics / updates | Sparkle latest-release appcast, standard chosen-destination save dialog and bounded current-process OSLog collector. | Real installed v1.4.8 export/save/reveal/repeat/cancel/update checks accepted. Matching retained logs were empty; earlier-launch history and useful retention remain unproven. |
| Shortcuts integration | AppIntents included in the macOS build. | No dedicated intent interaction tests were discovered. The intent's Show/toggle semantics remain a workflow hypothesis. |
| Quality / delivery | `tools/scripts/quality-gate.sh`, introduced-revision testing, GitHub Actions Quality/Release/Recovery, signing/notarization/Sparkle/public verification. | Latest accepted exact-main internal Release 41428111750/1 at main06e48b4; public app Release41415776521/2. CD-01 completed local quality/protected integration boundary correction. Every introduced revision is checked; this is distinct from full code-path coverage. |
| Availability monitoring | `tools/monitoring/health-check.py`; separately configured hourly thread monitor; timestamped process/crash/resource state. | Healthy unchanged observations stay quiet. Process presence does not establish a visible icon, successful login launch, zero future crashes or other-device reliability. |
| Alternate cask (`glimpse.rb`) | Homebrew descriptor in this repository. | Still v1.1.2 with an unchecked, reachable old ZIP. Current README advertises DMG only; no matching publisher was found among accessible public catalog/author/search taps. Separate retirement is recommended. Private/unindexed publication and actual usage remain unverified. |

Canonical whole-source check:

```sh
tools/scripts/quality-gate.sh
```

It checks tooling/monitoring contracts, synchronized versions and dependency pins, resolves locked versions, runs unsigned app and Core tests, and retains logs/xcresults. Development uses appropriate focused regressions first. Keep the existing test-host startup guard; fixture tests do not establish signed native permission behavior.

Production delivery remains the existing GitHub Release DMG/appcast/manifest pipeline. Signing keys, Apple services, trusted runners and GitHub configuration are external dependencies; ordinary work preserves their credentials and policies. Cloud date queries and local EventKit permission are separate workflows. No server privacy or security conclusion follows from inspecting the client alone.

Evidence for public distribution: [v1.4.9 release](https://github.com/iRedlof/Glimpse/releases/tag/v1.4.9), [panel source acceptance](superpowers/reviews/2026-11-01-panel-screen-fit-acceptance.md). The last accepted diagnostics interaction remains [v1.4.8 source acceptance](superpowers/reviews/2026-11-01-sandbox-diagnostics-acceptance.md) and retained `build/validation/native-live-v148.24ka2bug/native-acceptance.json`; the committed review predates that native check. Current release/install evidence lives under `build/validation/screen-fit-delivery.qojis70m`.

| Target / current initiative | Implementation | Tests / build | Release / verification | Outstanding |
| --- | --- | --- | --- | --- |
| macOS / panel screen fit | Shipped | Exact-main395 named tests passed | Public v1.4.9 signed artifacts and installed signature/launch accepted | Installed physical fit/scroll interaction pending |
| macOS / update recovery | Source independently accepted | 26 focused names / 72 cases pass; whole quality pending | Prepublication 1.4.10/build 17; protected delivery/public/native verification pending | [Scoped acceptance](superpowers/reviews/2026-11-02-update-retry-acceptance.md); ordinary full-quality hook, release and signed/native checks |
| Shared Core / update recovery | No source change required | Whole integration tests required | Delivered with app | Preserve reducers and dependency pins |
| External proxy / update recovery | No change required | No server claim | No deployment planned | Server access and operations remain uninspected |

Original other-machine termination remains unexplained, real restart testing is user-deferred, and endurance/physical display/live EventKit scenarios remain limited. Those outcomes stay open while independent verified improvements proceed.
