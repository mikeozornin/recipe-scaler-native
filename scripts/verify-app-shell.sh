#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/007-app-shell-navigation/screenshots"

test -f RecipeScalerNative/Views/AppShellView.swift

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1

sim_wait_ready 6
SHOT="$(sim_screenshot "$SHOT_DIR" "tabs")"
echo "Screenshot: $SHOT"
echo "VERIFIED app-shell"