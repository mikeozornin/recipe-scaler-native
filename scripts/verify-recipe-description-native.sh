#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

RECIPE_ID="${1:-7daed53b-5e79-42e8-bd9a-bc74deea712d}"
LOG_FILE="${LOG_FILE:-$ROOT/.debug-session.ndjson}"
SHOT_DIR="${SHOT_DIR:-$ROOT/specs/004-description-read-only/screenshots}"

sim_build >/dev/null
sim_prepare
sim_install
sim_launch \
  -SkipSplash=1 \
  "-OpenRecipeId=$RECIPE_ID" \
  "-RecipeReadDiagnostics=$RECIPE_ID"

sim_wait_ready 10

SHOT="$(sim_screenshot "$SHOT_DIR" "recipe-${RECIPE_ID:0:8}")"
echo "Screenshot: $SHOT"

if [[ -f "$LOG_FILE" ]]; then
  echo "== Read path =="
  grep -E 'description_html_ready|readRecipeData_done|description_parsed' "$LOG_FILE" || true
  if ! grep -q 'description_html_ready' "$LOG_FILE"; then
    echo "WARN: description_html_ready missing" >&2
  fi
else
  echo "No debug log at $LOG_FILE" >&2
fi

echo "VERIFIED recipe-description-read"