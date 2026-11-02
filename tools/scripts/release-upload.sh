#!/bin/bash
set -euo pipefail

# Glimpse Local Release Script
# Builds, signs, creates DMG, generates Sparkle appcast.
# The DMG + appcast are output to a unique local-release.* directory under
# GLIMPSE_BUILD_ROOT (or the configured/default build root) for local inspection.
# Publication uses the gated GitHub workflow.
#
# Usage:
#   GLIMPSE_SIGNING_KEYCHAIN="/absolute/path/signing.keychain-db" ./tools/scripts/release-upload.sh
# Optional: GLIMPSE_HEADLESS_DMG=1 skips cosmetic Finder automation.
#
# Developer ID and notarization are required for release artifacts.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
python3 "$SCRIPT_DIR/release-control.py" gate
python3 "$SCRIPT_DIR/release-control.py" readiness
test -z "$(git status --porcelain)" || { echo "Release artifacts require a clean committed source"; exit 1; }
SOURCE_SHA="$(git rev-parse HEAD)"
BUILD_NUMBER="$(python3 "$SCRIPT_DIR/release-control.py" version | python3 -c 'import json,sys; print(json.load(sys.stdin)["build"])')"
HEADLESS_DMG="${GLIMPSE_HEADLESS_DMG-0}"
case "$HEADLESS_DMG" in
  0|1) ;;
  *) echo "GLIMPSE_HEADLESS_DMG must be 0 or 1"; exit 1 ;;
esac
SIGNING_KEYCHAIN="${GLIMPSE_SIGNING_KEYCHAIN:-}"
if [[ "$SIGNING_KEYCHAIN" != /* || ! -f "$SIGNING_KEYCHAIN" ]]; then
  echo "GLIMPSE_SIGNING_KEYCHAIN must name an absolute existing signing keychain file"
  exit 1
fi
TEAM_ID="$(python3 -c 'import json; print(json.load(open(".github/release-policy.json"))["team_id"])')"
SIGNING_IDENTITY="$(python3 "$SCRIPT_DIR/select-signing-identity.py" --keychain "$SIGNING_KEYCHAIN" --team-id "$TEAM_ID")"

VERSION=$(grep 'MARKETING_VERSION' Glimpse.xcodeproj/project.pbxproj | head -1 | sed 's/[^0-9.]//g')
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/artifacts/sparkle/Sparkle/bin" -maxdepth 6 2>/dev/null | head -1)
if [ -z "$SPARKLE_BIN" ]; then
  echo "❌ Sparkle bin not found in DerivedData — build the project first"
  exit 1
fi
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
BUILD_ROOT="${GLIMPSE_BUILD_ROOT:-$(git config --get glimpse.buildRoot || true)}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build}"
mkdir -p "$BUILD_ROOT"
BUILD_DIR="$(mktemp -d "$BUILD_ROOT/local-release.XXXXXX")"
REPOSITORY="$(python3 -c 'import json; print(json.load(open(".github/release-policy.json"))["repository"])')"
DOWNLOAD_URL_PREFIX="https://github.com/${REPOSITORY}/releases/download/v${VERSION}"

# Resolve paths (script may be called from project root)
RESOURCES_DIR="$SCRIPT_DIR/../resources"

# Check the existing notarization profile without changing local credentials.
HAS_NOTARIZATION=false
if xcrun notarytool history --keychain-profile "AC_PASSWORD" &>/dev/null 2>&1; then
  HAS_NOTARIZATION=true
fi

if ! $HAS_NOTARIZATION; then
  echo "Notarization profile AC_PASSWORD is required; release preparation stopped"
  exit 1
fi
GLIMPSE_BUILD_ROOT="$BUILD_ROOT" "$SCRIPT_DIR/quality-gate.sh"

echo "=== Glimpse Release v${VERSION} ==="
echo ""
echo "  Developer ID:  ✅ Selected for policy team"
echo "  Notarization:  ✅ Available"
echo ""

# Clean build directory
cp Glimpse/Info.plist "$BUILD_DIR/ReleaseInfo.plist"
python3 - "$BUILD_DIR/ReleaseInfo.plist" "$SOURCE_SHA" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
info["GlimpseSourceSHA"] = sys.argv[2]
with open(sys.argv[1], "wb") as target:
    plistlib.dump(info, target)
PY

if ! command -v create-dmg &>/dev/null; then
  echo "❌ create-dmg not found — install with: brew install create-dmg"
  exit 1
fi

EXPORT_METHOD="developer-id"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building: Glimpse"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Step 1: Archive
echo "📦 Archiving..."
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Release \
  -skipMacroValidation \
  -disableAutomaticPackageResolution \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--keychain \"$SIGNING_KEYCHAIN\"" \
  INFOPLIST_FILE="$BUILD_DIR/ReleaseInfo.plist" \
  archive -archivePath "$BUILD_DIR/archive.xcarchive" \
  -quiet

# Step 2: Export
echo "📤 Exporting..."
python3 - "$BUILD_DIR/ExportOptions.plist" "$EXPORT_METHOD" "$SIGNING_IDENTITY" "$TEAM_ID" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as target:
    plistlib.dump({
        "method": sys.argv[2],
        "signingStyle": "manual",
        "signingCertificate": sys.argv[3],
        "teamID": sys.argv[4],
    }, target)
PY

xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/archive.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -quiet

APP_PATH="$BUILD_DIR/export/Glimpse.app"
if [ ! -d "$APP_PATH" ]; then
  echo "❌ Export failed — app not found at $APP_PATH"
  exit 1
fi
echo "✅ Export complete (method: ${EXPORT_METHOD})"

# Step 3: Notarize
echo "🔏 Notarizing app..."
codesign -dvv "$APP_PATH" 2>&1 | grep -E "Authority|Runtime"
ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/Glimpse.zip"
xcrun notarytool submit "$BUILD_DIR/Glimpse.zip" \
  --keychain-profile "AC_PASSWORD" \
  --wait
echo "📌 Stapling..."
xcrun stapler staple "$APP_PATH"
echo "✅ Notarization complete"

# Step 4: Create DMG
echo "💿 Creating DMG..."
DMG_NAME="Glimpse-${VERSION}.dmg"
rm -f "$BUILD_DIR/$DMG_NAME"

DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"

DMG_ARGS=(
  --volname "Glimpse"
  --window-pos 200 120
  --window-size 600 400
  --icon-size 100
  --icon "Glimpse.app" 150 190
  --app-drop-link 450 190
  --hide-extension "Glimpse.app"
  --no-internet-enable
)
if [ "$HEADLESS_DMG" = 1 ]; then
  DMG_ARGS+=(--skip-jenkins)
fi

# Add optional resources if they exist
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
  DMG_ARGS+=(--volicon "$RESOURCES_DIR/AppIcon.icns")
fi
create-dmg "${DMG_ARGS[@]}" "$BUILD_DIR/$DMG_NAME" "$DMG_STAGING"

# Set custom file icon on the DMG (if AppIcon available)
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
  ICON_RSRC=$(mktemp)
  sips -i "$RESOURCES_DIR/AppIcon.icns" >/dev/null 2>&1
  DeRez -only icns "$RESOURCES_DIR/AppIcon.icns" > "$ICON_RSRC" 2>/dev/null
  Rez -append "$ICON_RSRC" -o "$BUILD_DIR/$DMG_NAME" 2>/dev/null
  SetFile -a C "$BUILD_DIR/$DMG_NAME" 2>/dev/null
  rm -f "$ICON_RSRC"
fi

echo "🔏 Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" \
  --timestamp "$BUILD_DIR/$DMG_NAME"
codesign --verify --strict --verbose=2 "$BUILD_DIR/$DMG_NAME"

echo "🔏 Notarizing DMG..."
xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
  --keychain-profile "AC_PASSWORD" \
  --wait
xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
echo "✅ DMG notarized"

# Step 5: Sign for Sparkle
echo "✏️  Signing for Sparkle..."
"$SIGN_UPDATE" "$BUILD_DIR/$DMG_NAME"

# Step 6: Generate appcast
echo "📋 Generating appcast..."
mkdir -p "$BUILD_DIR/appcast_source"
cp "$BUILD_DIR/$DMG_NAME" "$BUILD_DIR/appcast_source/"

"$GENERATE_APPCAST" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX/" \
  "$BUILD_DIR/appcast_source"

cp "$BUILD_DIR/appcast_source/appcast.xml" "$BUILD_DIR/appcast.xml"
echo "✅ Appcast generated"
"$SCRIPT_DIR/verify-dmg.sh" "$BUILD_DIR" "$VERSION" "$BUILD_NUMBER" "$SOURCE_SHA"

# ─── Summary ───
echo ""
echo "═══════════════════════════════════════"
echo "  Release v${VERSION} Complete"
echo "═══════════════════════════════════════"
echo "  DMG:     $BUILD_DIR/$DMG_NAME"
echo "  Appcast: $BUILD_DIR/appcast.xml"
echo "  Signed:  ✅ Developer ID + Notarized"
echo ""
echo "  Next steps:"
echo "    Publish through the main-branch GitHub Release workflow after completed review."
echo ""
