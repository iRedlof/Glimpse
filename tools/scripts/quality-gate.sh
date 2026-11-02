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
trap 'if [[ -e "$WORK_DIR/retain-keyboard-artifacts" ]]; then
  printf "Keyboard artifact staging retained: %s\n" "$WORK_DIR" >&2
elif [[ -e "$WORK_DIR/retain-ai-date-search-integration-artifacts" ]]; then
  printf "AI date search artifact staging retained: %s\n" "$WORK_DIR" >&2
else
  rm -rf -- "$WORK_DIR"
fi' EXIT
mkdir -p "$WORK_DIR/tmp"
export TMPDIR="$WORK_DIR/tmp"
# Ordinary concurrent app tests must never inherit native keyboard research opt-ins.
export GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE=0 TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE=0
export GLIMPSE_KEYBOARD_MECHANISM_PROBE=0 TEST_RUNNER_GLIMPSE_KEYBOARD_MECHANISM_PROBE=0
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
KEYBOARD_RECEIPT="$RESULT_DIR/keyboard-ownership-acceptance.json"
if [[ ! -e Glimpse/CalendarKeyboardFocus.swift && ! -L Glimpse/CalendarKeyboardFocus.swift \
   && ! -e GlimpseTests/CalendarKeyboardOwnershipTests.swift && ! -L GlimpseTests/CalendarKeyboardOwnershipTests.swift ]]; then
  printf '%s\n' '{"status":"NotApplicable","reason":"Legacy archive: both keyboard focus and ownership suite absent"}' > "$KEYBOARD_RECEIPT"
elif [[ ! -f Glimpse/CalendarKeyboardFocus.swift || ! -f GlimpseTests/CalendarKeyboardOwnershipTests.swift ]]; then
  printf '%s\n' '{"status":"Failed","reason":"Keyboard focus and ownership suite must both exist"}' > "$KEYBOARD_RECEIPT"
  exit 1
else
  HOST_ARCH="$(uname -m)"
  mkdir -p "$WORK_DIR/keyboard-ownership-artifacts"
  if GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE=1 TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE=1 \
    GLIMPSE_KEYBOARD_ARTIFACT_DIR="$WORK_DIR/keyboard-ownership-artifacts" \
    TEST_RUNNER_GLIMPSE_KEYBOARD_ARTIFACT_DIR="$WORK_DIR/keyboard-ownership-artifacts" \
    xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug \
      -destination "platform=macOS,arch=$HOST_ARCH" -derivedDataPath "$WORK_DIR/DerivedData" \
      -skipMacroValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
      -parallel-testing-enabled NO -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 30 \
      -only-testing:GlimpseTests/CalendarKeyboardOwnershipTests \
      -resultBundlePath "$RESULT_DIR/KeyboardOwnershipTests.xcresult" \
      "ARCHS=$HOST_ARCH" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test \
      2>&1 | tee "$RESULT_DIR/keyboard-ownership-tests.log"; then
    keyboard_pipeline=("${PIPESTATUS[@]}")
  else
    keyboard_pipeline=("${PIPESTATUS[@]}")
  fi
  keyboard_exit="${keyboard_pipeline[0]}"
  keyboard_log_exit="${keyboard_pipeline[1]}"
  # Native writes stay private; collect only after terminal execution and owned-host absence.
  # Keep staging if collection cannot complete or the collector itself fails.
  touch "$WORK_DIR/retain-keyboard-artifacts"
  artifact_exit=0
  python3 "$SCRIPT_DIR/collect-keyboard-artifacts.py" \
    --staging "$WORK_DIR/keyboard-ownership-artifacts" \
    --destination "$RESULT_DIR/keyboard-ownership-artifacts" \
    --host-executable "$WORK_DIR/DerivedData/Build/Products/Debug/Glimpse.app/Contents/MacOS/Glimpse" \
    --manifest "$ROOT/tools/scripts/keyboard-ownership-methods.json" \
    --native-exit "$keyboard_exit" --retain-marker "$WORK_DIR/retain-keyboard-artifacts" \
    --receipt "$RESULT_DIR/keyboard-ownership-artifact-collection.json" \
    > "$RESULT_DIR/keyboard-ownership-artifact-collection.log" 2>&1 || artifact_exit=$?
  # Retain raw metadata and a checker receipt even when build/extraction fails.
  summary_exit=0
  xcrun xcresulttool get test-results summary --path "$RESULT_DIR/KeyboardOwnershipTests.xcresult" \
    > "$RESULT_DIR/keyboard-ownership-summary.json" 2> "$RESULT_DIR/keyboard-ownership-xcresult.log" || summary_exit=$?
  tests_exit=0
  xcrun xcresulttool get test-results tests --path "$RESULT_DIR/KeyboardOwnershipTests.xcresult" \
    > "$RESULT_DIR/keyboard-ownership-tests.json" 2>> "$RESULT_DIR/keyboard-ownership-xcresult.log" || tests_exit=$?
  checker_exit=0
  # Current controller owns validation; the required methods belong to the exact source archive.
  python3 "$SCRIPT_DIR/check-keyboard-xcresult.py" \
    --manifest "$ROOT/tools/scripts/keyboard-ownership-methods.json" \
    --summary "$RESULT_DIR/keyboard-ownership-summary.json" --tests "$RESULT_DIR/keyboard-ownership-tests.json" \
    --receipt "$KEYBOARD_RECEIPT" --xcodebuild-exit "$keyboard_exit" \
    --summary-exit "$summary_exit" --tests-exit "$tests_exit" \
    --log-exit "$keyboard_log_exit" || checker_exit=$?
  for phase_exit in "$keyboard_exit" "$keyboard_log_exit" "$summary_exit" "$tests_exit" "$checker_exit" "$artifact_exit"; do
    if [[ "$phase_exit" != 0 ]]; then exit "$phase_exit"; fi
  done
fi
AI_RECEIPT="$RESULT_DIR/ai-date-search-integration-acceptance.json"
AI_SUITE="GlimpseTests/AIDateSearchIntegrationTests.swift"
AI_MANIFEST="$ROOT/tools/scripts/ai-date-search-integration-methods.json"
if [[ ! -e "$AI_SUITE" && ! -L "$AI_SUITE" && ! -e "$AI_MANIFEST" && ! -L "$AI_MANIFEST" ]]; then
  printf '%s\n' '{"status":"NotApplicable","reason":"Legacy archive: both AI integration suite and method manifest absent"}' > "$AI_RECEIPT"
elif [[ ! -f "$AI_SUITE" || -L "$AI_SUITE" || ! -f "$AI_MANIFEST" || -L "$AI_MANIFEST" ]]; then
  printf '%s\n' '{"status":"Failed","reason":"AI integration suite and method manifest must both be regular files"}' > "$AI_RECEIPT"
  exit 1
else
  HOST_ARCH="$(uname -m)"
  mkdir -p "$WORK_DIR/ai-date-search-integration-artifacts"
  # This suite owns a key panel: execute after keyboard acceptance in its own host.
  if GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE=1 TEST_RUNNER_GLIMPSE_CALENDAR_KEYBOARD_ACCEPTANCE=1 \
    GLIMPSE_KEYBOARD_ARTIFACT_DIR="$WORK_DIR/ai-date-search-integration-artifacts" \
    TEST_RUNNER_GLIMPSE_KEYBOARD_ARTIFACT_DIR="$WORK_DIR/ai-date-search-integration-artifacts" \
    xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug \
      -destination "platform=macOS,arch=$HOST_ARCH" -derivedDataPath "$WORK_DIR/DerivedData" \
      -skipMacroValidation -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
      -parallel-testing-enabled NO -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 30 \
      -only-testing:GlimpseTests/AIDateSearchIntegrationTests \
      -resultBundlePath "$RESULT_DIR/AIDateSearchIntegrationTests.xcresult" \
      "ARCHS=$HOST_ARCH" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test \
      2>&1 | tee "$RESULT_DIR/ai-date-search-integration-tests.log"; then
    ai_pipeline=("${PIPESTATUS[@]}")
  else
    ai_pipeline=("${PIPESTATUS[@]}")
  fi
  ai_exit="${ai_pipeline[0]}"
  ai_log_exit="${ai_pipeline[1]}"
  # The unchanged collector accepts empty AI staging and proves owned-host absence.
  touch "$WORK_DIR/retain-ai-date-search-integration-artifacts"
  ai_artifact_exit=0
  python3 "$SCRIPT_DIR/collect-keyboard-artifacts.py" \
    --staging "$WORK_DIR/ai-date-search-integration-artifacts" \
    --destination "$RESULT_DIR/ai-date-search-integration-artifacts" \
    --host-executable "$WORK_DIR/DerivedData/Build/Products/Debug/Glimpse.app/Contents/MacOS/Glimpse" \
    --manifest "$AI_MANIFEST" \
    --native-exit "$ai_exit" --retain-marker "$WORK_DIR/retain-ai-date-search-integration-artifacts" \
    --receipt "$RESULT_DIR/ai-date-search-integration-artifact-collection.json" \
    > "$RESULT_DIR/ai-date-search-integration-artifact-collection.log" 2>&1 || ai_artifact_exit=$?
  ai_summary_exit=0
  xcrun xcresulttool get test-results summary --path "$RESULT_DIR/AIDateSearchIntegrationTests.xcresult" \
    > "$RESULT_DIR/ai-date-search-integration-summary.json" 2> "$RESULT_DIR/ai-date-search-integration-xcresult.log" || ai_summary_exit=$?
  ai_tests_exit=0
  xcrun xcresulttool get test-results tests --path "$RESULT_DIR/AIDateSearchIntegrationTests.xcresult" \
    > "$RESULT_DIR/ai-date-search-integration-tests.json" 2>> "$RESULT_DIR/ai-date-search-integration-xcresult.log" || ai_tests_exit=$?
  ai_checker_exit=0
  python3 "$SCRIPT_DIR/check-keyboard-xcresult.py" --suite AIDateSearchIntegrationTests \
    --manifest "$AI_MANIFEST" \
    --summary "$RESULT_DIR/ai-date-search-integration-summary.json" --tests "$RESULT_DIR/ai-date-search-integration-tests.json" \
    --receipt "$AI_RECEIPT" --xcodebuild-exit "$ai_exit" \
    --summary-exit "$ai_summary_exit" --tests-exit "$ai_tests_exit" \
    --log-exit "$ai_log_exit" || ai_checker_exit=$?
  for phase_exit in "$ai_exit" "$ai_log_exit" "$ai_summary_exit" "$ai_tests_exit" "$ai_checker_exit" "$ai_artifact_exit"; do
    if [[ "$phase_exit" != 0 ]]; then exit "$phase_exit"; fi
  done
fi
(
  cd GlimpseCore
  swift test --scratch-path "$WORK_DIR/core" --cache-path "$BUILD_ROOT/swiftpm-cache" \
    --force-resolved-versions 2>&1 | tee "$RESULT_DIR/core-tests.log"
)
shasum -a 256 "${LOCKFILES[@]}" > "$RESULT_DIR/dependency-pins.after.sha256"
cmp "$RESULT_DIR/dependency-pins.before.sha256" "$RESULT_DIR/dependency-pins.after.sha256"
