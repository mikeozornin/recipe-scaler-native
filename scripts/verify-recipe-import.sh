#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/010-recipe-import/screenshots"

test -f RecipeScalerNative/Views/ImportRecipeSheet.swift

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1 -OpenTab=import

sim_wait_ready 8
SHOT="$(sim_screenshot "$SHOT_DIR" "import")"
echo "Screenshot: $SHOT"
echo "VERIFIED recipe-import"