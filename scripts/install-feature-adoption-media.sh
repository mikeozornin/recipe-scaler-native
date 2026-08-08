#!/usr/bin/env bash
# Install generated guide PNG/MP4 files into the native target.
#
# This script is intentionally explicit: it creates image sets in the existing
# app asset catalog and copies videos into the app's Resources/GuideVideos.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${GUIDE_MEDIA_OUTPUT:-$ROOT/.guide-media-capture}"
ASSET_ROOT="$ROOT/RecipeScalerNative/Assets.xcassets/GuideMedia"
VIDEO_ROOT="$ROOT/RecipeScalerNative/Resources/GuideVideos"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--input DIR]

Reads:
  DIR/{ru,en}/{light,dark}/*.png
  DIR/{ru,en}/{light,dark}/*.mp4

Writes:
  RecipeScalerNative/Assets.xcassets/GuideMedia/*.imageset
  RecipeScalerNative/Resources/GuideVideos/*.mp4
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) INPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -d "$INPUT" ]] || {
  echo "Missing capture directory: $INPUT" >&2
  exit 1
}

mkdir -p "$ASSET_ROOT" "$VIDEO_ROOT"

python3 - "$INPUT" "$ASSET_ROOT" <<'PY'
import json
import shutil
import sys
from pathlib import Path

input_root = Path(sys.argv[1])
asset_root = Path(sys.argv[2])

for path in sorted(input_root.glob("*/*/*.png")):
    locale = path.parts[-3]
    appearance = path.parts[-2]
    base = path.stem
    asset_name = f"{base}_{locale}_{appearance}"
    imageset = asset_root / f"{asset_name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    destination = imageset / f"{asset_name}.png"
    shutil.copy2(path, destination)
    contents = {
        "images": [
            {
                "filename": destination.name,
                "idiom": "universal",
                "scale": "1x"
            }
        ],
        "info": {"author": "xcode", "version": 1}
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"installed {destination}")
PY

find "$INPUT" -type f -name '*.mp4' -exec cp {} "$VIDEO_ROOT/" \;

echo "Guide media installed into:"
echo "  $ASSET_ROOT"
echo "  $VIDEO_ROOT"
