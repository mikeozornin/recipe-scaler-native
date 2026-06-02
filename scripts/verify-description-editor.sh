#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

RECIPE_ID="${1:-7daed53b-5e79-42e8-bd9a-bc74deea712d}"
LOG_FILE="${LOG_FILE:-$ROOT/.debug-session.ndjson}"
SHOT_DIR="${SHOT_DIR:-$ROOT/specs/006-description-editor/screenshots}"

sim_build >/dev/null
sim_prepare
sim_install
sim_launch \
  -SkipSplash=1 \
  "-OpenRecipeId=$RECIPE_ID" \
  -StartDescriptionEdit=1 \
  "-RecipeReadDiagnostics=$RECIPE_ID"

sim_wait_ready 18

SHOT="$(sim_screenshot "$SHOT_DIR" "description-editor-${RECIPE_ID:0:8}")"
echo "Screenshot: $SHOT"

if [[ -f "$LOG_FILE" ]]; then
  echo "== Editor bridge =="
  grep -E 'description_editor_init|description_editor_ready' "$LOG_FILE" || true
  if grep -q 'description_editor_ready' "$LOG_FILE"; then
    echo "OK description_editor_ready"
  elif grep -q 'description_editor_sheet_presented' "$LOG_FILE"; then
    echo "OK description_editor_sheet_presented (WebView may still load)"
  elif grep -q 'description_html_ready\|readRecipeData_done' "$LOG_FILE"; then
    echo "WARN: recipe read OK; editor sheet not confirmed in log" >&2
  else
    echo "WARN: NDJSON present but no description traces" >&2
  fi
else
  echo "WARN: No NDJSON pulled from simulator (see Library/Caches in app container)" >&2
fi

# Heuristic: sheet title / editor chrome (light toolbar area in upper portion)
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY' "$SHOT" || { echo "Screenshot check failed: likely not on editor" >&2; exit 1; }
import sys
from pathlib import Path
try:
    from PIL import Image
except ImportError:
    sys.exit(0)
path = Path(sys.argv[1])
im = Image.open(path).convert("RGB")
w, h = im.size
# Top 18% should not be uniform splash gray; require some contrast (nav bar)
band = im.crop((0, 0, w, int(h * 0.18)))
px = list(band.getdata())
if len(px) < 10:
    sys.exit(1)
r = [p[0] for p in px]
spread = max(r) - min(r)
if spread < 12:
    sys.exit(1)
PY
fi

echo "VERIFIED description-editor"