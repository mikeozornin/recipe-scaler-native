#!/usr/bin/env bash
# Validate App Store screenshot PNG sizes and store release gates.
#
# Usage: validate-app-store-screenshots.sh [--device iphone-6.9|ipad-13|all]   (default all)
#   iphone-6.9: store/screenshots/iphone-6.9/{locale}/{appearance}/*.png
#   ipad-13:    store/screenshots/ipad-13/{ru,en}/light/landscape/ — exactly the store set
#               01-recipes 02-cooking 03-discover 04-shopping 05-assistant 09-nutrition
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/RecipeScalerNative.xcodeproj/project.pbxproj"
DEVICE="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
case "$DEVICE" in
  iphone-6.9|ipad-13|all) ;;
  *) echo "Unknown device: $DEVICE (iphone-6.9 | ipad-13 | all)" >&2; exit 1 ;;
esac

python3 - "$ROOT/store/screenshots" "$PBXPROJ" "$DEVICE" <<'PY'
import re
import struct
import subprocess
import sys
from pathlib import Path

shots_root = Path(sys.argv[1])
pbxproj = Path(sys.argv[2]).read_text()
device = sys.argv[3]
errors: list[str] = []

main_family = re.findall(
    r'PRODUCT_BUNDLE_IDENTIFIER = ru\.recipescaler\.RecipeScaler;\s*\n\s*SDKROOT = iphoneos;\s*\n\s*TARGETED_DEVICE_FAMILY = ([^;]+);',
    pbxproj,
)
if not main_family:
    # Debug config has extra RS_ALLOWS_LOCAL_NETWORKING line.
    main_family = re.findall(
        r'PRODUCT_BUNDLE_IDENTIFIER = ru\.recipescaler\.RecipeScaler;\n(?:.*\n)*?\s*TARGETED_DEVICE_FAMILY = ([^;]+);',
        pbxproj,
    )
families = {value.strip().strip('"') for value in main_family}
# Spec 081: the app is universal (iPhone + iPad), so ASC asks for iPad 13″ shots too.
if families != {"1,2"}:
    errors.append(f"main app TARGETED_DEVICE_FAMILY must be 1,2 (spec 081), got {sorted(families) or 'missing'}")

if "RecipeScalerNativeWatch.app in Embed Watch Content" not in pbxproj:
    errors.append(
        "store archive must embed RecipeScalerNativeWatch via Embed Watch Content"
    )

IPAD_PORTRAIT = {(2064, 2752), (2048, 2732)}
DEVICES = {
    # device dir: (glob, accepted sizes by orientation dir or None)
    "iphone-6.9": ("*/*/*.png", {None: {(1260, 2736), (1320, 2868), (1290, 2796)}}),
    "ipad-13": (
        "*/*/*/*.png",
        {
            "portrait": IPAD_PORTRAIT,
            "landscape": {(h, w) for w, h in IPAD_PORTRAIT},
        },
    ),
}

# The iPad 13″ store set (spec 081): landscape, light, these shots per locale. Anything
# else under ipad-13/ (dark, portrait, other shots) is not for upload.
IPAD_SHOTS = ("01-recipes", "02-cooking", "03-discover", "04-shopping", "05-assistant", "09-nutrition")
EXPECTED = {
    "ipad-13": {
        f"{locale}/light/landscape/{shot}.png" for locale in ("ru", "en") for shot in IPAD_SHOTS
    },
}

for name, (pattern, accepted_by_orientation) in DEVICES.items():
    if device not in ("all", name):
        continue
    out_root = shots_root / name
    pngs = sorted(out_root.glob(pattern))
    if not pngs:
        print(f"no PNGs under {out_root} (capture first, or this is a fixtures-only checkout)")
        continue
    expected = EXPECTED.get(name)
    if expected is not None:
        found = {path.relative_to(out_root).as_posix() for path in out_root.rglob("*.png")}
        for rel in sorted(expected - found):
            errors.append(f"{name}/{rel}: missing")
        for rel in sorted(found - expected):
            errors.append(f"{name}/{rel}: not in the store set (move it out of {name}/)")
    for path in pngs:
        rel = path.relative_to(shots_root)
        if None in accepted_by_orientation:
            accepted = accepted_by_orientation[None]
        else:
            accepted = accepted_by_orientation.get(path.parent.name)
            if accepted is None:
                errors.append(f"{rel}: orientation folder must be portrait or landscape")
                continue
        data = path.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            errors.append(f"{rel}: not a PNG")
            continue
        width, height = struct.unpack(">II", data[16:24])
        status = "OK" if (width, height) in accepted else "BAD"
        print(f"{rel}: {width}x{height} {status}")
        if (width, height) not in accepted:
            errors.append(f"{rel}: unexpected size {width}x{height}")
        if path.stat().st_size > 10 * 1024 * 1024:
            errors.append(f"{rel}: larger than 10 MB")
        # App Store Connect rejects screenshots with an alpha channel; sips is the source of truth.
        sips = subprocess.run(
            ["sips", "-g", "hasAlpha", str(path)], capture_output=True, text=True, check=False
        )
        if sips.returncode != 0:
            errors.append(f"{rel}: sips could not read the file to check for alpha")
        elif "hasAlpha: yes" in sips.stdout:
            errors.append(f"{rel}: has an alpha channel (flatten to opaque RGB)")

if errors:
    print("validation failed:", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    raise SystemExit(1)
print("store screenshot validation OK")
PY
