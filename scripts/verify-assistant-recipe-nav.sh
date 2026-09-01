#!/usr/bin/env bash
# Repro + gate: assistant tab → dismiss sheet → open recipe (no crash).
#
# Agent loop:
#   bash scripts/verify-assistant-recipe-nav.sh
#
# On failure: fresh RecipeScalerNative*.ips in ~/Library/Logs/DiagnosticReports/
# and XCTest .xcresult under DerivedData.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

CRASH_DIR="${HOME}/Library/Logs/DiagnosticReports"
TEST_ID="RecipeScalerNativeUITests/AssistantRecipeNavReproSpec/test_assistantDismissThenOpenRecipe_survivesNavigation"

count_crashes() {
  ls -1 "$CRASH_DIR"/RecipeScalerNative*.ips 2>/dev/null | wc -l | tr -d ' '
}

BEFORE_CRASHES="$(count_crashes)"

echo "== Build + UI test: $TEST_ID =="
sim_build >/dev/null

set +e
xcodebuild test \
  -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing:"$TEST_ID" \
  2>&1 | tee /tmp/verify-assistant-recipe-nav.log
TEST_EXIT=${PIPESTATUS[0]}
set -e

AFTER_CRASHES="$(count_crashes)"
if (( AFTER_CRASHES > BEFORE_CRASHES )); then
  echo "FAIL: new crash report(s) in $CRASH_DIR"
  ls -lat "$CRASH_DIR"/RecipeScalerNative*.ips | head -3
  exit 1
fi

if (( TEST_EXIT != 0 )); then
  echo "FAIL: xcodebuild test exit $TEST_EXIT (see /tmp/verify-assistant-recipe-nav.log)"
  exit "$TEST_EXIT"
fi

if grep -q "Test skipped" /tmp/verify-assistant-recipe-nav.log; then
  echo "INCONCLUSIVE: UI test skipped (see log). Fallback: bash scripts/repro-assistant-recipe-crash.sh"
  exit 2
fi

if grep -qE "TEST FAILED|XCTAssertTrue failed" /tmp/verify-assistant-recipe-nav.log; then
  echo "FAIL: UI test failed — crash repro confirmed"
  exit 1
fi

echo "VERIFIED: assistant dismiss → recipe detail (no new crash reports)"
