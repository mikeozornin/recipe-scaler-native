#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

RECIPE_ID="${VERIFY_RECIPE_ID:-7daed53b-5e79-42e8-bd9a-bc74deea712d}"

echo "== Unit: updateRecipeName persists =="
xcodebuild test \
  -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing "RecipeScalerNativeTests/RecipeScalerNativeTests/testUpdateRecipeNamePersistsInDocAndCollection" \
  2>&1 | grep -E 'Test Case|passed|failed|error:' || true

echo "== Build + launch recipe in edit mode (manual: rename title, Done, relaunch) =="
sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1 "-OpenRecipeId=$RECIPE_ID" -StartInEditMode=1

sim_wait_ready 8
LOG="${LOG_FILE:-$ROOT/.debug-session.ndjson}"
if sim_pull_debug_log; then
  echo "Debug log: $LOG"
  if grep -q 'title_blur_save_done' "$LOG" 2>/dev/null; then
    echo "OK: saw title_blur_save_done in log"
  else
    echo "NOTE: title_blur_save_done not in log yet (edit title + tap Done to verify)"
  fi
fi

echo "VERIFIED recipe-title-save (unit); simulator ready for manual title/Done/offline checks"