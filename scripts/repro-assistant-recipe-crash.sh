#!/usr/bin/env bash
# Repro: Dev app, assistant tab → dismiss sheet → open recipe. No XCTest / no local API.
#
#   bash scripts/repro-assistant-recipe-crash.sh
#
# Exit 0 = process alive, no new DiagnosticReports crash.
# Exit 1 = crash (process gone or new .ips).
# Exit 2 = axe missing or UI not ready.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${SIM_ID:=$("$ROOT/scripts/resolve-simulator.sh")}"

DEV_SCHEME="RecipeScalerNative-Dev"
DEV_BUNDLE="ru.recipescaler.RecipeScaler.debug"
CRASH_DIR="${HOME}/Library/Logs/DiagnosticReports"

count_crashes() {
  ls -1 "$CRASH_DIR"/RecipeScalerNative*.ips 2>/dev/null | wc -l | tr -d ' '
}

wait_for_id() {
  local id="$1" timeout="${2:-30}" elapsed=0
  while (( elapsed < timeout )); do
    if axe describe-ui --udid "$SIM_ID" 2>/dev/null | python3 -c "
import json,sys
tree=json.load(sys.stdin)
def walk(n):
    if n.get('AXUniqueId')==sys.argv[1] or n.get('identifier')==sys.argv[1]:
        return True
    return any(walk(c) for c in n.get('children',[]))
import sys
sys.exit(0 if (isinstance(tree,list) and any(walk(t) for t in tree)) or walk(tree) else 1)
" "$id" 2>/dev/null; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

first_recipe_row_id() {
  axe describe-ui --udid "$SIM_ID" 2>/dev/null | python3 -c "
import json,sys
tree=json.load(sys.stdin)
prefix='recipe_row_'
found=[]
def walk(n):
    i=n.get('AXUniqueId') or n.get('identifier') or ''
    if i.startswith(prefix):
        found.append(i)
    for c in n.get('children',[]):
        walk(c)
if isinstance(tree,list):
    for t in tree: walk(t)
else:
    walk(tree)
print(found[0] if found else '')
"
}

if ! command -v axe >/dev/null; then
  echo "axe CLI missing"
  exit 2
fi

echo "== Build Dev =="
xcodebuild -scheme "$DEV_SCHEME" \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -quiet build

APP_PATH=""
settings="$(xcodebuild -scheme "$DEV_SCHEME" \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -configuration Debug \
  -showBuildSettings 2>/dev/null)"
products="$(echo "$settings" | awk -F ' = ' '/TARGET_BUILD_DIR/ {print $2; exit}')"
product_name="$(echo "$settings" | awk -F ' = ' '/FULL_PRODUCT_NAME/ {print $2; exit}')"
if [[ -n "$products" && -n "$product_name" ]]; then
  APP_PATH="$products/$product_name"
fi
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*Build/Products/*iphonesimulator/RecipeScalerNative.app' \
    ! -path '*Index.noindex*' \
    -print -quit)"
fi
if [[ -z "$APP_PATH" ]]; then
  echo "FAIL: RecipeScalerNative.app not found"
  exit 1
fi

BEFORE="$(count_crashes)"
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl install "$SIM_ID" "$APP_PATH"
xcrun simctl terminate "$SIM_ID" "$DEV_BUNDLE" 2>/dev/null || true
xcrun simctl launch "$SIM_ID" "$DEV_BUNDLE" -SkipSplash=1 >/dev/null

echo "== Wait for Recipes tab =="
if ! wait_for_id "recipe_list_add" 45 \
  && ! wait_for_id "collection_grid_all" 15 \
  && ! wait_for_id "recipe_list" 15; then
  echo "FAIL: Recipes tab not ready (no recipe_list_add / collection_grid_all / recipe_list in a11y tree)"
  exit 2
fi

echo "== Assistant → dismiss =="
if axe tap --id tab-assistant --udid "$SIM_ID" --wait-timeout 10 2>/dev/null; then
  :
else
  axe tap --label Assistant --udid "$SIM_ID" --wait-timeout 10
fi
sleep 2
axe swipe --start-x 630 --start-y 400 --end-x 630 --end-y 2400 --duration 0.35 --udid "$SIM_ID"
sleep 1.5

if wait_for_id "collection_grid_all" 5; then
  echo "== Open All recipes folder =="
  axe tap --id collection_grid_all --udid "$SIM_ID" --wait-timeout 10
  sleep 2
fi

ROW_ID="$(first_recipe_row_id)"
if [[ -z "$ROW_ID" ]]; then
  echo "FAIL: no recipe_row_* in a11y tree — create a recipe in simulator first"
  exit 2
fi

echo "== Tap $ROW_ID =="
if ! axe tap --id "$ROW_ID" --udid "$SIM_ID" --wait-timeout 10 2>/dev/null; then
  echo "  (duplicate id — coordinate fallback)"
  axe tap -x 210 -y 350 --udid "$SIM_ID"
fi
sleep 3

if ! pgrep -q RecipeScalerNative; then
  echo "FAIL: app process exited (crash)"
  ls -lat "$CRASH_DIR"/RecipeScalerNative*.ips 2>/dev/null | head -2 || true
  exit 1
fi

AFTER="$(count_crashes)"
if (( AFTER > BEFORE )); then
  echo "FAIL: new crash report"
  ls -lat "$CRASH_DIR"/RecipeScalerNative*.ips | head -2
  exit 1
fi

echo "OK: assistant dismiss → recipe row tap — no crash (check recipe_detail_menu visually if needed)"
