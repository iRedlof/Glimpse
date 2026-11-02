# Glimpse

[![Version](https://img.shields.io/badge/version-1.4.5-green)](https://github.com/iRedlof/Glimpse/releases/latest)
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
- **Selected-day events** — EventKit integration shows events for the chosen day, with loading and retry states
- **Global hotkey** — configurable shortcut (default ⌘⇧C) to toggle from anywhere
- **Customizable menu bar** — toggle icon, day, month, date, year with live preview
- **Filled background mode** — solid pill style for the menu bar item
- **Workday highlighting** — configure which days are workdays
- **Pin window** — keep the calendar visible while working
- **Grouped preferences** — Display, Calendar, Features cards with branded divider
- **Auto-updates** — Sparkle with inline status in About window
- **Shortcuts.app** — "Show Glimpse Calendar" available via Siri and Shortcuts
- **Launch at login** — actual macOS registration status, with a shortcut to approve it in Login Items

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
# Full quality gate: tooling contracts, dependency pins, app and core tests
tools/scripts/quality-gate.sh

# Core tests only
cd GlimpseCore && swift test --force-resolved-versions
```

The Swift suites currently run 57 app tests and 62 core tests. They use Swift Testing
(`@Test`, `#expect`). Python fixture tests exercise release verification, recovery,
and runtime monitoring. Both Swift dependency lockfiles are checked in and must stay aligned.

See [runtime monitoring](docs/monitoring.md), [QA baseline](docs/qa-baseline.md),
and [stability roadmap](docs/stability-roadmap.md) for observation scope and acceptance criteria.

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
└── Tests/GlimpseCoreTests/           # Reducer and dependency regression tests

GlimpseTests/                        # App-level Swift Testing suites

tools/
├── scripts/
│   ├── preflight.sh                 # Machine readiness check (--setup for interactive guided setup)
│   ├── quality-gate.sh              # Tooling, app and core validation
│   ├── release-control.py           # Previous release, readiness, recovery gates
│   └── release-upload.sh            # Build → sign → notarize → create DMG
├── monitoring/
│   └── health-check.py              # Bounded process and retained crash observations
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
| **Calendar** | Show selected-day events (EventKit) | Click "Show calendar events" |

No other permissions required. The app runs as a menu bar accessory (no dock icon).

## Releasing

GitHub Actions tests every introduced commit and the pull request merge result. A protected merge to `main` then runs the serialized Release workflow. App releases require passing app/core and tooling checks, a higher marketing version and Sparkle build number, and completed product, UX, code, and QA evidence in `.github/release-readiness.json`.

Update all four `MARKETING_VERSION` settings, all four `CURRENT_PROJECT_VERSION` settings, and the README version badge together. Build numbers determine Sparkle update ordering and must increase. Documentation and developer tooling changes can keep the existing version when the controller proves they contain no app changes; they still run quality and final verification.

The workflow signs and notarizes the app and DMG using the existing distribution credentials, embeds the exact source SHA, and verifies bundle identity, version/build, signing team, notarization, Gatekeeper acceptance, and the Sparkle signature. It creates a draft at that SHA, downloads and verifies its artifacts, publishes, and checks anonymous public downloads and the latest feed. The final verification job and whole workflow must succeed before the next protected merge is admitted.

Each release contains `Glimpse-{version}.dmg`, `appcast.xml`, and `release-manifest.json`, which binds source, workflow attempt, and artifact digests. CI preserves per-commit SHA records, full test logs, result bundles, release metrics, and recovery evidence.

Install the local commit/push gates in each checkout:

```bash
./tools/scripts/install-release-hooks.sh
```

The hooks query GitHub on every operation and block while the preceding remote release is pending or unverified. Pre-commit requires all source changes staged, tests an archive of the exact index, and rejects changes made while tests run. Hooks apply only to configured checkouts and can be bypassed with Git options or configuration. Hosted enforcement requires strict up-to-date pull requests, the required GitHub Actions checks `Previous release verified`, `Release tooling checks`, and `App and core tests`, and removal of direct-push/admin bypass. The admission controller comes from trusted main; first installation uses an exact administrator-pinned audited implementation commit. See [release automation](docs/release-automation.md) for setup and bootstrap details.

Coordinate manual Release dispatches/reruns while merges are paused. A run at unchanged main cannot invalidate an already-green pull request through static branch checks; an absolute hosted lock during those manual operations needs a dynamic merge coordinator or administrator-managed lock.

Failures keep the previous release available. Publication or public-health failures re-draft only the release owned by that workflow. The Release Recovery workflow verifies the restored distribution and records the exact failed run/SHA before allowing remediation commits. GitHub outages keep admission closed until verified recovery completes. A withdrawn version already installed by a client requires a corrected higher build; withdrawal cannot downgrade it.

For local validation or release preparation:

```bash
./tools/scripts/quality-gate.sh
GLIMPSE_SIGNING_KEYCHAIN="/absolute/path/existing signing.keychain-db" ./tools/scripts/preflight.sh
GLIMPSE_SIGNING_KEYCHAIN="/absolute/path/existing signing.keychain-db" ./tools/scripts/release-upload.sh
```

The local release script requires clean committed source, completed readiness, the previous-release gate, all quality checks, existing Developer ID/Sparkle credentials, and the `AC_PASSWORD` notarization profile. Set `GLIMPSE_SIGNING_KEYCHAIN` to an absolute existing keychain file containing exactly one valid Developer ID Application identity for the team in `.github/release-policy.json`. That keychain and its private key must already be usable and available to Xcode's normal export search. The helper selects the exact certificate SHA for archive, export, and DMG signing; it does not import certificates, unlock keychains, or change their search list or access controls.

Preflight uses the same keychain and policy-team identity selector. Missing notarization, executable Sparkle tools, `create-dmg`, or authenticated GitHub CLI access fails the check. Its Sparkle check reads key-entry metadata; the release helper verifies the final signature and enforces source admission, readiness and quality. Rerun preflight after any interactive `--setup` changes.

Local packaging uses the styled Finder layout by default. Set `GLIMPSE_HEADLESS_DMG=1` to skip cosmetic Finder automation with `create-dmg --skip-jenkins`; both modes retain the app and Applications link. The setting accepts only `0` or `1`.

Verified artifacts remain in a unique `local-release.*` directory for inspection; publication goes through the GitHub workflow. Use `GLIMPSE_BUILD_ROOT` or worktree configuration `glimpse.buildRoot` to put that directory on suitable storage. The GitHub Actions variable `GLIMPSE_BUILD_ROOT` configures the trusted runner's storage.

Required GitHub secrets are `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PWD`, `SPARKLE_PRIVATE_KEY`, `APPLE_ID`, `APPLE_ID_PASSWORD`, and `TEAM_ID`. Restore existing signing credentials from their secure backup when setting up another release machine. Do not replace the Sparkle key used by installed clients.

## Deferred Items

These are known issues intentionally deferred. See `.claude/rules/known-issues.md` for details.

## License

MIT

## Author

[Rohit Chandani](https://rlchandani.dev/)
