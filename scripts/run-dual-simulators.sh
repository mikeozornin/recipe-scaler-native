#!/usr/bin/env bash
# Build RecipeScalerNative (embedded watch app) and launch on a paired
# iPhone + Apple Watch simulator set.
#
# Usage:
#   bash scripts/run-dual-simulators.sh
#   bash scripts/run-dual-simulators.sh -SkipSplash=1
#   SKIP_BUILD=1 bash scripts/run-dual-simulators.sh
#
# Env overrides:
#   PHONE_SIM_ID, WATCH_SIM_ID  — skip auto-discovery when both set
#   PHONE_SIM_NAME              — pick pair by iPhone name (default: first active pair)
#   PAIR_ID                     — specific simctl pair UUID
#   SKIP_BUILD=1                — reuse existing Debug .app bundle
#   LAUNCH_ARGS                 — extra simctl launch args for iPhone (space-separated)
#   WATCH_LAUNCH_DELAY_SEC      — seconds to wait after iPhone launch (default: 2)
#
# Legacy aliases: SIM_A_ID → phone, SIM_B_ID → watch
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

BUNDLE_ID_PHONE="$BUNDLE_ID"
BUNDLE_ID_WATCH="ru.recipescaler.RecipeScaler.watchkitapp"
WATCH_LAUNCH_DELAY_SEC="${WATCH_LAUNCH_DELAY_SEC:-4}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [iphone-launch-arg ...]

Build Debug and run on a paired iPhone + Apple Watch simulator set.

Discovery: \`simctl list pairs\` (override with PHONE_SIM_ID + WATCH_SIM_ID).

Options via env: SKIP_BUILD=1, PHONE_SIM_NAME, PAIR_ID, LAUNCH_ARGS
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

sim_resolve_pair() {
  python3 - <<'PY'
import json, os, subprocess, sys

phone_name = os.environ.get("PHONE_SIM_NAME", "")
pair_id = os.environ.get("PAIR_ID", "")
phone_id = os.environ.get("PHONE_SIM_ID") or os.environ.get("SIM_A_ID", "")
watch_id = os.environ.get("WATCH_SIM_ID") or os.environ.get("SIM_B_ID", "")

if phone_id and watch_id:
    print(phone_id, watch_id)
    sys.exit(0)

raw = subprocess.check_output(["xcrun", "simctl", "list", "pairs", "-j"], text=True)
pairs = json.loads(raw).get("pairs", {})
if not pairs:
    sys.exit("No paired iPhone/Watch simulators found. Create one in Xcode → Window → Devices and Simulators.", 1)

if pair_id:
    pair = pairs.get(pair_id)
    if pair is None:
        sys.exit(f"Pair not found: {pair_id}", 1)
    print(pair["phone"]["udid"], pair["watch"]["udid"])
    sys.exit(0)

candidates = list(pairs.values())
if phone_name:
    filtered = [p for p in candidates if p["phone"]["name"] == phone_name]
    if not filtered:
        names = ", ".join(sorted({p["phone"]["name"] for p in candidates}))
        sys.exit(f"No pair with phone {phone_name!r}. Available phones: {names}", 1)
    candidates = filtered

def sort_key(pair):
    state = pair.get("state", "")
    active = 1 if "active" in state else 0
    return (active, pair["phone"]["name"])

candidates.sort(key=sort_key, reverse=True)
pair = candidates[0]
print(pair["phone"]["udid"], pair["watch"]["udid"])
PY
}

read -r PHONE_SIM_ID WATCH_SIM_ID <<< "$(sim_resolve_pair)"

launch_args=()
if [[ -n "${LAUNCH_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  launch_args=($LAUNCH_ARGS)
fi
if (($# > 0)); then
  launch_args+=("$@")
fi

echo "== Paired simulator launch =="
echo "  iPhone: $PHONE_SIM_ID"
echo "  Watch:  $WATCH_SIM_ID"
if ((${#launch_args[@]} > 0)); then
  echo "  iPhone launch args: ${launch_args[*]}"
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  SIM_ID="$PHONE_SIM_ID" VERIFY_SKIP_BUILD=0 sim_ensure_built
else
  echo "== Build Debug (skipped — SKIP_BUILD=1) =="
fi

SIM_ID="$PHONE_SIM_ID" sim_resolve_app || exit 1
WATCH_APP="$APP/Watch/RecipeScalerNativeWatch.app"
if [[ ! -d "$WATCH_APP" ]]; then
  echo "Embedded watch app not found at: $WATCH_APP" >&2
  echo "Ensure RecipeScalerNative target has Embed Watch App build phase." >&2
  exit 1
fi
if [[ ! -d "$WATCH_APP/Frameworks/RecipeScalerCore.framework" ]]; then
  echo "RecipeScalerCore.framework missing from watch app bundle." >&2
  echo "Ensure RecipeScalerNativeWatch target embeds RecipeScalerCore.framework." >&2
  exit 1
fi
echo "iPhone app: $APP"
echo "Watch app:  $WATCH_APP"

sim_boot_phone() {
  echo "== [iPhone] boot =="
  xcrun simctl boot "$PHONE_SIM_ID" 2>/dev/null || true
  xcrun simctl privacy "$PHONE_SIM_ID" grant notifications "$BUNDLE_ID_PHONE" 2>/dev/null || true
}

sim_boot_watch() {
  echo "== [Watch] boot =="
  xcrun simctl boot "$WATCH_SIM_ID" 2>/dev/null || true
}

sim_install_phone() {
  echo "== [iPhone] install =="
  xcrun simctl install "$PHONE_SIM_ID" "$APP"
}

sim_install_watch() {
  echo "== [Watch] install (from iPhone bundle) =="
  xcrun simctl install "$WATCH_SIM_ID" "$WATCH_APP"
}

sim_launch_phone() {
  echo "== [iPhone] launch =="
  xcrun simctl terminate "$PHONE_SIM_ID" "$BUNDLE_ID_PHONE" 2>/dev/null || true
  if ((${#launch_args[@]} > 0)); then
    xcrun simctl launch "$PHONE_SIM_ID" "$BUNDLE_ID_PHONE" "${launch_args[@]}"
  else
    xcrun simctl launch "$PHONE_SIM_ID" "$BUNDLE_ID_PHONE"
  fi
}

sim_launch_watch() {
  echo "== [Watch] launch =="
  xcrun simctl terminate "$WATCH_SIM_ID" "$BUNDLE_ID_WATCH" 2>/dev/null || true
  xcrun simctl launch "$WATCH_SIM_ID" "$BUNDLE_ID_WATCH"
}

open -a Simulator 2>/dev/null || true

sim_boot_phone &
pid_boot_phone=$!
sim_boot_watch &
pid_boot_watch=$!
wait "$pid_boot_phone" "$pid_boot_watch"

sim_install_phone &
pid_install_phone=$!
sim_install_watch &
pid_install_watch=$!
wait "$pid_install_phone" "$pid_install_watch"

sim_launch_phone
sleep "$WATCH_LAUNCH_DELAY_SEC"
sim_launch_watch

echo "== Done =="
echo "  iPhone: $PHONE_SIM_ID ($BUNDLE_ID_PHONE)"
echo "  Watch:  $WATCH_SIM_ID ($BUNDLE_ID_WATCH)"
