#!/usr/bin/env bash
# Validate App Store screenshot PNG sizes and store release gates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="$ROOT/store/screenshots/iphone-6.9"
PBXPROJ="$ROOT/RecipeScalerNative.xcodeproj/project.pbxproj"

python3 - "$OUT_ROOT" "$PBXPROJ" <<'PY'
import re
import struct
import sys
from pathlib import Path

out_root = Path(sys.argv[1])
pbxproj = Path(sys.argv[2]).read_text()
accepted = {(1260, 2736), (1320, 2868), (1290, 2796)}
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
if families != {"1"}:
    errors.append(f"main app TARGETED_DEVICE_FAMILY must be 1, got {sorted(families) or 'missing'}")

if "RecipeScalerNativeWatch.app in Embed Watch App" in pbxproj:
    print("note: Watch is still embedded for Debug dual-sim. Strip Embed Watch App before the v1 store archive.")

pngs = sorted(out_root.glob("*/*/*.png"))
if not pngs:
    print(f"no PNGs under {out_root} (capture first, or this is a fixtures-only checkout)")
else:
    for path in pngs:
        data = path.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            errors.append(f"{path}: not a PNG")
            continue
        width, height = struct.unpack(">II", data[16:24])
        rel = path.relative_to(out_root)
        status = "OK" if (width, height) in accepted else "BAD"
        print(f"{rel}: {width}x{height} {status}")
        if (width, height) not in accepted:
            errors.append(f"{rel}: unexpected size {width}x{height}")
        if path.stat().st_size > 10 * 1024 * 1024:
            errors.append(f"{rel}: larger than 10 MB")

if errors:
    print("validation failed:", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    raise SystemExit(1)
print("store screenshot validation OK")
PY
