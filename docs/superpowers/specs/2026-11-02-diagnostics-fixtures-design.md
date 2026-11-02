# Controlled diagnostics deadline fixtures

QA-01 corrects fixture assumptions about collector scheduling. The accepted
read-only design is retained at
`build/validation/update-guidance-implementation.bpo8vktn/date-accessibility-implementation.gumn3kpn/diagnostic-fixture-next-slice.md`.
Quality41477994823/1 failed two provider-start waits; its exact execution
ordering remains unknown. This slice does not identify a product/crash cause.

Add two internal `LogCollector` initializer closures: submit an existing
`@Sendable () -> Void` worker, and await a `TimeInterval` deadline. Defaults
remain the utility queue and `Task.sleep`. Preserve validation, reservation,
detached timer installation, timeout origin, request delivery/cancellation,
pre-read guards, synchronous SDK ownership and cleanup.

Per-owned-test fixtures capture the actual worker and acknowledge deadline
arming. Run captured work on a separate actual background queue. For both
provider and iterator boundaries, observe real read entry before opening the
deadline gate. Assert timed-out empty output and limits while the read remains
blocked, exclusive ownership, no extra provider calls, full worker return
after cleanup, then fresh success without old output.

Separately release the deadline before running queued work: no provider entry,
ownership retained until that work returns, then fresh success. A separately
named production-default timer smoke captures only work, passes timeout `0.2`,
and retains elapsed time `<1s`.

Acknowledgements are async, single-shot and cancellation-safe. Retain ordered
safe fixture events. Cleanup always opens reader/deadline gates and drains
captured work, including assertion failures. Five-second fixture watchdogs
must fail explicitly. No polling, retries, timeout inflation, fabricated
collector results, new clock framework, OSLog access, or unrelated test rewrite.

Focused development runs only `DiagnosticsExportTests`, immutable package
pins, macro validation skipped, unsigned arm64 Debug, parallel testing disabled,
30-second per-test timeout, bounded wrapper and unique owned DerivedData.
Retain raw xcresults and source/pin receipts. Both lockfiles stay unchanged.
Root owns final whole-candidate review, mandatory hook, integration and delivery.

Independent review I1 requires cancellation of an acknowledgement observer
to remain separate from durable actual worker return. Mandatory bounded
draining must survive caller cancellation. A regression cancels the fixture
caller while its real completion wait is installed, then holds actual provider
exit behind a separate gate that cleanup cannot open. Cleanup and a fresh
observer must remain pending until that gate opens; each observer resumes once.
Review M1 requires consumed captured work to release its collector/fixture
graph after completion. A separate weak-collector regression covers ownership.
These corrections are fixture-only; production scheduling source stays frozen.
The producer alone stores durable signal completion; each observer has its own
locked cancellation/watchdog outcome and continuation. Cleanup joins an
uncanceled task that retains the existing explicit five-second bounds.
Captured work is consumed and cleared before actual return wakes observers.
