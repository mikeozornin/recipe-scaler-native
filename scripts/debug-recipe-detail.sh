#!/usr/bin/env bash
# Reproduce recipe read path on simulator and collect NDJSON logs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIM_ID="${SIM_ID:-$("$ROOT/scripts/resolve-simulator.sh")}"
RECIPE_ID="${RECIPE_ID:-70c03b0e-a9c3-44bd-82b9-b949a7839e26}"
LOG_FILE="${LOG_FILE:-$ROOT/.debug-session.ndjson}"
DERIVED="${DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/RecipeScalerNative-diymkplxrwchdvgvqkoehouiygur}"

rm -f "$LOG_FILE"

echo "== Build Debug =="
xcodebuild -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -configuration Debug \
  build >/dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/RecipeScalerNative.app"
if [[ ! -d "$APP" ]]; then
  echo "App not found at $APP" >&2
  exit 1
fi

xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl terminate "$SIM_ID" ru.recipescaler.RecipeScaler 2>/dev/null || true

export SIMCTL_CHILD_AGENT_DEBUG_LOG="$LOG_FILE"
echo "== Launch (RecipeReadDiagnostics=$RECIPE_ID) =="
xcrun simctl launch "$SIM_ID" ru.recipescaler.RecipeScaler \
  "-RecipeReadDiagnostics=$RECIPE_ID" >/dev/null

echo "Waiting 20s for sync + diagnostics..."
sleep 20

if [[ ! -s "$LOG_FILE" ]]; then
  CONTAINER=$(xcrun simctl get_app_container "$SIM_ID" ru.recipescaler.RecipeScaler data 2>/dev/null || true)
  if [[ -n "$CONTAINER" && -f "$CONTAINER/Library/Caches/debug-session.ndjson" ]]; then
    cp "$CONTAINER/Library/Caches/debug-session.ndjson" "$LOG_FILE"
  fi
fi

echo "== Log ($LOG_FILE) =="
if [[ -s "$LOG_FILE" ]]; then
  cat "$LOG_FILE"
else
  echo "No debug log captured." >&2
  exit 1
fi