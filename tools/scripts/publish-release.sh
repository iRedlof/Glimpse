#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
ARTIFACT_DIR="${1:?artifact directory required}"
PREVIOUS_RECORD="${2:?previous release verification required}"
VERSION="${VERSION:?version required}"
REPO="${GITHUB_REPOSITORY:?repository required}"
SOURCE_SHA="${GITHUB_SHA:?source SHA required}"
RUN_ID="${GITHUB_RUN_ID:?workflow run required}"
RELEASE_ID=""
PREVIOUS_TAG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag"])' "$PREVIOUS_RECORD")"

assert_current_source() {
  REMOTE_SHA="$(gh api "repos/$REPO/branches/main" --jq '.commit.sha')"
  if [[ "$REMOTE_SHA" != "$SOURCE_SHA" ]]; then
    echo "Main advanced during release; refusing to publish this source" >&2
    return 1
  fi
}

rollback_on_failure() {
  result=$?
  trap - EXIT
  if [[ "$result" != 0 && -n "$RELEASE_ID" ]]; then
    if ! python3 "$SCRIPT_DIR/release-control.py" withdraw --release-id "$RELEASE_ID" --previous-tag "$PREVIOUS_TAG"; then
      echo "::error::Release withdrawal could not be verified. Commits/pushes remain blocked; operator recovery is required." >&2
    fi
  fi
  exit "$result"
}
trap rollback_on_failure EXIT

assert_current_source
python3 "$SCRIPT_DIR/release-control.py" manifest --directory "$ARTIFACT_DIR"
# Create an empty draft first so upload failures cannot expose partial artifacts.
python3 - "$ARTIFACT_DIR/release-notes.md" "$REPO" "$VERSION" "$SOURCE_SHA" "$RUN_ID" <<'PY'
import json, pathlib, subprocess, sys
output, repo, version, sha, run = sys.argv[1:]
body = json.dumps({"tag_name": f"v{version}", "target_commitish": sha})
result = subprocess.run(["gh", "api", f"repos/{repo}/releases/generate-notes",
                         "--method", "POST", "--input", "-"],
                        input=body, text=True, capture_output=True, check=True)
notes = json.loads(result.stdout)["body"]
pathlib.Path(output).write_text(notes + f"\n\n<!-- glimpse-run:{run} sha:{sha} -->\n")
PY
gh api "repos/$REPO/releases?per_page=100" > "$ARTIFACT_DIR/existing-releases.json"
EXISTING_ID="$(python3 - "$ARTIFACT_DIR/existing-releases.json" "$VERSION" "$SOURCE_SHA" "$RUN_ID" <<'PY'
import json, sys
path, version, sha, run = sys.argv[1:]
matches = [r for r in json.load(open(path)) if r["tag_name"] == "v" + version]
if matches:
    release = matches[0]
    marker = f"<!-- glimpse-run:{run} sha:{sha} -->"
    if not release["draft"] or marker not in (release.get("body") or ""):
        raise SystemExit("Existing release is public or owned by a different workflow")
    print(release["id"])
PY
)"
if [[ -n "$EXISTING_ID" ]]; then
  RELEASE_ID="$EXISTING_ID"
  gh release edit "v$VERSION" --repo "$REPO" --draft --notes-file "$ARTIFACT_DIR/release-notes.md"
else
  gh release create "v$VERSION" --repo "$REPO" --target "$SOURCE_SHA" \
    --draft --title "v$VERSION" --notes-file "$ARTIFACT_DIR/release-notes.md"
  RELEASE_ID="$(gh api "repos/$REPO/releases/tags/v$VERSION" --jq '.id')"
fi
printf 'release_id=%s\n' "$RELEASE_ID" >> "$GITHUB_OUTPUT"
gh release upload "v$VERSION" --repo "$REPO" --clobber \
  "$ARTIFACT_DIR/Glimpse-$VERSION.dmg" "$ARTIFACT_DIR/appcast.xml" \
  "$ARTIFACT_DIR/release-manifest.json"
python3 "$SCRIPT_DIR/release-control.py" verify --tag "v$VERSION" \
  --directory "$ARTIFACT_DIR/draft-download"
assert_current_source
gh release edit "v$VERSION" --repo "$REPO" --draft=false --latest
# Download anonymously through the public release and Sparkle latest URLs.
# Retry boundedly for GitHub CDN propagation, then withdraw on persistent failure.
HEALTH_PASSED=false
for attempt in 1 2 3; do
  if python3 "$SCRIPT_DIR/release-control.py" verify --public --tag "v$VERSION" \
      --directory "$ARTIFACT_DIR/public-download-$attempt"; then
    HEALTH_PASSED=true
    break
  fi
  sleep 10
done
$HEALTH_PASSED
assert_current_source
printf 'release_verified=true\n' >> "$GITHUB_OUTPUT"
