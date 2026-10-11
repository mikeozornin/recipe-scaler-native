#!/usr/bin/env bash
# Resolve a usable iPad simulator (spec 081) without depending on one
# machine-specific UDID. Counterpart of scripts/resolve-simulator.sh (iPhone).
#
# Usage:
#   IPAD_ID="$(bash scripts/resolve-ipad-simulator.sh)"
#   IPAD_SIM_ID=<udid> bash scripts/resolve-ipad-simulator.sh   # explicit override
#
#   xcodebuild -scheme RecipeScalerNative \
#     -destination "platform=iOS Simulator,id=$IPAD_ID" build
#
# Selection order (first match wins):
#   1. IPAD_SIM_ID override (printed as-is, for CI and dedicated simulators);
#   2. name preference: "iPad Pro 11-inch (M4)" → "iPad Air 11-inch" → any iPad;
#   3. newest iOS runtime;
#   4. already booted device;
#   5. stable name order.
#
# Prints the UDID on stdout and a human-readable line on stderr.
# Simulators whose names start with "Scrapp" belong to another project and are
# never selected.

set -euo pipefail

if [[ -n "${IPAD_SIM_ID:-}" ]]; then
  printf '%s\n' "$IPAD_SIM_ID"
  exit 0
fi

python3 - <<'PY'
from __future__ import annotations

import json
import re
import subprocess
import sys

PREFERRED_NAMES = ("ipad pro 11-inch (m4)", "ipad air 11-inch")
EXCLUDED_PREFIXES = ("scrapp",)


def runtime_version(identifier: str) -> tuple[int, ...]:
    match = re.search(r"iOS[- ](\d+(?:[-.]\d+)*)", identifier, re.IGNORECASE)
    if not match:
        return (0,)
    return tuple(int(part) for part in re.split(r"[-.]", match.group(1)))


def name_rank(name: str) -> int:
    lowered = name.lower()
    for index, preferred in enumerate(PREFERRED_NAMES):
        if lowered.startswith(preferred):
            # Higher is better: first preference gets the largest rank.
            return len(PREFERRED_NAMES) - index
    return 0


try:
    payload = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        text=True,
    )
    devices = json.loads(payload).get("devices", {})
except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
    print(f"Unable to enumerate available iOS simulators: {exc}", file=sys.stderr)
    raise SystemExit(1)

candidates: list[tuple[int, tuple[int, ...], int, str, str, str]] = []
for runtime, runtime_devices in devices.items():
    if not runtime.lower().startswith("com.apple.coresimulator.simruntime.ios"):
        continue
    for device in runtime_devices:
        if device.get("isAvailable") is False:
            continue
        name = str(device.get("name", ""))
        lowered = name.lower()
        if "ipad" not in lowered:
            continue
        if lowered.startswith(EXCLUDED_PREFIXES):
            continue
        udid = str(device.get("udid", ""))
        if not udid:
            continue
        booted = 1 if device.get("state") == "Booted" else 0
        candidates.append(
            (name_rank(name), runtime_version(runtime), booted, name, udid, runtime)
        )

if not candidates:
    print(
        "No available iPad simulator found. Set IPAD_SIM_ID explicitly or create one, e.g.\n"
        "  xcrun simctl create 'iPad Pro 11-inch (M4)' "
        "'com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-16GB' <runtime-id>",
        file=sys.stderr,
    )
    raise SystemExit(1)

candidates.sort(key=lambda item: (item[0], item[1], item[2], item[3]), reverse=True)
_, _, _, name, udid, runtime = candidates[0]
print(f"Resolved iPad simulator: {name} ({runtime}, {udid})", file=sys.stderr)
print(udid)
PY
