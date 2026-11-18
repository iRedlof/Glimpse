# Sparkle in-app update installs in the sandbox (v1.5.2/build39)

## Product authority

On 2026-11-17 the owner reported that Glimpse finds an update but clicking Update does nothing.

## Cause

Glimpse has been sandboxed since its first release (`com.apple.security.app-sandbox`). Sparkle 2's sandboxing support needs two things to launch its installer, and neither was present, so an update could be found and downloaded but never installed:
- `SUEnableInstallerLauncherService = YES` in Info.plist.
- The `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `-spki` mach-lookup temporary exceptions in the entitlements.

The app already has `network.client`, so Sparkle's downloader service isn't needed.

## Change

- Info.plist: `SUEnableInstallerLauncherService` is true.
- Glimpse.entitlements: `com.apple.security.temporary-exception.mach-lookup.global-name` lists `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`.

## Verification

- **Code:** `SparkleSandboxInstallTests` checks the running app's Info.plist key and its signed entitlements, using `SecTaskCopyValueForEntitlement`. Both tests failed before the change and pass after it.
- **QA:** GlimpseCore and app suites pass, plus the pre-commit quality gate.
- **UX:** no visible change other than Update now installing.

Installs that already have 1.5.1 or older lack the fix, so they have to install 1.5.2 from the DMG. The first update that can install in-app is 1.5.2 → 1.5.3.
