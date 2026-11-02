# Keyboard mechanism Phase2

This test-only continuation answers two gaps from the preserved Phase1
`keyboard-focus-probe.7dh_e8tw` receipts. It changes no production UI or routing.
Source HEAD remains `db6fdc6b411b90a36287fcdd002330a0e2701971`; Phase1's exact
candidate sources, three attempts and report are immutable external evidence.

Use the same one owned, offscreen, nonactivating key-capable NSPanel. First focus
synthetic date1, then change the eligibility anchor and requested FocusState to
date2 in the same mutation turn. After bounded layout settling, send Space
**before any Tab**. Require exactly one date2 action. This is stronger evidence
than the generic NSHostingView responder observed immediately after Phase1's
anchor change. No retry, Tab reacquisition or focus fallback may precede it.

Then record forward Tab exit separately. Compare two Shift-Tab steps on the
SwiftUI prototype under direct owned-window dispatch and public application
dispatch. Replace content in this same panel with three ordinary native NSButtons
in an explicit native key-view loop. From the middle button, require Tab to reach
the following button and Shift-Tab to reach the preceding button under both
dispatch modes. The baseline sets native nextKeyView links but implements no
keyDown, traversal or action handler.

Public `NSApplication.sendEvent` dispatches to responders/window objects.
Apple defines `NSApplication.currentEvent` as the last event retrieved from the
queue; direct invocation of sendEvent is not evidence of queue retrieval.
Apple's `NSWindow.sendEvent` documentation says, **"Never invoke this method
directly."** Direct-window mode is an exploratory comparison to the existing
unsupported synthetic route, not proof of standard native or physical dispatch.
Capture whether application/window currentEvent is the synthetic event while the
owned panel receives it. Do not modify currentEvent or inspect metadata of an
unrelated event. SDK declarations confirm sendEvent is public and currentEvent
is read-only.

Application dispatch is allowed only inside the XCTest host, for an event whose
window is this actual key panel, with NSApp.keyWindow identity matching and an
owned firstResponder. The owned panel observes exact event identity and once-only
delivery before forwarding unchanged to super. No global posting/monitor,
CGEvent, activation, private API, physical modifier/settings change, installed
app interaction or previous-app manipulation is allowed.

Keep Return/keypad Enter's known zero-action result separate and pending root's
future scoped owner-routing design. Metadata U+0019/numericPad from Phase1 is
retained unchanged. A failure is a measured limit, not permission to introduce a
fallback or to claim a production defect. This compares public dispatch calls,
not physical keyboard delivery through the real application event queue.

Run only `anchorActivationAndReverseDispatch`, once, after root releases the
diagnostics build slot. Keep pinned local temporary DerivedData, unsigned arm64
Debug, no parallel testing, 30-second test timeout and 1200-second wrapper.
Fixture compiler corrections are permitted if required; no other reruns,
commit/push/full gate or production integration follows.
