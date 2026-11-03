# Pre-Production Code Review — Glimpse-Specific Checklist

Run these checks before any release or significant merge.

---

## A1 — macOS Permissions & TCC

### A1.1 Permission Gating
- Calendar access checked before EventKit queries
- Permission request only triggered by explicit user action ("Show today's events")
- Graceful degradation when access denied (show request button, not error)

### A1.2 Accessibility
- All interactive elements have `.accessibilityLabel`
- Calendar grid has `.accessibilityElement(children: .contain)`
- Date cells have full date accessibility labels
- Buttons have role descriptions

---

## A2 — NSPanel & Menu Bar

### A2.1 Panel Lifecycle
- Reused calendar re-show preserves its explicit Today/reset hook; settings are presented in a separate retained window
- Settings handoff leaves pinned calendar geometry/state intact and explicitly hides an unpinned calendar
- Panel positions correctly on all screens (multi-monitor)
- Panel respects edge margins (10pt from screen edges)
- Caret offset calculated correctly from status item position
- Pin mode prevents panel dismiss on resignKey

### A2.2 NSStatusItem
- StatusItemView handles all display option combinations
- Filled/unfilled rendering consistent between menu bar and preview
- Menu bar refresh via NotificationCenter (not direct method calls)
- Midnight refresh timer properly scheduled
- Status item handles menu bar overflow gracefully

### A2.3 Text Input Activation
- Calendar app activation is confined to explicit text editing; Settings activation belongs to explicit native-window presentation
- Previous app restored after external calendar editing, with that restoration lease abandoned for internal Settings handoff
- Deferred AI editor focus must still prove current owner, editing intent and generation before activating

---

## A3 — Carbon & Event Handling

### A3.1 Global Hotkey
- Carbon EventHotKey registered with correct modifiers
- Hotkey unregistered when disabled in preferences
- Key combo persisted to/loaded from UserDefaults
- No conflict with system shortcuts

### A3.2 Event Monitors
- Key monitor added in onAppear, removed in onDisappear
- Scroll monitor added/removed alongside key monitor
- Monitors return `nil` for consumed events, pass through for unhandled
- Calendar Escape closes the AI editor before closing the panel
- Settings Escape cancels shortcut recording first, then closes its own window; popup tracking/sheets retain native event ownership
- Settings Tab/Shift-Tab, Space/Return and Command-W use the native Settings owner and must not invoke calendar navigation

---

## A4 — Sparkle Auto-Updates

### A4.1 Feed Security
- `SUFeedURL` uses HTTPS
- `SUPublicEDKey` present for EdDSA verification
- InlineUpdateDriver handles all SPUUserDriver callbacks

### A4.2 Update UI
- All UpdateStatus cases handled in About window
- Install/Skip buttons wire to correct pendingReply callbacks
- Auto-dismiss after 5 seconds for "latest version" status

---

## A5 — AI Integration

### A5.1 Proxy Security
- App secret XOR-obfuscated (not plaintext)
- Device ID for rate limiting (not tracking)
- No user data sent beyond the query string

### A5.2 FoundationModels
- `#if canImport(FoundationModels)` guards all usage
- `@available(macOS 26, *)` runtime check
- Graceful fallback to proxy when on-device unavailable

---

## A6 — Data & Preferences

### A6.1 UserDefaults
- All preference keys have default values (missing key = default)
- Display options backward compatible (new fields have defaults)
- No secrets stored in UserDefaults (API keys use Keychain)

### A6.2 EventKit
- Calendar events fetched asynchronously
- Event date formatting handles all-day vs timed events
- Calendar access status checked before fetch

---

## A7 — Code Quality & Cleanup

(Same as Auris A11 — universally applicable)

### A7.1 Dead Code
- Unused functions, properties, imports, parameters, variables
- Commented-out code blocks (delete — git has history)
- Unreachable code paths

### A7.2 Hack Detection
- `try?` that silently swallows errors — every `try?` needs justification
- `Task.sleep` as timing hack instead of proper synchronization
- Force unwraps without safety comment
- Hardcoded magic numbers without named constants

### A7.3 Complexity Reduction
- Functions longer than ~50 lines — extract helpers
- Deeply nested if/switch (>3 levels) — flatten with guard/early return
- Duplicated logic — extract to shared helper

### A7.4 Consistency
- Naming: camelCase, descriptive, no abbreviations
- Error handling: use AppLogger not print
- Date handling: `@Dependency(\.date.now)` in reducers
- Design tokens: use AppDesign constants, not hardcoded values

### A7.5 Performance
- DateFormatter must be static (never in loops/computed properties)
- Avoid O(n) scans in SwiftUI body
- Large arrays in @ObservableState cause TCA to diff on every action

### A7.6 Security
- No secrets or API keys in source code
- No user-controlled strings in Process.arguments
- File paths logged with `privacy: .private`

---

## A8 — Test Coverage

### A8.1 New Code Must Have Tests
- Every new public function in GlimpseCore needs at least one test
- Every bug fix should have a regression test
- Edge cases: nil, empty, boundary values

### A8.2 Test Quality
- Tests should be independent (no shared mutable state)
- Use `withDependencies` for time, not real `Date()`
- Test names describe the scenario, not the implementation
