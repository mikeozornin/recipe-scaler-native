#!/usr/bin/env bash
# Resolve a usable iPhone simulator without depending on one machine-specific UDID.
#
# Usage:
#   SIM_ID=<udid> bash scripts/resolve-simulator.sh
#   bash scripts/resolve-simulator.sh
#
# The explicit SIM_ID override is intentionally checked first so CI and paired
# simulator workflows can retain deterministic destinations.

set -euo pipefail

if [[ -n "${SIM_ID:-}" ]]; then
  printf '%s\n' "$SIM_ID"
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT" <<'PY'
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


def runtime_version(identifier: str) -> tuple[int, ...]:
    match = re.search(r"iOS[- ](\d+(?:[-.]\d+)*)", identifier, re.IGNORECASE)
    if not match:
        return (0,)
    return tuple(int(part) for part in re.split(r"[-.]", match.group(1)))


try:
    payload = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        text=True,
    )
    devices = json.loads(payload).get("devices", {})
except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
    print(f"Unable to enumerate available iOS simulators: {exc}", file=sys.stderr)
    raise SystemExit(1)

candidates: list[tuple[int, tuple[int, ...], str, str, str]] = []
for runtime, runtime_devices in devices.items():
    if not runtime.lower().startswith("com.apple.coresimulator.simruntime.ios"):
        continue
    for device in runtime_devices:
        if device.get("isAvailable") is False:
            continue
        name = str(device.get("name", ""))
        if "iphone" not in name.lower():
            continue
        udid = str(device.get("udid", ""))
        if not udid:
            continue
        booted = 1 if device.get("state") == "Booted" else 0
        candidates.append((booted, runtime_version(runtime), name, udid, runtime))

if not candidates:
    print(
        "No available iPhone simulator found. Set SIM_ID explicitly or install an iOS runtime.",
        file=sys.stderr,
    )
    raise SystemExit(1)

# Prefer an already booted device, then the newest runtime, then a stable name.
candidates.sort(key=lambda item: (item[0], item[1], item[2]), reverse=True)
_, _, name, udid, runtime = candidates[0]
print(f"Resolved simulator: {name} ({runtime}, {udid})", file=sys.stderr)
print(udid)
PY
