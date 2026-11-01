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

# App tests (18 tests, 3 suites)
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -skipMacroValidation test

# GlimpseCore tests (32 TCA TestStore tests, 3 suites)
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
| `CalendarPanel.swift` | NSPanel (non-activating, pin support, text input, preferences collapse) |
| `CalendarStatusItem.swift` | NSStatusItem, panel positioning, midnight refresh, NotificationCenter observer |
| `MenuBarItemRenderer.swift` | Composites the whole menu bar item (border/filled, icon + separator + text) into one `NSImage` set as `button.image`. No subview — a child view in the status button pegs CPU on macOS 26 (see gotchas.md) |
| `StatusItemPreview.swift` | NSViewRepresentable rendering the same MenuBarItemRenderer image for the SwiftUI preferences preview |
| `CalendarPopoverView.swift` | Main calendar UI, date selection, AI field, events, footer with quit confirm |
| `PreferencesView.swift` | Grouped cards layout (Display, Calendar, Features) |
| `MonthBorderShape.swift` | Contoured month border (SwiftUI Shape) |
| `DateIconRenderer.swift` | Date number + red accent menu bar icon, configurable text color |
| `GlobalHotkey.swift` | Carbon EventHotKey, configurable combo with persistence |
| `AIDateHelper.swift` | Routes between proxy API and FoundationModels |
| `ProxyProvider.swift` | Auris proxy REST API integration |
| `ProxyConfig.swift` | XOR-obfuscated app secret, device ID, auth headers |
| `SparkleUpdater.swift` | Inline update UI with SPUUserDriver (all status states) |
| `AboutWindow.swift` | Floating window with version, updates, diagnostics, links |
| `AppDesign.swift` | Design tokens (spacing, colors, corner radius, animation) |
| `AppLogger.swift` | os.Logger categories |

### Core Package (GlimpseCore/)
| Directory | Contents |
|---|---|
| `Features/` | CalendarFeature, PreferencesFeature, MenuBarFeature |
| `Dependencies/` | PreferencesClient, CalendarClient, EventKitClient, LaunchAtLoginClient |
| `Models/` | CalendarDay, CalendarEvent, GridInfo, MenuBarDisplayOptions, AIProvider |

## Important Implementation Details

### 1. NSPanel + TextField
`.nonactivatingPanel` prevents SwiftUI TextField from working. Must call `NSApp.activate(ignoringOtherApps: true)` via `panel.activateForTextInput()`. Previous app stored and restored on deactivate.

### 2. Preferences Collapse on Reopen
`onAppear` does NOT fire when NSPanel is reused via orderOut/orderFront. `CalendarPanel` stores a reference to the TCA store and `collapsePreferencesIfNeeded()` is called from `CalendarStatusItem.showPanel()`.

### 3. Menu Bar Refresh
`onChange` on TCA `@ObservableState` bindings does NOT reliably fire. PreferencesView uses custom `Binding`s that post `NotificationCenter.menuBarDisplayDidChange`. CalendarStatusItem observes this and calls `updateMenuBarDisplay()`.

### 4. Filled Background Mode
`MenuBarItemRenderer.render(options:dateString:isDark:)` composites either bordered (stroke only) or filled (solid light gray + dark content) into a single `NSImage` set as `button.image`. `DateIconRenderer.render(textColor:)` accepts a color param for the icon text. `StatusItemPreview` renders the identical image so the preferences preview cannot drift. NOTE: do not add a custom NSView to the status button — it causes a CPU redraw loop on macOS 26 (see gotchas.md).

### 5. Key Monitor Eats Enter
`NSEvent.addLocalMonitorForEvents` intercepts keyCode 36 before SwiftUI `onSubmit`. Handle Enter explicitly in the monitor when AI field is active.

### 6. AI Proxy
Uses shared Auris proxy at `proxy.auris.workers.dev/refine`. App secret is XOR-obfuscated in `ProxyConfig`. Device ID for rate limiting. No API keys needed.

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
- `./tools/scripts/preflight.sh` — Checks all prerequisites (`--setup` for interactive guided setup)
- `./tools/scripts/release-upload.sh` — Builds, signs, creates DMG, generates appcast locally
- If Developer ID available: adds notarization + clean DMG background. If not: Sparkle EdDSA only.

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
| Developer ID cert | Optional, same across machines | Xcode → Accounts → Manage Certificates |
| Notarization creds | Optional, re-enter per machine | `xcrun notarytool store-credentials "AC_PASSWORD"` |
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

- App source files: ~17
- GlimpseCore source files: ~12
- Test files: 6
- Total tests: 50
