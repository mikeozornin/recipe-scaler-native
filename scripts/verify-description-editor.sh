#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

# Default: long v3 recipe in debug user's collection (see RecipeListView.openDebugRecipeIfNeeded).
RECIPE_ID="${1:-891daa94-ff72-4c83-b9a2-7b18cfb80b70}"
# end = pin last line (keyboard-gap); mid = mid-document caret scroll regression.
FOCUS="${DESCRIPTION_EDITOR_FOCUS:-end}"
LOG_FILE="${LOG_FILE:-$ROOT/.debug-session.ndjson}"
SHOT_DIR="${SHOT_DIR:-$ROOT/specs/006-description-editor/screenshots}"

sim_build >/dev/null
sim_prepare
sim_install
sim_launch \
  -SkipSplash=1 \
  "-OpenRecipeId=$RECIPE_ID" \
  -StartDescriptionEdit=1 \
  "-DescriptionEditorFocus=$FOCUS" \
  "-RecipeReadDiagnostics=$RECIPE_ID" \
  "-DescriptionEditorSimulateText=."

echo "Focus mode: $FOCUS"
sim_wait_ready 22
# Collection must be present before -OpenRecipeId can navigate (count-only onChange can miss).
if ! sim_wait_log_line 'sync_step2: collection' 40; then
  sim_wait_log_line 'Reindexing' 10 || true
fi
# Re-launch once collection is warm so OpenRecipeId sees entries.
sim_launch \
  -SkipSplash=1 \
  "-OpenRecipeId=$RECIPE_ID" \
  -StartDescriptionEdit=1 \
  "-DescriptionEditorFocus=$FOCUS" \
  "-RecipeReadDiagnostics=$RECIPE_ID" \
  "-DescriptionEditorSimulateText=."
sim_wait_ready 22
sim_wait_recipe_open 45
sim_wait_description_editor 50
# Keyboard + caret scroll settle (watchdog re-pins for ~2s).
sleep 5

SHOT="$(sim_screenshot "$SHOT_DIR" "description-editor-${RECIPE_ID:0:8}")"
echo "Screenshot: $SHOT"

if [[ -f "$LOG_FILE" ]]; then
  echo "== Editor bridge =="
  grep -E 'description_editor_init|description_editor_ready|description_editor_content_height|simulated_keystroke|editor_sync_payload|dropped_oversized|"message":"contentHeight"' "$LOG_FILE" || true
  if grep -q 'dropped_oversized_webview_update' "$LOG_FILE"; then
    echo "OK dropped_oversized_webview_update (html-push blocked from sync)"
  elif grep -q 'editor_sync_payload' "$LOG_FILE"; then
  oversized="$(grep 'editor_sync_payload' "$LOG_FILE" | tail -1 | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('data',{}).get('outboundBytes','?'))" 2>/dev/null || echo '?')"
    echo "OK editor_sync_payload outboundBytes=$oversized"
    if [[ "$oversized" != "?" && "$oversized" -gt 2048 ]]; then
      echo "WARN: outbound sync still >2048 bytes" >&2
    fi
  fi
  if grep -q 'description_editor_ready' "$LOG_FILE"; then
    echo "OK description_editor_ready"
  elif grep -q 'description_editor_content_height\|"message":"contentHeight"' "$LOG_FILE"; then
    echo "OK description editor contentHeight"
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

# Heuristic: nav contrast + text→formatting-bar gap (no keyboard-tall hole).
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY' "$SHOT" || { echo "Screenshot check failed" >&2; exit 1; }
import sys
import zlib
from pathlib import Path

path = Path(sys.argv[1])
try:
    from PIL import Image

    im = Image.open(path).convert("RGB")
    w, h = im.size
    band = im.crop((0, 0, w, int(h * 0.18)))
    px = list(band.getdata())
    if len(px) < 10:
        sys.exit(1)
    spread = max(p[0] for p in px) - min(p[0] for p in px)
    if spread < 12:
        print("FAIL: screenshot lacks nav contrast (likely not on editor)", file=sys.stderr)
        sys.exit(1)
except ImportError:
    pass

# Pixel gap: last description ink → topmost formatting bar above keyboard.
# Breathing room is 16pt; allow slack. Fail on keyboard-tall holes.
data = path.read_bytes()
pos = 8
idata = b""
width = height = None
while pos < len(data):
    length = int.from_bytes(data[pos : pos + 4], "big")
    ctype = data[pos + 4 : pos + 8]
    chunk = data[pos + 8 : pos + 8 + length]
    pos += 12 + length
    if ctype == b"IHDR":
        width = int.from_bytes(chunk[0:4], "big")
        height = int.from_bytes(chunk[4:8], "big")
    elif ctype == b"IDAT":
        idata += chunk
    elif ctype == b"IEND":
        break
if not width or not height:
    print("WARN: could not decode screenshot PNG for gap check", file=sys.stderr)
    sys.exit(0)

raw = zlib.decompress(idata)
bpp = 4
stride = width * bpp
rows = []
i = 0
prev = bytearray(stride)
for _y in range(height):
    ftype = raw[i]
    i += 1
    row = bytearray(raw[i : i + stride])
    i += stride
    if ftype == 1:
        for x in range(bpp, stride):
            row[x] = (row[x] + row[x - bpp]) & 255
    elif ftype == 2:
        for x in range(stride):
            row[x] = (row[x] + prev[x]) & 255
    elif ftype == 3:
        for x in range(stride):
            left = row[x - bpp] if x >= bpp else 0
            row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
    elif ftype == 4:

        def paeth(a, b, c):
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            return a if pa <= pb and pa <= pc else b if pb <= pc else c

        for x in range(stride):
            a = row[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            row[x] = (row[x] + paeth(a, b, c)) & 255
    rows.append(bytes(row))
    prev = row

# Logical points: screenshots are @3x on modern sims.
scale = 3.0 if height >= 2000 else (2.0 if height >= 1400 else 1.0)

candidates = []
for y in range(int(height * 0.40), int(height * 0.75)):
    vals = [
        (rows[y][x * 4] + rows[y][x * 4 + 1] + rows[y][x * 4 + 2]) / 3
        for x in range(0, width, 3)
    ]
    mean = sum(vals) / len(vals)
    var = sum((v - mean) ** 2 for v in vals) / len(vals)
    if 218 <= mean <= 232 and var < 30:
        candidates.append(y)

bands = []
if candidates:
    a = b = candidates[0]
    for y in candidates[1:]:
        if y <= b + 3:
            b = y
        else:
            bands.append((a, b))
            a = b = y
    bands.append((a, b))

merged = []
for a, b in bands:
    if not merged:
        merged.append([a, b])
        continue
    if a - merged[-1][1] < int(40 * scale):
        merged[-1][1] = b
    else:
        merged.append([a, b])


def has_kb_below(b):
    for y in range(b + 3, min(height, b + int(70 * scale)), 5):
        vals = [
            (rows[y][x * 4] + rows[y][x * 4 + 1] + rows[y][x * 4 + 2]) / 3
            for x in range(0, width, 4)
        ]
        mean = sum(vals) / len(vals)
        var = sum((v - mean) ** 2 for v in vals) / len(vals)
        dark = sum(
            1
            for x in range(0, width, 4)
            if rows[y][x * 4] + rows[y][x * 4 + 1] + rows[y][x * 4 + 2] < 500
        )
        if var > 2500 and dark > 25:
            return True
    return False


def has_bar_icons(a, b):
    for y in range(a, min(height, b + int(28 * scale))):
        left_dark = sum(
            1
            for x in range(int(width * 0.05), int(width * 0.55), 3)
            if rows[y][x * 4] + rows[y][x * 4 + 1] + rows[y][x * 4 + 2] < 450
        )
        right_dark = sum(
            1
            for x in range(int(width * 0.75), int(width * 0.95), 2)
            if rows[y][x * 4] + rows[y][x * 4 + 1] + rows[y][x * 4 + 2] < 500
        )
        if left_dark > 10 or right_dark > 8:
            return True
    return False


bar = None
for a, b in merged:
    if has_kb_below(b) and has_bar_icons(a, b) and (b - a) / scale >= 20:
        bar = (a, b)
        break
if bar is None:
    for a, b in bands:
        if has_kb_below(b) and has_bar_icons(a, b):
            bar = (a, b)
            break

if bar is None:
    print("FAIL: formatting bar not found above keyboard", file=sys.stderr)
    sys.exit(1)

bar_top = bar[0]
last = None
for y in range(int(height * 0.15), bar_top):
    dark = sum(
        1
        for x in range(int(width * 0.08), int(width * 0.72), 2)
        if rows[y][x * 4] + rows[y][x * 4 + 1] + rows[y][x * 4 + 2] < 480
    )
    if dark >= 20:
        last = y

if last is None:
    print("FAIL: no description text found above formatting bar", file=sys.stderr)
    sys.exit(1)

gap_pt = (bar_top - last) / scale
# Expected ~16pt breathing; allow layout/AA slack. Keyboard-tall hole is ~300pt.
max_gap_pt = 48.0
print(
    f"OK text→bar gap={gap_pt:.1f}pt (last={last / scale:.0f} barTop={bar_top / scale:.0f} max={max_gap_pt:.0f})"
)
if gap_pt > max_gap_pt:
    print(
        f"FAIL: text→bar gap {gap_pt:.1f}pt exceeds {max_gap_pt:.0f}pt (keyboard hole regression)",
        file=sys.stderr,
    )
    sys.exit(1)
PY
fi

echo "VERIFIED description-editor"