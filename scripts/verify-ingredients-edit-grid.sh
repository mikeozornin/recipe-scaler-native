#!/usr/bin/env bash
# Launch v3 recipe in edit mode on simulator and capture ingredients grid screenshot.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=sim-verify-lib.sh
source "$ROOT/scripts/sim-verify-lib.sh"

RECIPE_ID="${VERIFY_RECIPE_ID:-7daed53b-5e79-42e8-bd9a-bc74deea712d}"
SHOT_DIR="${VERIFY_SHOT_DIR:-$ROOT/.verify-screenshots}"

echo "== Build Debug =="
sim_build >/dev/null
sim_prepare
xcrun simctl privacy "$SIM_ID" grant notifications "$BUNDLE_ID" 2>/dev/null || true
sim_install

echo "== Launch edit mode (recipe $RECIPE_ID) =="
sim_launch -SkipSplash=1 "-OpenRecipeId=$RECIPE_ID" -StartInEditMode=1 -ScrollToNewIngredient=1
sim_wait_ready 12

mkdir -p "$SHOT_DIR"
SHOT="$(sim_screenshot "$SHOT_DIR" ingredients-edit-grid)"
echo "Screenshot: $SHOT"
echo "VERIFIED ingredients-edit-grid (simulator screenshot captured)"