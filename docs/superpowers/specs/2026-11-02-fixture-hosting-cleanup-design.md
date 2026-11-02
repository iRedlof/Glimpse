# Terminal fixture hosting cleanup

## Evidence and scope

Canonical `d36661d6b78a7236b0aedfc7e05237516000c9f1` uses terminal
`AboutUpdateHost.close()` and `AccessibilityTestHost.close()` calls. The consumer
audit covers all 30 original test methods: 11 About and 19 accessibility methods.
All close calls occur in terminal defers, directly or through the date wrapper.
The three About `reopen()` calls replace content before close; none reopens a
closed window. Viewport helpers read hosting content only before close.

The accepted close-only experiment retained six hosting views after about one
second despite releasing the helper objects. The separate one-factor comparison
released all six hosting views by the first 26–33 ms drain sample after detaching
`window.contentView`. Windows remained alive in both experiments. These are
bounded fixture observations, not production leak or performance findings.

## Intended contract

After terminal helper close and helper scope exit, its hosting view must be
releasable within bounded executor/run-loop drainage. The helper intentionally
owns its hosting view while the helper is alive; close does not have to invalidate
that stored property. The regression must prove that a real, settled hosting
view existed before close and retain only weak host/view references afterward.

Use two tests in a separate `FixtureHostingCleanupTests` suite. Each constructs
one original helper and performs its real settle, accessibility-tree read and
deferred close. About uses `UpdaterFixture` with its existing injected backend
and delay cleanup. Accessibility uses an inert plain, nonfocusable button.
No manual content detachment occurs in either regression.

After the async factory returns, assert that the helper is gone, then poll the
weak hosting reference. Stop on release, after one second, or after 40 passes.
Each pass pumps the default run loop for at most 5 ms and awaits 25 ms. Preserve
actual passes, elapsed time and liveness in raw `FIXTURE_HOSTING_CLEANUP` JSON.
Scheduling can delay resumption; this is bounded work, not a hard elapsed-time
performance assertion. Propagate task cancellation and keep close in defer.

The intended RED is a hosting-release assertion against the unchanged original
helper. A compiler/loader failure, missing fixture, or retained helper is not
that RED. After an accepted RED and explicit runtime handoff, the sole proposed
helper change is `window.contentView = nil` immediately before `window.close()`.
Keep stored hosting properties, `reopen()`, release flags and all callers intact.
Removing that cleanup must cause the new behavioral regression to fail.

## Preserved behavior and exclusions

- Original baseline/comparison source, snapshots, logs and xcresults stay intact.
  Their historical receipts remain tied to the recorded source. Do not rerun
  those selectors as the original baseline after a helper change.
- Date fixture's existing `EmptyView` assignment before close remains intact;
  this is not permission to add that factor elsewhere.
- Reopen-before-close, rendering, action geometry, picker cleanup and dependency
  isolation remain covered by the existing affected suites when runtime is granted.
- No assertion about `NSWindow` deallocation, window-count shrinkage, retention
  owner, warning suppression, production memory/crash cause or performance.
- No release-flag change, private heap API, extra helper cleanup, production edit,
  registry repair, native installation, version bump, commit, push or full gate.
- Initial preparation was source-only. Subsequent runtime was allocated by root,
  with terminal owned-process absence recorded before release of the slot.

Both original-helper regressions reached the hosting-release assertion and failed.
The minimal two-helper detachment then passed the unchanged regressions and all
30 original affected consumer methods: 32 methods/137 cases in total, with no
failures or skips. Independent review accepted the changes; root integrated the
two helpers, regression and project registrations into the keyboard candidate.
These are retained bounded results. Integrated whole quality remains pending,
and no production leak, window deallocation or performance cause is claimed.
