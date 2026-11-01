# Glimpse

[![Version](https://img.shields.io/badge/version-1.4.3-green)](https://github.com/iRedlof/Glimpse/releases/latest)
[![Download](https://img.shields.io/badge/download-DMG-brightgreen)](https://github.com/iRedlof/Glimpse/releases/latest)

[![Release](https://github.com/iRedlof/Glimpse/actions/workflows/release.yml/badge.svg)](https://github.com/iRedlof/Glimpse/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](https://github.com/iRedlof/Glimpse/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)]()

A lightweight macOS menu bar calendar app. Click the date icon to see the current month at a glance.

## Features

- **Menu bar popover** with month grid, week numbers, and contoured month border
- **Date selection** — click any day to see full date info and week number
- **AI date search** — press ⌘G and type "next Friday" or "Christmas"
- **Today's events** — EventKit integration shows calendar events in the popover
- **Global hotkey** — configurable shortcut (default ⌘⇧C) to toggle from anywhere
- **Customizable menu bar** — toggle icon, day, month, date, year with live preview
- **Filled background mode** — solid pill style for the menu bar item
- **Workday highlighting** — configure which days are workdays
- **Pin window** — keep the calendar visible while working
- **Grouped preferences** — Display, Calendar, Features cards with branded divider
- **Auto-updates** — Sparkle with inline status in About window
- **Shortcuts.app** — "Show Glimpse Calendar" available via Siri and Shortcuts
- **Launch at login** — via macOS SMAppService

## Setup

1. Download the latest release from [GitHub Releases](https://github.com/iRedlof/Glimpse/releases/latest)
2. Move `Glimpse.app` to `/Applications`
3. Launch — the date icon appears in the menu bar
4. Click it to see the calendar, click the gear icon for preferences

## Architecture

Built with [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) (TCA) and Swift 6 strict concurrency.

- `CalendarFeature` → month navigation, date selection, events, AI
- `PreferencesFeature` → all preference state with delegate actions
- `MenuBarFeature` → display options, date string formatting
- `@Dependency` clients: `PreferencesClient`, `CalendarClient`, `EventKitClient`, `LaunchAtLoginClient`
- `@Dependency(\.date)` for deterministic reducer testing
- `AppDesign` tokens for spacing, corner radius, colors, animation
- `os.Logger` via `AppLogger` for diagnostics

## Requirements

- macOS 14.0 (Sonoma) or later, Apple Silicon
- macOS 26.0 (Tahoe) for on-device AI date search
- Xcode 16+
- Swift 6.0

## Development

### Building

Open in Xcode (recommended):

```bash
open Glimpse.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Release -skipMacroValidation build
```

> `-skipMacroValidation` is required for TCA macro plugins.

### Testing

```bash
# App tests (18 tests)
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -skipMacroValidation test

# GlimpseCore tests (32 TCA TestStore tests)
cd GlimpseCore && swift test
```

50 tests total (18 app + 32 GlimpseCore). All use Swift Testing (`@Test`, `#expect`) — no XCTest.

### Code Signing

The project uses `CODE_SIGN_STYLE = Automatic`. Debug builds sign with "Apple Development" — make sure you have a valid Apple Development certificate in your keychain and your team is selected in Xcode's Signing & Capabilities tab.

> **Tip:** If you get repeated permission prompts during debug, ensure the signing identity is "Apple Development" so TCC entries persist across builds.

## Project Structure

```
Glimpse/                             # App target
├── GlimpseApp.swift                 # @main entry, AppDelegate
├── CalendarPanel.swift              # NSPanel (non-activating, pin, text input)
├── CalendarStatusItem.swift         # NSStatusItem, positioning, midnight refresh
├── StatusItemView.swift             # Menu bar rendering (bordered/filled)
├── StatusItemPreview.swift          # NSViewRepresentable for preferences preview
├── CalendarPopoverView.swift        # SwiftUI calendar, date selection, AI field
├── PreferencesView.swift            # Grouped cards preferences (Display/Calendar/Features)
├── MonthBorderShape.swift           # Contoured month border (SwiftUI Shape)
├── DateIconRenderer.swift           # Date number + red accent menu bar icon
├── GlobalHotkey.swift               # Carbon EventHotKey, configurable combo
├── AppIntents.swift                 # Shortcuts.app integration
├── AIDateHelper.swift               # AI date parsing (proxy + FoundationModels)
├── ProxyProvider.swift              # Auris proxy API integration
├── ProxyConfig.swift                # XOR-obfuscated auth
├── SparkleUpdater.swift             # Inline update UI with SPUUserDriver
├── AboutWindow.swift                # Version, updates, diagnostics
├── AppDesign.swift                  # Design tokens
├── AppLogger.swift                  # os.Logger categories
├── PrivacyInfo.xcprivacy
├── Info.plist
├── Glimpse.entitlements
└── Assets.xcassets/

GlimpseCore/                         # Local Swift Package (business logic)
├── Sources/GlimpseCore/
│   ├── Dependencies/                # PreferencesClient, CalendarClient,
│   │                                # EventKitClient, LaunchAtLoginClient
│   ├── Features/                    # CalendarFeature, PreferencesFeature,
│   │                                # MenuBarFeature
│   └── Models/                      # CalendarDay, CalendarEvent, GridInfo,
│                                    # MenuBarDisplayOptions, AIProvider
└── Tests/GlimpseCoreTests/          # 32 TCA TestStore tests

GlimpseTests/                        # 18 app-level tests

tools/
├── scripts/
│   ├── preflight.sh                 # Machine readiness check (--setup for interactive guided setup)
│   └── release-upload.sh            # Build → sign → notarize → create DMG
└── resources/
    └── AppIcon.icns                 # App icon for DMG volume icon
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧C (configurable) | Toggle calendar from anywhere |
| ← → | Previous / next month |
| ↑ ↓ | Previous / next year |
| Enter | Go to today |
| Escape | Close preferences or calendar |
| ⌘G | AI date search |

## Permissions

| Permission | Why | When Requested |
|---|---|---|
| **Calendar** | Show today's events (EventKit) | Click "Show today's events" |

No other permissions required. The app runs as a menu bar accessory (no dock icon).

## Releasing

Releases are distributed via GitHub Releases. Push a version bump to `main` and GitHub Actions builds a signed, notarized DMG and creates the release automatically.

### New Machine Setup

When setting up a new development Mac for releases:

```bash
# Check what's missing
./tools/scripts/preflight.sh

# Or run interactive guided setup (walks you through each missing item)
./tools/scripts/preflight.sh --setup
```

This verifies all prerequisites and tells you exactly what's missing. With `--setup`, it prompts you to configure each missing item interactively.

#### 1. Developer ID Certificate

Open Xcode → Settings → Accounts → sign in with your Apple ID. Xcode downloads certificates automatically. Verify:

```bash
security find-identity -v -p codesigning | grep "Developer ID"
```

#### 2. Notarization Credentials

Store your Apple notarization credentials in the Keychain (one-time per machine):

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com/account/manage) → Sign-In and Security → App-Specific Passwords.

#### 3. Sparkle EdDSA Signing Key

The Sparkle private key must be in your Keychain for update signing. **This is the most critical secret** — if lost, existing users can't verify updates.

**Import from backup** (preferred):
```bash
# Find generate_keys in DerivedData (build the project first)
find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" -path "*/artifacts/*" -type f

# Import the backed-up private key
/path/to/generate_keys --import YOUR_PRIVATE_KEY_BASE64
```

**Export for backup** (do this on your current machine):
```bash
security find-generic-password -s "https://sparkle-project.org" -a "ed25519" -w
```

Save the output in your password manager. This one string restores signing on any Mac.

### Version Bumping

**Before pushing any user-facing change**, bump the version. This triggers the GitHub Actions release workflow.

Update the version in **all 3 locations** (missing any will break the release). Use `/bump` to automate this:

1. `Glimpse.xcodeproj/project.pbxproj` → `MARKETING_VERSION` (4 occurrences: Debug/Release × App/Tests)
2. `Glimpse.xcodeproj/project.pbxproj` → `CURRENT_PROJECT_VERSION` (4 occurrences — must match build number)
3. `README.md` → version badge

Build number (`CURRENT_PROJECT_VERSION`) is critical — Sparkle uses it (not marketing version) to determine update ordering. Always increment it.

Commit with: `chore: bump version to X.Y.Z`

### How to Release

#### GitHub Actions (Primary — triggered on push to main)

1. Bump version in all 3 locations (use `/bump`)
2. Commit: `git commit -m "chore: bump version to X.Y.Z"`
3. Push to main → GitHub Actions builds and releases automatically

#### Local Script (Backup)

```bash
# 1. Verify machine is ready (use --setup on first time)
./tools/scripts/preflight.sh --setup

# 2. Bump version
# Use /bump or manually update the 3 locations

# 3. Build, sign, notarize, create DMG
./tools/scripts/release-upload.sh

# 4. Commit, tag, and push
git add -A && git commit -m "chore: bump version to X.Y.Z"
git tag v$(grep 'MARKETING_VERSION' Glimpse.xcodeproj/project.pbxproj | head -1 | sed 's/[^0-9.]//g')
git push origin main --tags

# 5. Create GitHub Release with the built artifacts
gh release create v${VERSION} build/release/Glimpse-*.dmg build/release/appcast.xml --title v${VERSION} --generate-notes
```

### What the Release Pipeline Does

1. Archives with `xcodebuild -scheme Glimpse -configuration Release`
2. Exports and signs with Developer ID + hardened runtime
3. Notarizes app + staples
4. Creates styled DMG via `create-dmg` with background image
5. Notarizes DMG
6. Signs DMG with Sparkle EdDSA key
7. Generates appcast.xml with `generate_appcast`
8. Creates GitHub Release with DMG + appcast.xml attached

### Release Artifacts

Each GitHub Release contains:

| File | Purpose |
|---|---|
| `Glimpse-{version}.dmg` | Styled DMG (signed + notarized) |
| `appcast.xml` | Sparkle update feed |

### Required Secrets

| Secret | Purpose |
|---|---|
| `MACOS_CERTIFICATE` | Developer ID .p12 (base64-encoded) |
| `MACOS_CERTIFICATE_PWD` | Password for .p12 |
| `SPARKLE_PRIVATE_KEY` | EdDSA signing for Sparkle updates |
| `APPLE_ID` | Notarization |
| `APPLE_ID_PASSWORD` | Notarization (app-specific password) |
| `TEAM_ID` | Notarization |

### Troubleshooting

Run preflight to diagnose issues:
```bash
./tools/scripts/preflight.sh          # Check only
./tools/scripts/preflight.sh --setup  # Interactive fix for each failure
```

Common problems:
- **"Developer ID certificate not found"** — Open Xcode, sign in, let it download certificates
- **"Notarization credentials not configured"** — Run `xcrun notarytool store-credentials`
- **"Sparkle EdDSA private key not in Keychain"** — Import from backup (see above)

## Deferred Items

These are known issues intentionally deferred. See `.claude/rules/known-issues.md` for details.

## License

MIT

## Author

[Rohit Chandani](https://rlchandani.dev/)
