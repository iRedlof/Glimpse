#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
python3 "$SCRIPT_DIR/release-control.py" gate
EXISTING_PATH="$(git -C "$ROOT" config --get core.hooksPath || true)"
HOOK_PATH="$SCRIPT_DIR/hooks"
if [[ -n "$EXISTING_PATH" && "$EXISTING_PATH" != "$HOOK_PATH" ]]; then
  echo "Existing core.hooksPath must be integrated manually: $EXISTING_PATH" >&2
  exit 1
fi
# Separate worktree config prevents this checkout's hook path from taking over
# another worktree. Enabling the extension itself is shared Git metadata.
git -C "$ROOT" config --local extensions.worktreeConfig true
git -C "$ROOT" config --worktree core.hooksPath "$HOOK_PATH"
chmod +x "$HOOK_PATH/pre-commit" "$HOOK_PATH/pre-push"
echo "Previous-release gates installed for this checkout: $ROOT"
