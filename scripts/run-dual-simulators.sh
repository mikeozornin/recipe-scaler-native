#!/usr/bin/env bash
# Build RecipeScalerNative once and launch on two simulators side by side:
#   iPhone 16 (iOS 18) + iPhone 17 (iOS 26) by default.
#
# Usage:
#   bash scripts/run-dual-simulators.sh
#   bash scripts/run-dual-simulators.sh -SkipSplash=1
#   SKIP_BUILD=1 bash scripts/run-dual-simulators.sh
#
# Env overrides:
#   SIM_A_NAME, SIM_A_IOS_MAJOR   — first device (default: iPhone 16, 18)
#   SIM_B_NAME, SIM_B_IOS_MAJOR   — second device (default: iPhone 17, 26)
#   SIM_A_ID, SIM_B_ID            — skip auto-discovery when set
#   SKIP_BUILD=1                  — reuse existing Debug .app bundle
#   LAUNCH_ARGS                   — extra simctl launch args (space-separated)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SIM_A_NAME="${SIM_A_NAME:-iPhone 16}"
SIM_A_IOS_MAJOR="${SIM_A_IOS_MAJOR:-18}"
SIM_B_NAME="${SIM_B_NAME:-iPhone 17}"
SIM_B_IOS_MAJOR="${SIM_B_IOS_MAJOR:-26}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [launch-arg ...]

Build Debug and run on two simulators:
  $SIM_A_NAME (iOS $SIM_A_IOS_MAJOR) + $SIM_B_NAME (iOS $SIM_B_IOS_MAJOR)

Options via env: SKIP_BUILD=1, SIM_A_ID, SIM_B_ID, LAUNCH_ARGS
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

sim_resolve_udid() {
  local name="$1"
  local ios_major="$2"
  python3 - "$name" "$ios_major" <<'PY'
import json, subprocess, sys

name, ios_major = sys.argv[1], sys.argv[2]
raw = subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"],
    text=True,
)
data = json.loads(raw)
needle = f"iOS-{ios_major}"
matches = []
for runtime, devices in data["devices"].items():
    if needle not in runtime.replace(".", "-"):
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name") == name:
            matches.append((runtime, device["udid"]))
if not matches:
    sys.exit(f"No available simulator: {name!r} on iOS {ios_major}.x", 1)
# Prefer the newest patch runtime within the major (lexicographic on runtime id works).
matches.sort(key=lambda item: item[0], reverse=True)
print(matches[0][1])
PY
}

SIM_A_ID="${SIM_A_ID:-$(sim_resolve_udid "$SIM_A_NAME" "$SIM_A_IOS_MAJOR")}"
SIM_B_ID="${SIM_B_ID:-$(sim_resolve_udid "$SIM_B_NAME" "$SIM_B_IOS_MAJOR")}"

launch_args=()
if [[ -n "${LAUNCH_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  launch_args=($LAUNCH_ARGS)
fi
if (($# > 0)); then
  launch_args+=("$@")
fi

echo "== Dual simulator launch =="
echo "  A: $SIM_A_NAME (iOS $SIM_A_IOS_MAJOR) → $SIM_A_ID"
echo "  B: $SIM_B_NAME (iOS $SIM_B_IOS_MAJOR) → $SIM_B_ID"
if ((${#launch_args[@]} > 0)); then
  echo "  Launch args: ${launch_args[*]}"
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  SIM_ID="$SIM_A_ID" VERIFY_SKIP_BUILD=0 sim_ensure_built
else
  echo "== Build Debug (skipped — SKIP_BUILD=1) =="
fi

SIM_ID="$SIM_A_ID" sim_resolve_app || exit 1
echo "App: $APP"

sim_boot_install_launch() {
  local sim_id="$1"
  local label="$2"
  echo "== [$label] boot =="
  xcrun simctl boot "$sim_id" 2>/dev/null || true
  xcrun simctl privacy "$sim_id" grant notifications "$BUNDLE_ID" 2>/dev/null || true
  echo "== [$label] install =="
  xcrun simctl install "$sim_id" "$APP"
  echo "== [$label] launch =="
  xcrun simctl terminate "$sim_id" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$sim_id" "$BUNDLE_ID" "${launch_args[@]}"
}

open -a Simulator 2>/dev/null || true

sim_boot_install_launch "$SIM_A_ID" "$SIM_A_NAME" &
pid_a=$!
sim_boot_install_launch "$SIM_B_ID" "$SIM_B_NAME" &
pid_b=$!

status=0
wait "$pid_a" || status=1
wait "$pid_b" || status=1

if (( status != 0 )); then
  echo "One or more simulators failed to launch." >&2
  exit "$status"
fi

echo "== Done =="
echo "  $SIM_A_NAME: $SIM_A_ID"
echo "  $SIM_B_NAME: $SIM_B_ID"
