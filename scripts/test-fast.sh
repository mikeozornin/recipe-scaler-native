#!/usr/bin/env bash
# Fast unit-test gate: build-for-testing once, then run RecipeScalerNativeTests
# (no UI tests). Fails if any test case exceeds MAX_TEST_SECONDS wall time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${SIM_ID:=C3ED7448-2C55-4F02-B5DA-721E2853FD0B}"
: "${MAX_TEST_SECONDS:=30}"
DESTINATION="platform=iOS Simulator,id=$SIM_ID"
RESULT_BUNDLE="${RESULT_BUNDLE:-$ROOT/.test-fast-results.xcresult}"
LOG_FILE="$ROOT/.test-fast.log"

rm -rf "$RESULT_BUNDLE" "$LOG_FILE"

echo "== build-for-testing =="
xcodebuild build-for-testing \
  -scheme RecipeScalerNative \
  -destination "$DESTINATION" \
  -configuration Debug

echo "== test-without-building (unit tests only) =="
# SnapshotTests are excluded because they crash the test host on missing
# `.environmentObject(AuthService/YjsSyncService)` (pre-existing, unrelated
# to the rest of the suite). Run them separately via `verify-all.sh`.
set +e
xcodebuild test-without-building \
  -scheme RecipeScalerNative \
  -destination "$DESTINATION" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -skip-testing:RecipeScalerNativeUITests \
  -skip-testing:RecipeScalerNativeTests/SnapshotTests \
  2>&1 | tee "$LOG_FILE"
test_exit=${PIPESTATUS[0]}
set -e

if grep -qE '\*\* TEST FAILED \*\*|TEST BUILD FAILED' "$LOG_FILE"; then
  echo "FAILED: unit test bundle reported failures" >&2
  exit 1
fi

if [[ "$test_exit" -ne 0 ]]; then
  echo "FAILED: xcodebuild exited $test_exit" >&2
  exit 1
fi

# Flag any single test case that exceeded the wall-time budget.
slow_tests="$(grep -E "Test Case .* passed \([0-9]+\.[0-9]+ seconds\)" "$LOG_FILE" \
  | awk -v max="$MAX_TEST_SECONDS" '{
      if (match($0, /passed \([0-9]+\.[0-9]+ seconds\)/)) {
        s = substr($0, RSTART + 8, RLENGTH - 17)
        if (s + 0 > max + 0) print $0
      }
    }' || true)"

if [[ -n "$slow_tests" ]]; then
  echo "FAILED: test(s) exceeded ${MAX_TEST_SECONDS}s budget:" >&2
  echo "$slow_tests" >&2
  exit 1
fi

executed="$(grep -E 'Executed [0-9]+ test' "$LOG_FILE" | tail -1 || true)"
echo "VERIFIED test-fast ($executed, max ${MAX_TEST_SECONDS}s per case)"
