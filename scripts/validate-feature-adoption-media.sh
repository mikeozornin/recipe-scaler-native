#!/usr/bin/env bash
# Validate the Feature Adoption guide media contract and captured files.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/specs/040-feature-adoption-guides/guide-media-manifest.json"
OUTPUT="${GUIDE_MEDIA_OUTPUT:-$ROOT/.guide-media-capture}"
REQUIRE_CAPTURE="${REQUIRE_GUIDE_MEDIA_CAPTURE:-0}"

if [[ "$REQUIRE_CAPTURE" == "1" && ! -d "$OUTPUT" ]]; then
  echo "capture output is required: $OUTPUT" >&2
  exit 1
fi

[[ -f "$MANIFEST" ]] || {
  echo "Missing manifest: $MANIFEST" >&2
  exit 1
}

python3 - "$MANIFEST" "$OUTPUT" <<'PY'
import json
import struct
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
output_root = Path(sys.argv[2])
data = json.loads(manifest_path.read_text())
errors = []

if data.get("version") != "1.0":
    errors.append("manifest.version must be 1.0")
if data.get("schema") != "recipe-scaler.feature-adoption-guide-media":
    errors.append("manifest.schema is invalid")
if data.get("locales") != ["ru", "en"]:
    errors.append("manifest.locales must contain ru and en")
if data.get("appearances") != ["light", "dark"]:
    errors.append("manifest.appearances must contain light and dark")

scene_ids = set()
for scene in data.get("scenes", []):
    scene_id = scene.get("id")
    if scene_id in scene_ids:
        errors.append(f"duplicate scene id: {scene_id}")
    scene_ids.add(scene_id)
    for key in ("item", "kind", "launchScene", "assetBaseName", "titleKey"):
        if not scene.get(key):
            errors.append(f"scene {scene_id} missing {key}")
    if scene.get("durationSeconds", 0) <= 0:
        errors.append(f"scene {scene_id} has invalid duration")

video_ids = set()
for video in data.get("videos", []):
    video_id = video.get("id")
    if video_id in video_ids:
        errors.append(f"duplicate video id: {video_id}")
    video_ids.add(video_id)
    if video.get("codec") != "h264":
        errors.append(f"video {video_id} must use h264")
    if video.get("durationSeconds", 0) <= 0:
        errors.append(f"video {video_id} has invalid duration")

accepted_sizes = {
    tuple(size) for size in data.get("device", {}).get("acceptedPixelSizes", [])
}

captured_scene_assets = [
    scene["assetBaseName"]
    for scene in data.get("scenes", [])
]

if output_root.exists():
    for locale in data.get("locales", []):
        for appearance in data.get("appearances", []):
            base = output_root / locale / appearance
            for asset in captured_scene_assets:
                path = base / f"{asset}.png"
                if not path.exists():
                    continue
                raw = path.read_bytes()
                if raw[:8] != b"\x89PNG\r\n\x1a\n":
                    errors.append(f"{path} is not PNG")
                    continue
                size = struct.unpack(">II", raw[16:24])
                if size not in accepted_sizes:
                    errors.append(f"{path} has unexpected size {size[0]}x{size[1]}")
                if path.stat().st_size > 10 * 1024 * 1024:
                    errors.append(f"{path} exceeds 10 MB")

            for video in data.get("videos", []):
                path = base / video["output"]
                if path.exists() and path.stat().st_size == 0:
                    errors.append(f"{path} is empty")
else:
    print(f"capture output does not exist yet: {output_root}")

if errors:
    print("feature adoption media validation failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)

print(
    f"manifest OK: {len(data.get('scenes', []))} scenes, "
    f"{len(data.get('videos', []))} videos"
)
PY
