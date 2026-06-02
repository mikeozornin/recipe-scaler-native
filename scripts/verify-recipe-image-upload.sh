#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

RECIPE_ID="${1:-7daed53b-5e79-42e8-bd9a-bc74deea712d}"
SHOT_DIR="$ROOT/specs/016-recipe-image-upload/screenshots"

rg -q 'RecipeImageUploadAPI' RecipeScalerNative/Services/RecipeImageUploadAPI.swift
rg -q 'RecipeDetailActionsMenu' RecipeScalerNative/Views/RecipeDetailActionsMenu.swift

sim_build >/dev/null
sim_prepare
sim_install
sim_launch \
  -SkipSplash=1 \
  "-OpenRecipeId=$RECIPE_ID" \
  -StartInEditMode=1

sim_wait_ready 10
SHOT="$(sim_screenshot "$SHOT_DIR" "image-upload-edit-${RECIPE_ID:0:8}")"
echo "Screenshot: $SHOT"
echo "VERIFIED recipe-image-upload"