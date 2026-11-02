# UX-02: actionable About update failures

Design proposal, revised 2026-11-02 after independent builder/spec review. Nothing implemented or shipped; implementation follows current screen-fit delivery and the separately prepared CD-01 iteration.

## Outcome and boundary

When an update check fails, About explains the result and offers an explicit retry as soon as Sparkle can accept it. When updating cannot initialize, About offers the existing official distribution route instead of a permanently disabled check button.
Designer calls below implement the delegated UX-02 scope; they are recommendations, not claims of separate user approval.
Keep the existing native About layout, shared MainActor updater/driver, installation choices, privacy behavior, HTTPS feed and EdDSA verification, test-host startup guard, and both locked dependency graphs.
No automatic retry, updater replacement, background-check override, new dependency/global state framework, release control, settings change, automatic download/install choice, or unrelated UI work.

## Inspected facts

Source root: `/Users/rohit/.codex/worktrees/stability-ux/Glimpse`; inspected HEAD `f90999f3d16104574651f1a758607fd2144af51d`.
Pinned Sparkle checkout: `/Volumes/xHome/Github/Glimpse/build/ci/quality.r05ura/core/checkouts/Sparkle`; verified HEAD `b6496a74a087257ef5e6da1c5b29a447a60f5bd7` = both graphs' Sparkle 2.9.4.

| Evidence | Relevant contract or current behavior |
| --- | --- |
| `Glimpse/SparkleUpdater.swift:36–55` | Construction starts Sparkle, observes `canCheckForUpdates`, logs startup failure, and exposes an unguarded check method. |
| `Glimpse/SparkleUpdater.swift:63–76,99–108,137–140` | One status, two pending choices, a five-second latest timer; errors acknowledge immediately; teardown only clears choices. |
| `Glimpse/AboutWindow.swift:134–233` | Error has no action. Check is disabled solely by Sparkle eligibility. Install/Skip/Relaunch invoke callbacks before clearing them. |
| `Glimpse/GlimpseApp.swift:9–16` | Test-host guard precedes `SparkleUpdater.shared`; retain it and avoid the singleton in fixtures. |
| `Glimpse/Info.plist:27–32`, `README.md:3–4,31` | Existing HTTPS feed/public signing key, automatic checks, and official HTTPS release-page route. |
| Sparkle `SPUUpdater.h:71–109,156–189` | Start validates configuration; manual check may resume a prior downloaded/installing update. Eligibility is not equivalent to absence of a session. |
| Sparkle `SPUUpdater.m:146–190,206–358` | Failed start returns before `_startedUpdater = YES`; repeated successful start returns YES without another cycle. Failures include bundle/XPC/key/configuration faults. |
| Sparkle `SPUUserDriver.h:33,58–100,145–156,208–268` | Main-thread callbacks; errors can follow any phase; Install/Skip and ready-to-relaunch replies carry different lifecycle meanings; dismissal tears down installation UI. |
| Sparkle `SPUUIBasedUpdateDriver.m:452–489`, `SPUUpdater.m:815–840,867–897` | Error acknowledgement queues dismissal/abort; eventual completion releases the session and eligibility. Acknowledgement alone is not permission to retry. |
| Sparkle `SPUUpdater.m:435–439,546–547,722–737,894–897` | This driver has no focus support: checks/permission presentation make eligibility false; it is not re-enabled for shown updates. Scheduler eligibility/session writes do not suspend between them. |
| Sparkle `SPUUIBasedUpdateDriver.m:244–245,420–422`; app `SparkleUpdater.swift:68–76,132–135` | Native choice continuations dispatch asynchronously. Existing latest task checks its own cancellation before a synchronous MainActor write; installation-finished currently writes idle after acknowledgement. |

## Bounded approaches considered

| Approach | Assessment |
| --- | --- |
| A. Typed failure presentation, guarded manual check/retry, official release fallback | **Recommend.** Resolves the dead ends using existing objects and Sparkle's lifecycle. |
| B. Also retry `start()` on the same instance | Supported by this pinned implementation, but repeated configuration validation rarely repairs bundled faults; adds a second recovery path with weak user value. |
| C. Replace the updater/driver or add a general update coordinator | Unnecessary ownership/scheduler changes for this problem; broader regression surface. |

Start failure is deliberately not retryable within this change. This is a product choice, not an assertion that Sparkle forbids repeat start.
Normal Retry calls `checkForUpdates()` on the existing successfully started instance; it never calls `start()`.

## Copy, controls and state transitions

Use a distinct initialization-failure status and a bounded runtime failure kind (check / update), rather than routing recovery by matching message strings.
Keep the failure result until a user starts another eligible check or Sparkle reports a newer outcome; opening/closing About does not reset it.
Render wrapped, centered text and actions within the existing update section, using AppDesign spacing. Keep errors readable without relying on red alone.
“View Releases” is a native link to `https://github.com/iRedlof/Glimpse/releases/latest`, already advertised by README; no feed/asset URL is generated from errors.

| State / event | User sees and can do | Transition |
| --- | --- | --- |
| Start succeeds | Existing “Check for Updates”; availability follows the common guard below | Check action → checking before invoking Sparkle |
| Start throws | “Updates are unavailable.” / “Get the latest Glimpse release from GitHub.”; **View Releases** | Remains visible for this launch; no Check/Retry or silent repeat start |
| Checking | Existing spinner and “Checking for updates…”; no Check/Retry/Install | Sparkle result determines next state |
| Check fails | “Couldn’t check for updates.”; **Retry**, **View Releases** | Record result before acknowledging once; wait for teardown/eligibility |
| Check failure, retry ineligible | Same result; Retry remains visible and disabled; “Retry is temporarily unavailable.”; View Releases stays usable | Eligibility changes update the same control; no polling or queued retry |
| Check failure, retry eligible | Retry enabled; omit unavailable helper | One user activation → checking; old result/timer invalidated |
| Error after offer/download/extraction/install | “The update couldn’t be completed.” / “Check again for available updates.”; **Check for Updates**, **View Releases** | Same guarded new-check path after teardown; never replay an install callback |
| No update found | Existing latest result, five-second dismissal | Only that result's timer may restore idle |
| Available update | Existing version, Install and Skip; enabled only while the corresponding choice is owned | Choice consumed once; remain unavailable for new checks while Sparkle continues |
| Downloading / extracting / installing | Existing progress presentation | Follow Sparkle; no retry or new install choice |
| Ready to install | Existing Install & Relaunch; enabled only while its callback is owned | Explicit choice consumed once; then await Sparkle |
| Installation finished / ordinary teardown | Installation progress and controls removed; ordinary state returns idle | Preserve a terminal About failure/latest result as described below |

A check error does not establish an offline connection; do not claim “No internet” or promise that retry will succeed.
For errors whose preceding phase is unknown, use the broader update-failure copy. Log bounded diagnostic context with AppLogger; do not expose raw paths, URLs, or framework details in UI.
Do not change existing no-update reason handling, information-only/major-update behavior, release notes, cancellation controls, or installation-termination recovery in this iteration; these are separate contracts, not new Retry capabilities.

## Ownership and concurrency

1. Keep all observable mutation, Sparkle calls, callback storage/consumption, and timer transitions on MainActor.
2. One shared action predicate governs rendering and execution: successful initialization, Sparkle eligibility, no owned update/install choice, and an idle or recoverable-error presentation.
3. Keep the existing `canCheckForUpdates` observation and re-read live eligibility at activation. Its observer only updates presentation availability; it never initiates a check. Do not add a session subscription/cache or `showUpdateInFocus`.
4. Admit a check synchronously before calling Sparkle: cancel the prior result task and set `.checking`. That phase already blocks rapid clicks, keyboard activation and stale check actions; no separate admission flag is required.
5. Driver callbacks then determine the next phase. Error publication/acknowledgement does not manufacture eligibility; actual eligibility notification re-enables Retry after teardown. Never queue a retry. A defensive live session read is optional, not a required state source; preserve Sparkle's intended manual resumption of deferred/downloaded/installing updates.
6. Move Install, Skip, and Install & Relaunch callback consumption behind small driver methods. Store a fresh local choice identity with each offered-update or ready-to-install reply; Install and Skip for one offer share the same identity. The view neither owns nor writes callback slots/status.
7. Each rendered control captures that choice identity as a value, not by reading the current identity when activated. Driver methods validate identity plus current phase/slot, take the closure locally, retire its slot/identity and disable that choice before invoking once. Do not write old state after invocation.
8. “Exactly once” means one invocation for an accepted user choice, zero for a stale/repeated action or Sparkle-invalidated choice. Do not fabricate `.skip`, `.dismiss`, or `.install` to unblock Retry.
9. Publishing an error does not consume either pending choice. Acknowledge that error once after recording the result, then return; Sparkle owns abort timing. Pending choices continue blocking retry until Sparkle dismissal retires them.
10. `dismissUpdateInstallation()` clears both retired choice slots/identities and active installation presentation without calling them. Preserve terminal failure/latest status in the same existing status model, so queued teardown cannot erase the error action or latest result.
11. Teardown is not a new retry command. Closing About only hides its presentation; the shared updater, pending choice and failure survive reopening.
12. A new Sparkle offer/progress/result supersedes an old terminal result. No asynchronous continuation may restore the previous error/checking state afterward.

If invoking choice A synchronously publishes same-phase choice B, retained A controls must fail identity validation and leave B intact; newly rendered B controls can consume B once. Apply this to both offers and ready-to-install choices.
The exact private field arrangement is the builder's choice: extend the existing driver/status object, not a second independently writable UI model.
Public Sparkle callbacks have no session IDs. A local choice identity protects retained controls, not arbitrary reordered native callbacks. Synchronous replacement/acknowledgement fixtures and delayed notifications are defensive contracts, not observed native failures; pinned native choice handlers dispatch asynchronously.

## Auto-dismiss and accessibility

Only the latest-result presentation auto-dismisses, after the existing five seconds. Failures never auto-dismiss.
Retain one cancellable MainActor Task with an injected awaited delay; cancel it on each new check or superseding presentation, including error/offer/progress and a newer latest result. No timer generation is needed.
After the delay returns, check that task's own cancellation flag and expected status, then write idle synchronously with no intervening await. A canceled sleeper returning successfully still cannot dismiss a newer equal latest result; MainActor cannot interleave between the guard and write.
Record/schedule latest before its acknowledgement; record errors before theirs. For installation-finished, clear ordinary progress/retired choices and publish idle before acknowledging. Each acknowledgement is invoked once with no post-ack state write, so a synchronously published replacement survives.
Ordinary Sparkle dismissal preserves the current latest task and result while removing active installation work; do not cancel that result and strand it permanently.
Keep native Button/Link roles, explicit labels (“Retry checking for updates”, “Check for updates”, “View Glimpse releases on GitHub”, “Install update”, “Skip this update”, “Install update and relaunch Glimpse”) and readable status text; hide decorative error/check icons from accessibility.
Updater controls must participate in native keyboard navigation/activation. Scope removal of `.focusable(false)` to this section; preserve plain styling, use AppDesign padding/contentShape for usable hit targets, and allow native focus indication.
Do not bind Return globally to Retry or Install; keyboard focus determines the target and disabled controls cannot activate. Preserve ordinary window-close and calendar input routing.
The scoped focus change intentionally overrides the generic view rule that suppresses all button focus; keyboard access is the reason.

## Minimum seam and meaningful acceptance

Inject a narrow app-local MainActor updater boundary: start result, live eligibility read and its existing change delivery, and manual check invocation. Production still owns exactly one SPUUpdater; fixture construction never initializes `.shared` or SPUUpdater.
Inject an awaited delay inside the existing latest task to advance five seconds deterministically, including returning a canceled sleeper successfully; retain the task's own cancellation context. Invoke actual driver callbacks with counted acknowledgement/choice closures, not a new independent timer-completion API.
For offer fixtures, exercise the same small version/choice transition helper called by the production callback: `SPUUserUpdateState` exposes no public default initializer (`SPUUserUpdateState.h:65–67`). Do not fabricate it with private API or construct a real updater merely to obtain one.
Use Swift Testing in the app target with per-test instances. No production defaults, network feed, real timers, signing changes, or native update operation in regression tests.

| Injected scenario | Required observable result |
| --- | --- |
| Initial start throws, About projected/reopened, attempted stale Check | Visible initialization fallback; start count one; check count zero; no retry path |
| Successful start → check error → ack → dismiss while ineligible → eligibility restored | Correct persistent failure; ack once; both choices retired only at dismissal; Retry enables without reopening |
| Eligibility drops between rendering and activation | No check; error retained; control reflects current availability |
| Double Retry with eligibility notification/callback delayed | Exactly one check; checking immediately; no pending auto-retry |
| Retry blocked by live ineligibility, non-actionable phase, or owned offer/ready choice | No check/start/choice invocation; `.checking` is the only local admission state; no artificial session/eligibility contradiction is required |
| Retry → latest, retry → available, retry → repeated failure | Correct new result; no lingering old error/timer; repeat failure allows later explicit retry |
| Error during download or install | Broader update copy; acknowledgement once; no “retry install”, no replayed choice; new check only after retirement |
| Install A synchronously publishes same-phase offer B; retained A Install/Skip then activate; newly rendered B activates | A called once; both retained A actions invoke nothing and preserve B; current B action invokes B once |
| Install & Relaunch A synchronously publishes ready choice B; retained A action then current B action activate | Retained A action invokes nothing and preserves B; each matching current choice is consumed once |
| Sparkle dismisses without user choice | Both old callbacks invalidated, none invoked; stale actions inert; active progress removed |
| Canceled latest sleeper returns successfully after error/check/offer or equal newer latest result | Own task cancellation guard retains the new state; only current latest dismisses at its five-second deadline; ordinary dismissal preserves that task |
| Error/latest/installation-finished acknowledgement synchronously causes teardown or newer presentation | Each ack once; all old-state writes/scheduling precede ack; error/latest survive ordinary dismissal and newer presentation wins |
| Close/reopen projection with failure or outstanding choice | Shared state retained; no new start/check or choice consumption |

Later signed About acceptance must verify wrapped copy/window fit, light/dark contrast, VoiceOver names, keyboard focus/disabled activation, Check/Retry responsiveness and official-link destination. Fault states use a controlled injected presentation where a safe real reproducer is unavailable; label that evidence separately.
Existing installation behavior, resumed-update prompts, real network errors, and relaunch success require later native evidence; this design and fixture results cannot establish them. Follow the normal exact-source quality/review/release process only during the separately authorized implementation.
