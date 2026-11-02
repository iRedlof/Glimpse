# Sandbox-compatible diagnostics

## Problem and evidence

The installed, signed v1.4.7/build 14 exports its report successfully but its default log collector exits 64 with `log: Cannot run while sandboxed`. `DiagnosticsExport` launches `/usr/bin/log`; the production app has `com.apple.security.app-sandbox=true`. The live report and private receipt are in `/Volumes/xHome/Github/Glimpse/build/validation/native-live-v147.fcfannzu`.

Independent QA reproduced the same error in an owned sandboxed helper. `OSLogStore(scope: .currentProcessIdentifier)` initialization and enumeration succeed with only the sandbox entitlement on this host. Neither its own SDK reads nor external reads retained the helper's fabricated messages. API access is established; useful message retrieval and historical crash coverage are not.

## Intended behavior

Export useful app metadata and a bounded excerpt of Glimpse's own current-process logs, without requesting new permissions or relaxing the sandbox. The report identifies its scope as the current launch and last five minutes. Empty retained logs are an explicit valid result. Collection failures and timeouts still save useful metadata to the user-selected destination.

The collector runs away from the main actor. A report stops waiting after the default ten-second collection deadline, including when native store creation or enumeration blocks. At most one native read remains active in the process. Another export while that read is unfinished receives a clear collection-in-progress error and still saves metadata. A timed-out or canceled read can continue inside an uninterruptible Apple API; its ownership remains reserved until that worker actually exits.

This is the Tech Lead's implementation choice under the existing autonomous bug-fixing and delivery goal. No new feature preference or user permission is needed for the source fix. The separate existing authorization covers installing a verified update and restarting the app, but excludes machine logout/reboot and new calendar access.

## Architecture

Replace the production subprocess collector with `OSLogStore(scope: .currentProcessIdentifier)`. Construct and consume the non-Sendable store and lazy enumerator entirely within one background worker. Convert entries to Sendable values there; no store or enumerator crosses an actor boundary. Filter on the exact current PID, `com.rohit.Glimpse`, and the five-minute cutoff. Preserve the SDK's composed message and privacy redaction.

Keep report writing and the selected-destination export flow. Remove the obsolete subprocess implementation and its process-specific tests. Use a small injectable entry provider and a separately owned collector instance in tests. The default export shares one production collector.

Deadline/cancellation delivery must be independent of completion of the synchronous native worker. Do not use a structured task group whose scope waits for a blocked worker. Do not hold a state lock while invoking a native API, iterating, or formatting. Late completion cannot resume a continuation twice or free another read's ownership.

## Bounds and errors

- Default collection deadline: `10` seconds. Accept only finite timeouts greater than zero and at most `60` seconds.
- Default and absolute maximum output: `1_048_576` UTF-8 bytes. Accept positive custom limits no greater than this maximum.
- Scan at most `10_000` candidate entries, without an extra lookahead. Reaching that cap marks the result limited even if no additional entry is known; report possible truncation truthfully.
- Keep output valid UTF-8 within its byte limit, including a boundary through a multibyte character.
- Cancellation returns `CancellationError`, avoids starting a canceled request, and cooperatively stops enumeration when possible. Native synchronous calls themselves have no cancellation API.
- Invalid limits and an already active read are distinct testable errors.
- Preserve metadata on collection errors, empty results, and deadline expiration. Preserve destination write errors for the caller.

Keep the existing `DiagnosticsExport.export(to:hotkey:collect:)` injection point. Its Sendable `LogResult` describes output, timeout, and truncation; remove subprocess-only exit status. Report wording must describe the actual byte/entry bounds and the current-process scope without claiming a hard termination of a native call.

## Compatibility and scope

- macOS deployment floor `14.0`; Swift language mode `6`, complete strict concurrency.
- No dependencies or entitlement changes. Existing team `5D7M37QQLU`, signing policy and Sparkle key remain unchanged.
- Preserve all 15 pins and both lockfiles byte-for-byte: core SHA-256 `ffeaf49b65ce3dd7b6a95db730357b03546883dc7fd20ba8e05cdb9aed529e6d`; app SHA-256 `5a5b283530b0e02190ce66eb50ac5817f037e0d2ac7ab99af10cdc6e931e54b7`.
- Changes stay in diagnostics source/tests and necessary release evidence/metadata. Do not modify startup registration, hotkeys, EventKit, panel layout, or unrelated UI.
- Target release `1.4.8`, build `15`, after source, product/UX and QA acceptance.
- The controller alone makes the accepted commit. Every introduced revision passes normal quality gates; no subsequent commit/push until the exact main Release/Recovery is verified.

## Acceptance

Behavioral RED/GREEN must cover supplied valid entries, foreign PID/subsystem and old-date exclusion, empty results, Unicode/byte and entry bounds, provider failure, blocked initialization/iteration, deadline delivery, cancellation, rejected concurrent collection, eventual ownership release, and late completion without duplicate continuation delivery.

Independent source review and sandbox evidence must confirm the production default calls the current-process SDK API and cannot launch `/usr/bin/log`. Fixture success alone is insufficient for this platform regression. After verified publication, install the authorized update and repeat the real About > Export flow. The app-generated report must save correct metadata, identify current-process scope, and contain no `Cannot run while sandboxed` or subprocess exit status. Record empty/native-error results honestly; do not infer retained message availability or crash-free operation.

Reboot/login reliability, global shortcut hardware delivery, real EventKit latency, long-duration stability, and the other-Mac crash remain separate acceptance work.
