#!/usr/bin/env bash
# Capture localized Feature Adoption guide media from deterministic DEBUG scenes.
#
# Examples:
#   bash scripts/capture-feature-adoption-media.sh \
#     --scene connected_mcp_assistant.external-assistant \
#     --locale ru --appearance dark
#
#   bash scripts/capture-feature-adoption-media.sh \
#     --item imported_recipe --all-locales --all-appearances

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-capture-lib.sh"

MANIFEST="$ROOT/specs/040-feature-adoption-guides/guide-media-manifest.json"
OUT_ROOT="${GUIDE_MEDIA_OUTPUT:-$ROOT/.guide-media-capture}"
SKIP_BUILD=0
ALL_LOCALES=0
ALL_APPEARANCES=0
LOCALE="ru"
APPEARANCE="light"
SCENE=""
ITEM=""
VIDEO=0
VIDEO_ID=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --scene ID             Capture one manifest scene.
  --item ITEM            Capture all scenes for one feature item.
  --video ID             Capture one manifest video.
  --locale ru|en         Capture one locale (default: ru).
  --appearance light|dark
  --all-locales
  --all-appearances
  --skip-build
  --output DIR           Override output directory.

Scenes are written to:
  \$OUTPUT/{locale}/{appearance}/{asset}.png

Videos are written to:
  \$OUTPUT/{locale}/{appearance}/{output}.mp4
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scene) SCENE="$2"; shift 2 ;;
    --item) ITEM="$2"; shift 2 ;;
    --video) VIDEO=1; VIDEO_ID="$2"; shift 2 ;;
    --locale) LOCALE="$2"; shift 2 ;;
    --appearance) APPEARANCE="$2"; shift 2 ;;
    --all-locales) ALL_LOCALES=1; shift ;;
    --all-appearances) ALL_APPEARANCES=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --output) OUT_ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -f "$MANIFEST" ]] || {
  echo "Missing guide media manifest: $MANIFEST" >&2
  exit 1
}

python3 - "$MANIFEST" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
if data.get("version") != "1.0":
    raise SystemExit("guide media manifest version must be 1.0")
if data.get("schema") != "recipe-scaler.feature-adoption-guide-media":
    raise SystemExit("unexpected guide media manifest schema")
PY

if [[ -n "$SCENE" && -n "$ITEM" ]]; then
  echo "Use either --scene or --item, not both." >&2
  exit 1
fi
if [[ -n "$VIDEO_ID" && ( -n "$SCENE" || -n "$ITEM" ) ]]; then
  echo "Use --video separately from --scene/--item." >&2
  exit 1
fi
if [[ -z "$VIDEO_ID" && -z "$SCENE" && -z "$ITEM" ]]; then
  echo "One of --scene, --item, or --video is required." >&2
  exit 1
fi

scene_json_lines() {
  if [[ -z "$SCENE" && -z "$ITEM" ]]; then
    exit 0
  fi
python3 - "$MANIFEST" "$SCENE" "$ITEM" <<'PY'
import json
import sys

manifest, scene_id, item = sys.argv[1:]
data = json.load(open(manifest))
matches = [
    scene for scene in data["scenes"]
    if (not scene_id or scene["id"] == scene_id)
    and (not item or scene["item"] == item)
]
if scene_id and not matches:
    raise SystemExit(f"scene not found: {scene_id}")
if item and not matches:
    raise SystemExit(f"item has no scenes: {item}")
for scene in matches:
    print(json.dumps(scene))
PY
}

video_json_lines() {
python3 - "$MANIFEST" "$VIDEO_ID" <<'PY'
import json
import sys

manifest, video_id = sys.argv[1:]
if not video_id:
    raise SystemExit(0)
data = json.load(open(manifest))
matches = [video for video in data["videos"] if video["id"] == video_id]
if not matches:
    raise SystemExit(f"video not found: {video_id}")
for video in matches:
    print(json.dumps(video))
PY
}

if [[ "$SKIP_BUILD" != "1" ]]; then
  sim_ensure_built
fi
capture_resolve_sim
sim_prepare
sim_install

LOCALES=( "$LOCALE" )
APPEARANCES=( "$APPEARANCE" )
if [[ "$ALL_LOCALES" == "1" ]]; then LOCALES=(ru en); fi
if [[ "$ALL_APPEARANCES" == "1" ]]; then APPEARANCES=(light dark); fi

for language in "${LOCALES[@]}"; do
  for appearance in "${APPEARANCES[@]}"; do
    capture_set_os_locale "$language"
    capture_set_appearance "$appearance"

    while IFS= read -r scene_json; do
      [[ -n "$scene_json" ]] || continue
      scene_values=()
      while IFS= read -r value; do
        scene_values+=("$value")
      done < <(python3 - "$scene_json" <<'PY'
import json
import sys

scene = json.loads(sys.argv[1])
print(scene["launchScene"])
print(scene["assetBaseName"])
PY
)
      scene_id="${scene_values[0]}"
      asset_base="${scene_values[1]}"
      output="$OUT_ROOT/$language/$appearance/${asset_base}.png"
      echo "== Capture $language/$appearance/$scene_id =="
      capture_launch "$scene_id" "$language" "$appearance"
      capture_png "$output"
      capture_validate_png_dimensions "$output"
    done < <(scene_json_lines)

    while IFS= read -r video_json; do
      [[ -n "$video_json" ]] || continue
      video_values=()
      while IFS= read -r value; do
        video_values+=("$value")
      done < <(python3 - "$video_json" <<'PY'
import json
import sys

video = json.loads(sys.argv[1])
print(video["launchScene"])
print(video["output"])
print(video["durationSeconds"])
PY
)
      scene_id="${video_values[0]}"
      output="$OUT_ROOT/$language/$appearance/${video_values[1]}"
      echo "== Record $language/$appearance/$scene_id =="
      capture_launch "$scene_id" "$language" "$appearance" "$scene_id"
      capture_video "$output" "${video_values[2]}"
    done < <(video_json_lines)
  done
done

echo "Guide media capture complete: $OUT_ROOT"
