#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT="${GLIMPSE_SOURCE_ROOT:-$ROOT}"
cd "$ROOT"
export PYTHONDONTWRITEBYTECODE=1
BUILD_ROOT="${GLIMPSE_BUILD_ROOT:-$(git -C "$SCRIPT_DIR" config --get glimpse.buildRoot || true)}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build}"
mkdir -p "$BUILD_ROOT"
RESULT_DIR="${GLIMPSE_RESULTS_DIR:-$(mktemp -d "$BUILD_ROOT/quality-results.XXXXXX")}"
mkdir -p "$RESULT_DIR"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then printf 'results_dir=%s\n' "$RESULT_DIR" >> "$GITHUB_OUTPUT"; fi
WORK_ROOT="${RUNNER_TEMP:-/tmp}"
mkdir -p "$WORK_ROOT"
WORK_DIR="$(mktemp -d "$WORK_ROOT/glimpse-quality.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/tmp"
export TMPDIR="$WORK_DIR/tmp"
# Current orchestration owns cleanup; tooling under test belongs to the source archive.
python3 -m unittest discover -s "$ROOT/tools/scripts/tests" -v
python3 -m unittest discover -s "$ROOT/tools/monitoring" -p 'test_*.py' -v
python3 "$ROOT/tools/scripts/release-control.py" version --root "$ROOT"
python3 "$ROOT/tools/scripts/check-dependency-pins.py" --root "$ROOT"
LOCKFILES=(GlimpseCore/Package.resolved Glimpse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)
shasum -a 256 "${LOCKFILES[@]}" > "$RESULT_DIR/dependency-pins.before.sha256"
xcodebuild -version
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile \
  -skipMacroValidation 2>&1 | tee "$RESULT_DIR/resolve.log"
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -destination 'platform=macOS' \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  -skipMacroValidation -disableAutomaticPackageResolution \
  -resultBundlePath "$RESULT_DIR/AppTests.xcresult" CODE_SIGNING_ALLOWED=NO test \
  2>&1 | tee "$RESULT_DIR/app-tests.log"
(
  cd GlimpseCore
  swift test --scratch-path "$WORK_DIR/core" --cache-path "$BUILD_ROOT/swiftpm-cache" \
    --force-resolved-versions 2>&1 | tee "$RESULT_DIR/core-tests.log"
)
shasum -a 256 "${LOCKFILES[@]}" > "$RESULT_DIR/dependency-pins.after.sha256"
cmp "$RESULT_DIR/dependency-pins.before.sha256" "$RESULT_DIR/dependency-pins.after.sha256"
