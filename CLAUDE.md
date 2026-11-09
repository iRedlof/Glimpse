# Glimpse — Dev Notes for Agents

This file provides guidance for coding agents working in this repo.

## Code Review Requirements

**When asked to do a code review, ALWAYS follow the checklist in `.claude/rules/pre-production-review.md`.** This is not optional. Run through every applicable section (A1–A8) against the changed files. Report findings by section number. Key sections:
- A1–A6: Glimpse-specific (permissions, panel, hotkey, Sparkle, AI, preferences)
- A7: Code quality — dead code, hack detection, complexity, consistency, performance, security
- A8: Test coverage — every new function, bug fix, and model needs tests

Also check the rules in `.claude/rules/` for:
- `glimpsecore.md` — GlimpseCore package rules (Sendable, no AppKit, logging)
- `clients.md` — Dependency client rules (closures, error handling, UserDefaults)
- `tca-features.md` — TCA reducer rules (state capture, effects, delegate actions)
- `swiftui-views.md` — SwiftUI view rules (Store binding, AppDesign tokens)
- `gotchas.md` — Hard-won debugging insights to avoid repeating mistakes
- `known-issues.md` — Deferred items (don't fix unless asked)
- `versioning.md` — Version sync rules (3 locations)

## Project Overview

Glimpse is a macOS menu bar calendar app built with TCA and Swift 6. Click the date in the menu bar to see the current month at a glance, with AI-powered date navigation, EventKit events, and configurable display options.

## Build & Development Commands

```bash
# Build (requires -skipMacroValidation for TCA macros)
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Release -skipMacroValidation build

# App tests (370 default-run tests; key-panel suites run in the quality gate)
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -skipMacroValidation test

# GlimpseCore tests (182 tests, 12 suites)
cd GlimpseCore && swift test

# Local run (re-sign Sparkle for ad-hoc)
find Glimpse.app/Contents/Frameworks -name "*.framework" -exec codesign --force --sign - --timestamp {} \;
codesign --force --sign - --timestamp --deep Glimpse.app
open Glimpse.app

# Open in Xcode (recommended for development)
open Glimpse.xcodeproj
```

## Architecture

**TCA** (The Composable Architecture) for all state management. Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`.

### App Target (Glimpse/)
| File | Purpose |
|---|---|
| `GlimpseApp.swift` | @main entry, AppDelegate |
| `CalendarPanel.swift` | NSPanel (non-activating, pin support, text input, Settings handoff) |
| `CalendarStatusItem.swift` | NSStatusItem, panel positioning, midnight refresh, NotificationCenter observer |
| `MenuBarItemRenderer.swift` | Composites the whole menu bar item (border/filled, icon + separator + text) into one `NSImage` set as `button.image`. No subview — a child view in the status button pegs CPU on macOS 26 (see gotchas.md) |
| `StatusItemPreview.swift` | NSViewRepresentable rendering the same MenuBarItemRenderer image for the SwiftUI preferences preview |
| `CalendarPopoverView.swift` | Main calendar UI, date selection, AI field, events, footer with quit confirm |
| `SettingsWindow.swift` | Retained native Settings controller, exact shortcut owner, refresh and bounded placement |
| `SettingsRootView.swift` | One full-width Settings scroll viewport with native control focus |
| `PreferencesView.swift` | One categorized Settings page, shared lifecycle and existing preference setters |
| `MonthBorderShape.swift` | Contoured month border (SwiftUI Shape) |
| `DateIconRenderer.swift` | Date number + red accent menu bar icon, configurable text color |
| `GlobalHotkey.swift` | Carbon EventHotKey, configurable combo with persistence |
| `AIDateHelper.swift` | Routes between proxy API and FoundationModels; both return a validated `AIIntent` |
| `AIIntentPrompt.swift` | The one intent prompt for both providers (local civil date, delimited query) |
| `OnDeviceIntentGenerator.swift` | `@Generable` intent for FoundationModels (`#if canImport` + `@available(macOS 26, *)`) |
| `AIDateQueryModel.swift` | Owns ⌘G requests: stale-result dropping, clarifications, result invalidation |
| `AISubmitRouter.swift` | What Return in the AI field means (confirm / allow access / ignore / submit) |
| `CalendarDateSearchRow.swift` | The "Ask Glimpse" field, trailing slot chip and clarification line |
| `AIResultViews.swift` | Answer, range summary and clarification rows |
| `ScheduleProposalView.swift` | Free-time proposal, access rows and the Undo chip |
| `ScheduleCopy.swift` | User-facing and VoiceOver copy for the create flow |
| `ProxyProvider.swift` | Auris proxy REST API integration |
| `ProxyConfig.swift` | XOR-obfuscated app secret, device ID, auth headers |
| `SparkleUpdater.swift` | Inline update UI with SPUUserDriver (all status states) |
| `AboutWindow.swift` | Floating window with version, updates, diagnostics, links |
| `AppDesign.swift` | Design tokens (spacing, colors, corner radius, animation) |
| `AppLogger.swift` | os.Logger categories |

### Core Package (GlimpseCore/)
| Directory | Contents |
|---|---|
| `Features/` | CalendarFeature, ScheduleFeature, PreferencesFeature |
| `Dependencies/` | PreferencesClient, CalendarClient, EventKitClient (read + free-time fetch/save/remove), ScheduleEventsClient (save signal → app closes the AI editor), LaunchAtLoginClient, KeychainClient |
| `Models/` | CalendarDay, CalendarEvent, GridInfo, MenuBarDisplayOptions, AIProvider, CivilDate, AIIntent, AIIntentWire, AIIntentDecoder, DayPhraseParser, DateAnswerer, FreeSlotFinder, ScheduleModels |

## Important Implementation Details

### 1. NSPanel + TextField
`.nonactivatingPanel` prevents SwiftUI TextField from working. Must call `NSApp.activate(ignoringOtherApps: true)` via `panel.activateForTextInput()`. Previous app stored and restored on deactivate.

### 2. Reused Windows and Settings Handoff
`onAppear` does NOT fire when an AppKit window is reused via orderOut/orderFront. Calendar reopening retains its explicit Today reset. Gear and ⌘, share one retained `SettingsWindowController`; each presentation explicitly refreshes its preferences store while preserving pending login operations/errors. Settings handoff cancels deferred calendar editor focus and abandons the previous external-app restoration lease. A pinned calendar keeps its frame, scroll and selection; an unpinned calendar hides. Closing Settings does not reopen the calendar.

### 3. Menu Bar Refresh
`onChange` on TCA `@ObservableState` bindings does NOT reliably fire. PreferencesView uses custom `Binding`s that post `NotificationCenter.menuBarDisplayDidChange`. CalendarStatusItem observes this and calls `updateMenuBarDisplay()`.

### 4. Filled Background Mode
`MenuBarItemRenderer.render(options:dateString:isDark:)` composites either bordered (stroke only) or filled (solid light gray + dark content) into a single `NSImage` set as `button.image`. `DateIconRenderer.render(textColor:)` accepts a color param for the icon text. `StatusItemPreview` renders the identical image so the preferences preview cannot drift. NOTE: do not add a custom NSView to the status button — it causes a CPU redraw loop on macOS 26 (see gotchas.md).

### 5. Key Monitor Eats Enter
`NSEvent.addLocalMonitorForEvents` intercepts keyCode 36 before SwiftUI `onSubmit`. Handle Enter explicitly in the monitor when AI field is active.

### 6. AI Proxy
Uses shared Auris proxy at `proxy.auris.workers.dev/refine` with the `{tier, prompt}` body. App secret is XOR-obfuscated in `ProxyConfig`. Device ID for rate limiting. No API keys needed. The live service answers HTTP 200 with `text: null` on upstream errors; that maps to the generic failure copy.

### 7. Type to Schedule (⌘G intents)
Providers return one JSON intent (navigate, range, question, create, clarify) validated by `AIIntentDecoder`; a bare `yyyy-MM-dd` still navigates. The AI never counts and never sees calendar data: `DateAnswerer` and `FreeSlotFinder` are pure GlimpseCore code. Days the query names ("next Friday", "Mar 1", "next 3 Fridays") are resolved in Swift by `DayPhraseParser` and win over the model's dates; both prompts also carry a 28-day date table. On-device uses a per-intent `@Generable` enum (`GeneratedRequest`). `ScheduleFeature` never preselects a time (Return without a pick is a no-op), never cancels a started save, requests calendar access only from its explicit "Allow calendar access" button (Return in the field never does), keeps the times after a retryable save failure, and offers Undo for 10 s (also ⌘Z outside text editing). A confirmed save sends `.delegate(.eventSaved)`; CalendarFeature calls `ScheduleEventsClient`, whose `.scheduleEventSaved` notification closes the editor (no `onChange`). ↑/↓ (and Return with focus out of the field) pick times through `CalendarKeyboardRouter.slotPicker`, before browse routing. Live provider check: `TEST_RUNNER_GLIMPSE_LIVE_AI=foundationModels[,proxy] xcodebuild … -only-testing:GlimpseTests/AILiveProviderGoldenTests`.

## Storage

| What | Where | Format |
|---|---|---|
| Display options | UserDefaults | Bool per key (showIcon, showDayOfWeek, etc.) |
| Workdays | UserDefaults | `[Int]` array |
| Start of weekday | UserDefaults | `Int` |
| AI settings | UserDefaults | Bool (showAISearch), String (aiProvider) |
| Hotkey combo | UserDefaults | UInt32 (keyCode, modifiers) |
| Launch at login | SMAppService | System managed |

## Release Infrastructure

### Sparkle Auto-Updates via GitHub Releases

- **Feed URL** (in Info.plist): `https://github.com/iRedlof/Glimpse/releases/latest/download/appcast.xml`
- **Sparkle EdDSA public key** (in Info.plist): `r3bpqxl5pEGWf6atYS0ZWP3FZyTVVcFAfDj22fuCioE=`
- **Distribution**: DMG + appcast.xml attached to each GitHub Release

### Release Pipelines

**GitHub Actions (primary — triggered on push to main):**
- `.github/workflows/release.yml`
- Builds → styled DMG → notarize → Sparkle sign → appcast → GitHub Release
- Secrets: `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PWD`, `SPARKLE_PRIVATE_KEY`, `APPLE_ID`, `APPLE_ID_PASSWORD`, `TEAM_ID`

**Local (backup):**
- `GLIMPSE_SIGNING_KEYCHAIN="/absolute/path/signing.keychain-db" ./tools/scripts/preflight.sh` — Checks mandatory machine prerequisites with the same policy-team identity selector; Sparkle metadata only (`--setup` for interactive guided setup, then rerun)
- `./tools/scripts/release-upload.sh` — Builds, signs, creates DMG, generates appcast locally
- Requires an absolute existing `GLIMPSE_SIGNING_KEYCHAIN` containing exactly one valid Developer ID Application identity for the policy team, usable private-key access, the existing `AC_PASSWORD` notarization profile, and the existing Sparkle key.
- Archive and export use the selected certificate SHA with manual signing. Xcode export must already find the selected keychain through its normal search; the helper must not import/unlock credentials or alter keychain search lists/ACLs.
- Signs the final DMG after icon edits and strictly verifies it before notarization. `GLIMPSE_HEADLESS_DMG=1` skips cosmetic Finder automation; `0` is the styled local default. Only `0`/`1` are accepted.
- Retains verified outputs in a unique `local-release.*` directory under the configured build root. Publication uses the gated GitHub workflow.

### DMG Layout

- Icon positions: Glimpse app at (150, 190), Applications at (450, 190)
- Window size: 600×400
- Optional: `tools/resources/AppIcon.icns` for custom DMG volume icon

### GitHub Actions Secrets

| Secret | Purpose |
|---|---|
| `MACOS_CERTIFICATE` | Developer ID .p12 (base64-encoded) |
| `MACOS_CERTIFICATE_PWD` | Password for .p12 |
| `SPARKLE_PRIVATE_KEY` | EdDSA signing for Sparkle updates |
| `APPLE_ID` | Notarization |
| `APPLE_ID_PASSWORD` | Notarization (app-specific password) |
| `TEAM_ID` | Notarization |

### Machine Setup (Local Releases)

| Secret | Scope | Setup |
|---|---|---|
| Developer ID cert | Required for local release artifacts, same across machines | Configure existing certificate/private key in an absolute `GLIMPSE_SIGNING_KEYCHAIN`; keychain must already be usable and discoverable by Xcode export |
| Notarization creds | Required for local release artifacts, re-enter per machine | Existing `AC_PASSWORD` profile |
| Sparkle EdDSA key | Only needed for local releases | Import: `generate_keys --import KEY` |

The Sparkle private key in GitHub Secrets is the source of truth for distribution. Local machines don't need it unless doing local releases. Never run `generate_keys` without `--import` — it creates a new key that breaks updates for existing users.

## Version Bumping

**Before pushing any user-facing change**, bump the version. This triggers the GitHub Actions release workflow.

A "user-facing change" is any feature, bug fix, performance improvement, or UX change — anything that ships to users. Internal-only changes (CI config, docs, dev tooling) do not require a bump.

Update the version in **all 3 locations** (missing any will cause release issues). Use `/bump` to automate this:

1. `Glimpse.xcodeproj/project.pbxproj` → `MARKETING_VERSION` (4 occurrences: Debug/Release × App/Tests)
2. `Glimpse.xcodeproj/project.pbxproj` → `CURRENT_PROJECT_VERSION` (4 occurrences)
3. `README.md` → version badge `[![Version](https://img.shields.io/badge/version-X.Y.Z-green)]`

Build number (`CURRENT_PROJECT_VERSION`) is critical. Sparkle uses it (not marketing version) to determine update ordering. If the build number doesn't increase, users won't see the update. Always increment it.

Commit with: `chore: bump version to X.Y.Z`

Quick reference for the current version and build:
```bash
grep 'MARKETING_VERSION' Glimpse.xcodeproj/project.pbxproj | head -1 | sed 's/[^0-9.]//g'
grep 'CURRENT_PROJECT_VERSION' Glimpse.xcodeproj/project.pbxproj | head -1 | sed 's/[^0-9]//g'
```

## Testing Rules

- All tests use Swift Testing (`@Test`, `#expect`) — no XCTest
- TCA tests use `TestStore` with explicit `withDependencies`
- Provide `$0.date = .constant(...)` for any reducer using `@Dependency(\.date)`
- Provide `$0.eventKitClient.authorizationStatus = { .notDetermined }` for CalendarFeature tests
- Avoid `Result<Void, Error>` in TCA actions — causes Swift compiler crashes

## Git Commit Messages

- Use a concise, descriptive subject line that captures the user-facing impact (roughly 50–70 characters).
- Follow up with as much context as needed in the body. Include the rationale, notable tradeoffs, relevant logs, or reproduction steps.
- Reference any related GitHub issues in the body if the change tracks ongoing work.
- **Do NOT include `Co-Authored-By` trailers** in commit messages.
- Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `chore:`

## File Counts

- App source files: ~40
- GlimpseCore source files: ~21
- Test files: ~45
- Total tests: 212 GlimpseCore + 385 app default run (+ 45 keyboard, 11 AI and 13 agenda key-panel tests in the quality gate; 4 opt-in live AI checks)
