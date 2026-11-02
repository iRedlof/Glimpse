#!/bin/bash
# Glimpse Release Preflight Check
# Verifies all signing, notarization, and upload prerequisites on this machine.
#
# Usage:
#   ./tools/scripts/preflight.sh          # Check only
#   ./tools/scripts/preflight.sh --setup  # Interactive guided setup for missing items

set -uo pipefail

SETUP_MODE=false
[ "${1:-}" = "--setup" ] && SETUP_MODE=true

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }
info() { echo "     $1"; }

prompt_continue() {
  if $SETUP_MODE; then
    echo ""
    read -p "     Press Enter when done (or 's' to skip): " choice
    [ "$choice" = "s" ] && return 1
    return 0
  fi
  return 1
}

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
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  CERT=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
  pass "$CERT"
else
  warn "Developer ID Application certificate not found (OPTIONAL)"
  info ""
  info "Without this: first-time users must right-click → Open to bypass Gatekeeper."
  info "With this: app opens without warnings + gets Apple notarization."
  info "Sparkle updates work either way (uses EdDSA signing, not Apple signing)."
  info ""
  info "Requires Apple Developer Program (\$99/year). To set up:"
  info "  1. Enroll at https://developer.apple.com/programs/"
  info "  2. Open Xcode → Settings → Accounts"
  info "  3. Select your Apple ID → your team"
  info "  4. Click 'Manage Certificates...' → '+' → 'Developer ID Application'"
fi

# ─── 3. Notarization Credentials ───
echo ""
echo "Notarization:"
if xcrun notarytool history --keychain-profile "AC_PASSWORD" &>/dev/null 2>&1; then
  pass "AC_PASSWORD keychain profile found"
else
  warn "Notarization credentials not configured (OPTIONAL — requires \$99 Developer Program)"
  info ""
  info "Apple notarization proves your app is malware-free. You need:"
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

SPARKLE_KEY=$(security find-generic-password -s "https://sparkle-project.org" -a "ed25519" -w 2>/dev/null)
if [ -n "$SPARKLE_KEY" ]; then
  pass "EdDSA private key found in Keychain"

  # Check public key match
  PLIST_KEY=$(defaults read "$(pwd)/Glimpse/Info.plist" SUPublicEDKey 2>/dev/null || echo "")
  KEYCHAIN_COMMENT=$(security find-generic-password -s "https://sparkle-project.org" -a "ed25519" 2>/dev/null | grep "icmt")
  if [ -n "$PLIST_KEY" ] && echo "$KEYCHAIN_COMMENT" | grep -q "$PLIST_KEY"; then
    pass "Public key matches Info.plist (${PLIST_KEY:0:20}...)"
  elif [ -n "$PLIST_KEY" ]; then
    warn "Cannot auto-verify public key match"
    info "Info.plist key: $PLIST_KEY"
    info "Manually verify this matches the key in Keychain (check 'icmt' comment above)"
  fi

  info ""
  info "⬆️  BACK UP this key now if you haven't already:"
  info "  security find-generic-password -s \"https://sparkle-project.org\" -a \"ed25519\" -w"
  info "  Save the output in your password manager."
else
  fail "EdDSA private key NOT found in Keychain"
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
      read -p "     Enter private key to import (or 's' to skip): " key_input
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
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*" -type f 2>/dev/null | head -1)
if [ -n "$SIGN_UPDATE" ]; then
  pass "sign_update found"
else
  warn "sign_update not found — build the project in Xcode first"
fi

GENERATE_APPCAST=$(find ~/Library/Developer/Xcode/DerivedData -name "generate_appcast" -path "*/artifacts/*" -type f 2>/dev/null | head -1)
if [ -n "$GENERATE_APPCAST" ]; then
  pass "generate_appcast found"
else
  warn "generate_appcast not found — build the project in Xcode first"
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
    warn "Not authenticated — run: gh auth login"
  fi
else
  warn "gh CLI not installed (optional — needed for local gh release create)"
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
  echo "✅ Machine is ready for releases!"
  echo "   Run: ./tools/scripts/release-upload.sh"
  exit 0
else
  echo "❌ Fix the failures above before releasing."
  if ! $SETUP_MODE; then
    echo "   Run with --setup for interactive guided setup:"
    echo "   ./tools/scripts/preflight.sh --setup"
  fi
  exit 1
fi
