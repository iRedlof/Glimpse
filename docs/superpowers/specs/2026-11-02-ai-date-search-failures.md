# AI date-search failure feedback

The calendar keeps its existing AI field, provider choices and successful date
navigation. A completed response without a usable date and a failed request have
different static messages. A canceled or obsolete request cannot change the
current calendar, draft, progress or feedback.

The app-side client returns `async throws -> Date?`. `nil` means a successfully
completed, supported String response with no extracted date. Invalid preparation,
transport, non-HTTP/non-success responses, malformed response shape and on-device
generation failures throw payload-free categories. Unsupported explicit on-device
selection throws unavailable before invoking either provider. Cancellation stays
distinct and silent. Existing DateParser semantics, prompt, balanced POST tier,
authorization path, 15-second request timeout and Auto-to-Cloud policy stay intact.

| Outcome | Feedback and action |
| --- | --- |
| Completed without a date | `AI didn't return a usable date. Try ‘next Friday’ or ‘Jan 2028’.` Retain the draft/editor and stop progress. |
| Operational failure | `AI couldn't complete the date search. Try again.` Retain the draft/editor and stop progress. |
| Unsupported on-device choice | `On-device AI is unavailable. Choose Cloud AI in Preferences.` Retain the draft/editor and stop progress. |
| Cancellation | Stop only current progress without feedback or navigation. |
| Current success | Clear/close the draft and send the existing date action once. |

One MainActor observable model owns the real request. Each submission snapshots
its request ID, editor generation, draft revision, selected-preference revision
and resolved provider. Completion validates ownership and publishes atomically.
Invalidation clears the token before requesting Task cancellation; it does not
promise that the underlying provider immediately stops.

Every draft edit and selected-provider change invalidates synchronously, including
changes away and back. Provider changes retain an enabled editor. Disable, Escape,
dismissal, owned hide and actual view removal cancel and discard it. Hidden panel
preparation does not authorize submission; actual visible completion does.
Repeated visible Show and unchanged preference reload preserve current work.
The Preferences toggle/picker notify the owner immediately after reducer mutation.
Reload also reconciles current saved settings. Direct bindings drive the same
production model rather than a separate test controller.

There is no automatic retry, new Retry button, fallback, provider-readiness policy,
Core error state, new storage or telemetry. Display and logs use static categories
without query, prompt, response, status/body, endpoint, authorization or localized
error payloads. Core `aiDateResult(Date?)`, permissions, events, startup, updates,
keyboard ownership, focus policy and panel layout retain their existing contracts.

Tests inject explicit synthetic providers, configuration and fixture-local
preferences. Actual request handles, producer acknowledgements and cleanup joins
prove completion separately from canceled observers. Native root tests run alone
and exercise the actual editor, settings controls and panel lifecycle. Synthetic
on-device tests do not establish live FoundationModels readiness. Signed physical
keyboard, VoiceOver, macOS 14, restart and endurance remain separate observations.
