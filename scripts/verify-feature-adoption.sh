#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/038-feature-adoption-tracker/screenshots"

rg -q 'FeatureAdoptionDetailView' RecipeScalerNative/Views/FeatureAdoptionDetailView.swift

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1 -OpenTab=profile

sim_wait_ready 8
SHOT="$(sim_screenshot "$SHOT_DIR" "feature-adoption")"
echo "Screenshot: $SHOT"
echo "VERIFIED feature-adoption"
