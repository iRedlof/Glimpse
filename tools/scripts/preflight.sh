#!/bin/bash
# Glimpse Release Preflight Check
# Verifies machine prerequisites for the gated local release helper.
#
# Usage:
#   GLIMPSE_SIGNING_KEYCHAIN="/absolute/path/signing.keychain-db" ./tools/scripts/preflight.sh
# Add --setup for interactive guided setup using existing credentials.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_MODE=false
[ "${1:-}" = "--setup" ] && SETUP_MODE=true

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }
info() { echo "     $1"; }

echo "=== Glimpse Release Preflight Check ==="
echo ""

# ─── 1. Xcode ───
echo "Xcode:"
if xcodebuild -version &>/dev/null; then
  pass "$(xcodebuild -version | head -1)"
else
  fail "Xcode not installed"
  info "Install from the Mac App Store or: xcode-select --install"
fi

# ─── 2. Developer ID Certificate ───
echo ""
echo "Code Signing:"
SIGNING_KEYCHAIN="${GLIMPSE_SIGNING_KEYCHAIN:-}"
if [[ "$SIGNING_KEYCHAIN" != /* || ! -f "$SIGNING_KEYCHAIN" ]]; then
  fail "GLIMPSE_SIGNING_KEYCHAIN must name an absolute existing signing keychain file"
  info "Configure the existing Developer ID certificate/private key for the release-policy team."
elif ! command -v python3 &>/dev/null; then
  fail "Python 3 is required for policy and signing-identity validation"
elif ! TEAM_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["team_id"])' \
  "$ROOT/.github/release-policy.json" 2>/dev/null)"; then
  fail "Cannot read the team from .github/release-policy.json"
elif SIGNING_IDENTITY="$(python3 "$SCRIPT_DIR/select-signing-identity.py" \
  --keychain "$SIGNING_KEYCHAIN" --team-id "$TEAM_ID" 2>/dev/null)"; then
  pass "Policy-team Developer ID Application identity found ($SIGNING_IDENTITY)"
  info "The keychain/private key must already be usable and discoverable by Xcode export."
else
  fail "Expected exactly one valid Developer ID Application identity for the policy team"
  info "Check the existing signing keychain and certificate; preflight does not import or unlock them."
fi

# ─── 3. Notarization Credentials ───
echo ""
echo "Notarization:"
if xcrun notarytool history --keychain-profile "AC_PASSWORD" &>/dev/null 2>&1; then
  pass "AC_PASSWORD keychain profile found"
else
  fail "Required AC_PASSWORD notarization profile is unavailable"
  info ""
  info "For the existing Apple Developer account, you need:"
  info "  - Your Apple ID"
  info "  - Your Team ID (find at developer.apple.com → Membership)"
  info "  - An app-specific password (NOT your Apple ID password)"
  info ""
  info "Step 1: Generate an app-specific password:"
  info "  Go to https://appleid.apple.com/account/manage"
  info "  → Sign-In and Security → App-Specific Passwords → Generate"
  info ""
  info "Step 2: Store in Keychain:"
  info "  xcrun notarytool store-credentials \"AC_PASSWORD\" \\"
  info "    --apple-id YOUR_APPLE_ID \\"
  info "    --team-id YOUR_TEAM_ID \\"
  info "    --password YOUR_APP_SPECIFIC_PASSWORD"
  if $SETUP_MODE; then
    echo ""
    read -p "     Enter Apple ID (or 's' to skip): " apple_id
    if [ "$apple_id" != "s" ] && [ -n "$apple_id" ]; then
      read -p "     Enter Team ID: " team_id
      read -sp "     Enter App-Specific Password: " app_password
      echo ""
      xcrun notarytool store-credentials "AC_PASSWORD" \
        --apple-id "$apple_id" --team-id "$team_id" --password "$app_password" \
        && pass "Notarization credentials stored!" \
        || fail "Failed to store credentials"
    fi
  fi
fi

# ─── 4. Sparkle EdDSA Key ───
echo ""
echo "Sparkle EdDSA Signing Key:"
echo "  ⚡ CRITICAL: This key MUST be identical on every release machine."
echo "     If you generate a new key, existing users CANNOT update."
echo ""

if KEYCHAIN_METADATA=$(security find-generic-password -s "https://sparkle-project.org" -a "ed25519" 2>/dev/null); then
  pass "Existing EdDSA key entry found in Keychain (private key not read)"

  # The metadata comparison is advisory; the final verifier checks the signature.
  PLIST_KEY=$(defaults read "$ROOT/Glimpse/Info.plist" SUPublicEDKey 2>/dev/null || true)
  KEYCHAIN_COMMENT=$(echo "$KEYCHAIN_METADATA" | grep "icmt" || true)
  if [ -z "$PLIST_KEY" ]; then
    fail "SUPublicEDKey is missing from Glimpse/Info.plist"
  elif echo "$KEYCHAIN_COMMENT" | grep -Fq "$PLIST_KEY"; then
    pass "Public key matches Info.plist (${PLIST_KEY:0:20}...)"
  else
    warn "Cannot auto-verify public key match"
    info "Info.plist key: $PLIST_KEY"
    info "The local helper must verify the final Sparkle signature before retaining release artifacts."
  fi
else
  fail "Existing EdDSA key entry NOT found in Keychain"
  info ""
  info "You need the SAME private key that was used to set SUPublicEDKey"
  info "in Info.plist. This key must be identical across all release machines."
  info ""
  info "Option A — Import from backup (PREFERRED):"
  info "  You need the private key string from your password manager."
  info "  Then find generate_keys:"
  info "    find ~/Library/Developer/Xcode/DerivedData -name 'generate_keys' -path '*/artifacts/*' -type f"
  info "  Run:"
  info "    /path/to/generate_keys --import YOUR_PRIVATE_KEY_BASE64"
  info ""
  info "Option B — Export from another Mac that has the key:"
  info "  On that Mac run:"
  info "    security find-generic-password -s 'https://sparkle-project.org' -a 'ed25519' -w"
  info "  Then import here using Option A."
  info ""
  info "The existing distribution key must be restored; do not generate a replacement."

  if $SETUP_MODE; then
    GENERATE_KEYS=$(find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" -path "*/artifacts/*" -type f 2>/dev/null | head -1)
    if [ -n "$GENERATE_KEYS" ]; then
      echo ""
      read -sp "     Enter existing private key to import (or 's' to skip): " key_input
      echo ""
      if [ "$key_input" != "s" ] && [ -n "$key_input" ]; then
        "$GENERATE_KEYS" --import "$key_input" \
          && pass "Sparkle key imported!" \
          || fail "Failed to import key"
      fi
    else
      info "Build the project first to get the generate_keys tool."
    fi
  fi
fi

# ─── 5. Sparkle Tools ───
echo ""
echo "Sparkle Tools:"
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/artifacts/sparkle/Sparkle/bin" -maxdepth 6 2>/dev/null | head -1)
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
if [ -n "$SPARKLE_BIN" ] && [ -x "$SIGN_UPDATE" ]; then
  pass "sign_update found"
else
  fail "Executable sign_update not found in the Sparkle bin used by the local helper"
  info "Build the project in Xcode first."
fi

GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
if [ -n "$SPARKLE_BIN" ] && [ -x "$GENERATE_APPCAST" ]; then
  pass "generate_appcast found"
else
  fail "Executable generate_appcast not found in the Sparkle bin used by the local helper"
  info "Build the project in Xcode first."
fi

# ─── 6. create-dmg ───
echo ""
echo "DMG Packaging:"
if command -v create-dmg &>/dev/null; then
  pass "create-dmg found (styled DMG with drag-to-install)"
else
  fail "create-dmg not found — required for styled DMG"
  info "Install: brew install create-dmg"
  if $SETUP_MODE; then
    echo ""
    read -p "     Install now with brew? (y/n): " install_dmg
    if [ "$install_dmg" = "y" ]; then
      brew install create-dmg && pass "create-dmg installed!" || fail "Installation failed"
    fi
  fi
fi

# ─── 7. GitHub CLI ───
echo ""
echo "GitHub CLI:"
if command -v gh &>/dev/null; then
  pass "$(gh --version | head -1)"
  if gh auth status &>/dev/null 2>&1; then
    pass "Authenticated with GitHub"
  else
    fail "Not authenticated — required for release admission checks; run: gh auth login"
  fi
else
  fail "gh CLI not installed — required for release admission checks"
  info "Install: brew install gh"
  if $SETUP_MODE; then
    echo ""
    read -p "     Install now with brew? (y/n): " install_gh
    if [ "$install_gh" = "y" ]; then
      brew install gh && pass "gh CLI installed!" || fail "Installation failed"
    fi
  fi
fi

# ─── Summary ───
echo ""
echo "═══════════════════════════════"
echo "  ✅ Passed:   $PASS"
[ $WARN -gt 0 ] && echo "  ⚠️  Warnings: $WARN"
[ $FAIL -gt 0 ] && echo "  ❌ Failed:   $FAIL"
echo "═══════════════════════════════"
echo ""

if [ $FAIL -eq 0 ]; then
  echo "✅ Machine prerequisites are ready for local release preparation!"
  echo "   The helper still enforces source admission, readiness, quality and final artifact verification."
  echo "   Run: ./tools/scripts/release-upload.sh"
  exit 0
else
  echo "❌ Fix the failures above before releasing."
  echo "   Rerun preflight after any guided setup changes."
  if ! $SETUP_MODE; then
    echo "   Run with --setup for interactive guided setup:"
    echo "   ./tools/scripts/preflight.sh --setup"
  fi
  exit 1
fi
