# Owned native keyboard mechanism probe

This is an opt-in test-only experiment for the future keyboard design in the
external `keyboard-focus-next-slice.md` report. It changes no production behavior.
The source baseline is v1.4.14 `db6fdc6b411b90a36287fcdd002330a0e2701971`,
tree `e1e413f27684915739659e90669b501c8e47c55f`.

Use one owned, offscreen, key-capable nonactivating NSPanel hosting plain SwiftUI
Buttons and actual FocusState. Two peer buttons bracket three synthetic dates;
only the current date anchor is focusable. No date/calendar data is loaded.

Record the OS, application active/key state, read-only public keyboard-navigation
configuration, actual FocusState, actual firstResponder type/identity/ownership,
key delivery, per-target action counts, and cleanup. Send keyDown/keyUp directly
to this owned window. Never post global events, invoke AX default actions,
activate the app, manipulate the previous application, or change system settings.

The desired mechanism assertions are native Tab from the preceding peer to one
date and then the following peer; reverse traversal; anchor transfer followed by
native Tab exit/reentry; and exactly one date action each for Return, keypad
Enter and Space. Focus changes must not invoke an action. These are hypotheses:
a failure characterizes this prototype/host configuration, not a production bug.
FocusState alone is insufficient; a non-window firstResponder must belong to the
owned panel before the report can claim native focus.

The suite is enabled only by `GLIMPSE_KEYBOARD_MECHANISM_PROBE=1`. Ordinary tests
must not depend on this machine's keyboard-navigation setting. No fallback
handler, custom Tab interception, 42 sequential stops, production monitor or
production UI is introduced. Cleanup clears only the owned firstResponder,
replaces the owned hosting content, orders out/closes that panel, and records
visibility/key state. The fixture creates no unstructured tasks.

Use unsigned arm64 Debug, resolved-file package pins, local temporary DerivedData,
macro-validation skip, no parallel testing, 30-second test timeout and a
1200-second external receipt wrapper. Root owns source review and future
production scope; no commit, push, full gate or release follows this probe.
