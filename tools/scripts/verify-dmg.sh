#!/bin/bash
# Mount only the downloaded artifact; never install or launch it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACT_DIR="${1:?artifact directory required}"
VERSION="${2:?version required}"
BUILD_NUMBER="${3:?build required}"
SOURCE_SHA="${4:-}"
DMG="$ARTIFACT_DIR/Glimpse-$VERSION.dmg"
MOUNT_DIR="$(mktemp -d)"
mounted=false
cleanup() {
  if $mounted; then hdiutil detach "$MOUNT_DIR" >/dev/null; fi
  rmdir "$MOUNT_DIR"
}
trap cleanup EXIT
xcrun stapler validate "$DMG"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG" >/dev/null
mounted=true
APP="$MOUNT_DIR/Glimpse.app"
test -d "$APP"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
codesign -dvv "$APP" 2>"$ARTIFACT_DIR/signing-verification.txt"
python3 - "$APP" "$VERSION" "$BUILD_NUMBER" "$SOURCE_SHA" "$ROOT" "$ARTIFACT_DIR" <<'PY'
import importlib.util, json, pathlib, plistlib, sys
app, version, build, sha, root, directory = sys.argv[1:]
root, directory = pathlib.Path(root), pathlib.Path(directory)
policy = json.loads((root / ".github/release-policy.json").read_text())
with open(pathlib.Path(app) / "Contents/Info.plist", "rb") as source:
    info = plistlib.load(source)
expected = {
    "CFBundleIdentifier": policy["bundle_id"],
    "CFBundleShortVersionString": version, "CFBundleVersion": build,
    "SUPublicEDKey": policy["sparkle_public_key"],
    "SUFeedURL": f"https://github.com/{policy['repository']}/releases/latest/download/appcast.xml",
}
if sha:
    expected["GlimpseSourceSHA"] = sha
for name, value in expected.items():
    if info.get(name) != value:
        raise SystemExit(f"Downloaded app identity mismatch: {name}")
signing = (directory / "signing-verification.txt").read_text()
if f"TeamIdentifier={policy['team_id']}" not in signing or "Authority=Developer ID Application:" not in signing:
    raise SystemExit("Downloaded app signing identity mismatch")
if "(runtime)" not in signing:
    raise SystemExit("Downloaded app lacks hardened runtime")
spec = importlib.util.spec_from_file_location("release_control", root / "tools/scripts/release-control.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)
dmg = directory / f"Glimpse-{version}.dmg"
signature = control.validate_feed((directory / "appcast.xml").read_bytes(),
                                 policy["repository"], version, build, dmg.stat().st_size)
(directory / "sparkle-signature.txt").write_text(signature)
PY
PUBLIC_KEY="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sparkle_public_key"])' "$ROOT/.github/release-policy.json")"
SIGNATURE="$(cat "$ARTIFACT_DIR/sparkle-signature.txt")"
swift "$SCRIPT_DIR/verify-sparkle.swift" "$PUBLIC_KEY" "$SIGNATURE" "$DMG"
