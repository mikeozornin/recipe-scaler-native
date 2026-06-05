#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

echo "== UI test: shopping list add flows =="
xcodebuild test \
  -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing:RecipeScalerNativeUITests/RecipeScalerNativeUITests/testShoppingListAddFlowsOnSimulator \
  2>&1 | tee /tmp/verify-shopping-list-ui.log | tail -40

rg -q "Test Case.*testShoppingListAddFlowsOnSimulator.*passed" /tmp/verify-shopping-list-ui.log
echo "VERIFIED shopping-list-ui"