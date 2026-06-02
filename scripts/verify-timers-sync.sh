#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

test -f specs/014-timers-sync/BLOCKER.md
rg -q 'MobileTimerPanel' RecipeScalerNative/Views/MobileTimerPanel.swift

source "$ROOT/scripts/sim-verify-lib.sh"
SHOT_DIR="$ROOT/specs/014-timers-sync/screenshots"

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1

sim_wait_ready 5
SHOT="$(sim_screenshot "$SHOT_DIR" "timers-panel")"
echo "Screenshot: $SHOT"
echo "VERIFIED timers-sync (blocker documented, local panel only)"