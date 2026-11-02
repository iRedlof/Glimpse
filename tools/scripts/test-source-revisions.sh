#!/bin/bash
# Test every introduced commit, plus the PR merge result, using exact archives.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
export PYTHONDONTWRITEBYTECODE=1
BUILD_ROOT="${GLIMPSE_BUILD_ROOT:-$(git config --get glimpse.buildRoot || true)}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build}"
mkdir -p "$BUILD_ROOT"
BATCH_DIR="$(mktemp -d "$BUILD_ROOT/history.XXXXXX")"
RESULT_DIR="$BATCH_DIR/results"
mkdir -p "$RESULT_DIR"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then printf 'results_dir=%s\n' "$RESULT_DIR" >> "$GITHUB_OUTPUT"; fi
HEAD_SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
test "$(git rev-parse "$HEAD_SHA^{commit}")" = "$HEAD_SHA"
if [[ "${GITHUB_EVENT_NAME:-}" == pull_request ]]; then
  BASE_SHA="${PR_BASE_SHA:?Missing PR base SHA}"
  SOURCE_HEAD="${PR_HEAD_SHA:?Missing PR source SHA}"
elif [[ "${GITHUB_EVENT_NAME:-}" == push ]]; then
  SOURCE_HEAD="$HEAD_SHA"
  BASE_SHA="${BEFORE_SHA:?Missing push predecessor SHA}"
  if [[ "$BASE_SHA" == 0000000000000000000000000000000000000000 ]]; then
    BASE_SHA="$(git merge-base origin/main "$SOURCE_HEAD")"
  fi
else
  BASE_SHA="$HEAD_SHA"
  SOURCE_HEAD="$HEAD_SHA"
fi
git rev-parse "$BASE_SHA^{commit}" "$SOURCE_HEAD^{commit}" >/dev/null
git rev-list --reverse --topo-order "$BASE_SHA..$SOURCE_HEAD" > "$RESULT_DIR/requested-shas.txt"
if ! grep -Fxq "$HEAD_SHA" "$RESULT_DIR/requested-shas.txt"; then
  printf '%s\n' "$HEAD_SHA" >> "$RESULT_DIR/requested-shas.txt"
fi
printf '{"base_sha":"%s","source_head_sha":"%s","merge_or_push_sha":"%s","event":"%s"}\n' \
  "$BASE_SHA" "$SOURCE_HEAD" "$HEAD_SHA" "${GITHUB_EVENT_NAME:-local}" > "$RESULT_DIR/history.json"
: > "$RESULT_DIR/tested-shas.txt"
while IFS= read -r revision; do
  SOURCE_DIR="$BATCH_DIR/source-$revision"
  mkdir -p "$SOURCE_DIR" "$RESULT_DIR/$revision"
  git archive "$revision" | tar -x -C "$SOURCE_DIR"
  printf 'Testing exact source %s\n' "$revision"
  if GLIMPSE_SOURCE_ROOT="$SOURCE_DIR" GLIMPSE_BUILD_ROOT="$BUILD_ROOT" \
      GLIMPSE_RESULTS_DIR="$RESULT_DIR/$revision" GITHUB_OUTPUT="" \
      "$SCRIPT_DIR/quality-gate.sh"; then
    printf '%s\n' "$revision" >> "$RESULT_DIR/tested-shas.txt"
    rm -rf "$SOURCE_DIR"
  else
    printf '%s\n' "$revision" > "$RESULT_DIR/failed-sha.txt"
    exit 1
  fi
done < "$RESULT_DIR/requested-shas.txt"
cmp "$RESULT_DIR/requested-shas.txt" "$RESULT_DIR/tested-shas.txt"
