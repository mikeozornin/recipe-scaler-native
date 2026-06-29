#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/038-feature-adoption-tracker/screenshots"

rg -q 'FeatureAdoptionDetailView' RecipeScalerNative/Views/FeatureAdoptionDetailView.swift
rg -q 'WatchFeatureAdoptionReporter' RecipeScalerNativeWatch/Services/WatchFeatureAdoptionReporter.swift
rg -q 'installed_watch_app' RecipeScalerNative/Models/FeatureAdoptionItem.swift
rg -q 'installedWatchApp' RecipeScalerNative/Services/FeatureAdoptionStore.swift
rg -q 'FeatureAdoptionClientFeature' RecipeScalerCore/Networking/FeatureAdoptionClientFeature.swift
rg -q 'FeatureAdoptionRingLabelLayout' RecipeScalerNative/Utils/FeatureAdoptionRingLabelLayout.swift

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1 -OpenTab=profile

sim_wait_ready 8
SHOT="$(sim_screenshot "$SHOT_DIR" "feature-adoption")"
echo "Screenshot: $SHOT"
echo "VERIFIED feature-adoption"
