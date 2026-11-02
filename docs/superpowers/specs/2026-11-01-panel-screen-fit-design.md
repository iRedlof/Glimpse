# Calendar panel screen fit

## Intent and evidence

Keep the calendar and expanded preferences inside the usable display, with every control reachable when content is taller than the available space. This is the next existing UX-roadmap item under the user's autonomous cross-functional mandate. The design choices below are Tech Lead decisions, not additional preferences supplied by the user.

Released main `302a260e736f8d9cdc14684b1f1281f7768588fa` retains the panel's top below the menu bar but caps height to the entire `visibleFrame.height`. With visible frame `(0,48,1440,828)` and status item `(1000,876,100,24)`, the top is870; an828-point height requests y42, below the visible lower edge48. The preferences/calendar stack has no scrolling recovery. These are source findings; actual clipping and unreachable controls in the signed app have not yet been measured.

Independent investigation: `/Volumes/xHome/Github/Glimpse/build/validation/screen-fit-independent-source-qa.bnx9t_io/source-investigation.md`.

## User-visible behavior

- Preserve the compact calendar, existing controls, material, rounded corners and menu-bar attachment. The caret stays outside the scrolling area.
- Preserve panel width316 points and content width300 points. The existing300-point content retains its padding and child widths; the outer caret spans the actual316-point panel.
- Align the top to status-item minY minus6 points, capped at visibleFrame.maxY. Keep the left, right and bottom edges10 points inside visibleFrame. The caret points toward the status item's center, clamped16 points from the panel's left/right edges.
- A short panel uses its measured natural height. A tall panel uses only the space from its anchored top down to visibleFrame.minY+10. Its entire padded body scrolls vertically, including expanded preferences, wrapped errors, calendar, events and footer. Show normal system scroll indicators when scrolling is needed. Keep the material and rounded clipping stationary.
- When the body fits, wheel gestures over the calendar retain month navigation. When it overflows, wheel gestures everywhere scroll content and do not change month. Previous/next buttons and existing unmodified keyboard navigation remain available. A gesture must never both scroll the viewport and navigate months.
- A phased trackpad gesture, including momentum, has one owner chosen at its begin: compact eligible calendar consumes events, otherwise the viewport receives them. Keep that ownership when content or hover changes. If a calendar-owned gesture loses eligibility, consume its remaining panel events without navigation until a fresh gesture begins; a viewport-owned gesture never becomes month navigation. Hidden/other-window events always pass through and end this panel's ownership. Unphased mouse-wheel events use event-level exclusivity.
- Clear partial wheel accumulation when leaving the calendar, hiding/reopening the panel, starting shortcut recording, changing overflow mode or receiving an ineligible event. Context changes suspend navigation while retaining phased ownership; hide/reopen fully reset it. Ignore nonfinite deltas. Preserve strict threshold magnitude>5 and contribution clamping to±1.5 in compact mode.
- Opening/closing preferences and reopening the reused panel reset the content to the top. Activating AI input scrolls its field into view. These are transient view changes, with no new persisted preference.
- Recompute placement while visible after screen-parameter changes and wake, and after the status item's displayed width changes. Choose the screen containing the status item. Continue to collapse preferences and reset calendar state on reopen.

## Architecture and convergence

Use a pure `PanelGeometry` policy for initial placement and later resizing, consuming status-item rect, chosen visibleFrame and desired total height. Its result contains the frame, caret offset and maximum total height. Reject nonfinite/nonpositive rects/heights, unsupported visible widths below336 points, and anchors with fewer than13 points available; never pass invalid geometry to AppKit. Such invalid transient geometry preserves the previous valid panel placement, or skips a first show with a logged error. Ordinary macOS display configurations are wider than this threshold; responsive preferences below300 content points are outside this iteration.

Use one `@MainActor @Observable PanelLayoutState`, owned by CalendarPanel and passed to the root view. It records measured natural body height, maximum total height and caret offset. Initial natural body height420, caret12 and default maximum total height800 preserve safe initial values. Viewport height is min(natural body height, maximum total height−12), total height adds12, and overflow requires a difference>0.5 points. Only finite positive measurements are accepted. Updates smaller than0.5 points do not mutate observable state.

Use one persistent generic `PanelViewport` containing a vertical SwiftUI ScrollView. Its padded child has fixed natural vertical size at width300, measured using GeometryReader/PreferenceKey behind the child. The child measurement must remain independent of the constrained viewport height. Frame the viewport to the state's explicit height and disable scrolling while content fits. Do not replace the subtree when crossing the overflow threshold: settings/recorder/AI state must survive.

Keep the existing intrinsic-content KVO,50ms cancellable debounce and0.5-point frame idempotency guard. The root's intrinsic height now describes the bounded viewport plus caret. Initial placement, measurement and screen changes converge to a stable frame; unchanged measurements and frames must cause no further mutation. Compare x,y,width,height in the frame guard. Retain first-show nonanimation and hide cancellation. Geometry refresh must not send a reopen action or reset user selection.

Extract wheel policy into a small pure `CalendarScrollRouter`. The local event monitor maps native gesture/momentum phases, consumes calendar-owned events, passes viewport-owned events through, and uses the router's optional direction to send the existing month action. View context callbacks suspend accumulation/navigation; hide/reopen fully reset the router. Keep ownership after finger phase ends so following momentum retains it, then clear at momentum end/cancel or a fresh begin/discrete input; no timer is necessary. No new gesture recognizer or global event monitor.

## Constraints and limits

- macOS14.0 minimum, Swift6.0 with complete concurrency, existing TCA/Sparkle versions and both15-pin lockfiles unchanged. No new packages or newer-runtime-only APIs.
- No launch-at-login, global hotkey registration/persistence, diagnostics, EventKit, AI transport, entitlements, signing or release-tool behavior changes.
- No production calendar grant/data, display/Dock preference changes, machine reboot/logout or private external transmissions. Rich layout states use controlled test fixtures.
- The user deferred the restart check. Enabled registration remains evidence of registration, not proof of unattended launch. The other machine's crash remains unexplained.
- One controller commit after source and metadata acceptance; every introduced source revision passes mandatory quality. Use existing protected ordinary PR and exact-main Release/Recovery gates for this affected production line. The updated master goal requires unrelated independent development to remain possible during a release failure; narrow the existing global gate in a separately tested delivery iteration. Native installation follows public artifact verification under the existing authorization.
- Publish user-facing change as1.4.9/build16 only after product/UX/code/QA acceptance. Synchronize all4 marketing+4 build settings, README badge and release readiness evidence.

## Acceptance

1. Geometry regressions cover the concrete failing example, cap boundaries, shorter content, bottom/side Dock visible frames, negative origins, shifted menu bars, unsupported/invalid input and repeated same placement. Every accepted target is finite and contained with the stated margins.
2. Router regressions cover compact navigation, strict threshold, positive/negative/clamped deltas, partial accumulation reset, overflow, settings, other windows, hidden panels, shortcut recording and nonfinite input. An overflowing-started gesture passes through with no month action. Calendar→overflow and overflow→compact changes during finger/momentum phases preserve ownership; an unseen phased start conservatively passes through until a fresh begin.
3. Controlled hosting-view layout verifies natural body height stays independent of viewport constraint, short/tall content and long wrapped text grow/shrink correctly, caret+viewport intrinsic size stays within budget, repeated measurement settles, and lifecycle reset/focus anchors exist. Fixture stores must not trigger live permissions, network, hotkey registration or startup changes.
4. Source/integration review checks real preferences and error/recovery/footer are inside the one viewport, correct screen refresh and observer lifetime, persistent subtree/state, pin/focus/reopen behavior and A1–A8 repository requirements.
5. Mandatory whole-revision quality and protected publication/native artifact verification remain separate gates. Signed native UI QA must exercise expanded preferences, scroll reachability, compact grid navigation, pin/reopen and settled resources. Small/scaled display, Dock and multiple-display configurations unavailable on this host remain explicit limits; pure layout tests do not substitute for all physical configurations.
