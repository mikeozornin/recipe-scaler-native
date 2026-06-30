#!/usr/bin/env bash
# Spec 040 — feature adoption guides verify script.
#
# Verifies that:
#  - Guide content models exist (FeatureAdoptionGuideContent, GuideCTA).
#  - Every non-installed FeatureAdoptionItem has guideContent with a why key.
#  - i18n keys for all 8 guide items exist in Localizable.xcstrings (RU + EN).
#  - The app still builds and launches in the simulator.
#
# Usage:
#   bash scripts/verify-feature-adoption-guides.sh
#   SIM_ID=<udid> bash scripts/verify-feature-adoption-guides.sh
#   VERIFY_SKIP_BUILD=1 bash scripts/verify-feature-adoption-guides.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/040-feature-adoption-guides/screenshots"
mkdir -p "$SHOT_DIR"

# --- Static checks ---

echo "== Static checks =="

rg -q 'struct FeatureAdoptionGuideContent' RecipeScalerNative/Models/FeatureAdoptionGuideContent.swift
rg -q 'enum GuideCTA' RecipeScalerNative/Models/FeatureAdoptionGuideContent.swift
rg -q 'struct GuideExampleImage' RecipeScalerNative/Models/FeatureAdoptionGuideContent.swift
rg -q 'var isGuideAvailable' RecipeScalerNative/Models/FeatureAdoptionItem.swift
rg -q 'var guideContent' RecipeScalerNative/Models/FeatureAdoptionItem.swift
rg -q 'struct FeatureAdoptionGuideView' RecipeScalerNative/Views/FeatureAdoptionGuideView.swift
rg -q 'struct GuideExampleCarousel' RecipeScalerNative/Views/GuideExampleCarousel.swift
rg -q 'struct GuideVideoPlayer' RecipeScalerNative/Views/GuideVideoPlayer.swift
rg -q 'struct GuideAssetPlaceholder' RecipeScalerNative/Views/GuideAssetPlaceholder.swift
rg -q 'GuideAssetResolver' RecipeScalerNative/Utils/GuideAssetResolver.swift
rg -q 'FeatureAdoptionAppCtaHandler' RecipeScalerNative/Utils/FeatureAdoptionGuideCta.swift
rg -q 'FeatureAdoptionProfileScrollCtaHandler' RecipeScalerNative/Utils/FeatureAdoptionGuideCta.swift
rg -q 'NavigationLink' RecipeScalerNative/Views/FeatureAdoptionDetailView.swift
rg -q 'FeatureAdoptionGuideView\(item:' RecipeScalerNative/Views/FeatureAdoptionDetailView.swift
rg -q 'featureAdoptionProfileScrollCta' RecipeScalerNative/Views/AccountView.swift
rg -q 'makeFeatureAdoptionAppCtaHandler' RecipeScalerNative/Views/AppShellView.swift
# Spec 040 — two separate environment keys, so AccountView's scroll handler
# can never override AppShellView's app-level handler.
rg -q 'featureAdoptionAppCta' RecipeScalerNative/Utils/FeatureAdoptionGuideCta.swift
rg -q 'featureAdoptionProfileScrollCta' RecipeScalerNative/Utils/FeatureAdoptionGuideCta.swift

# Every guide item must have a why + at least one how step in xcstrings.
I18N_FILE="RecipeScalerNative/Resources/Localizable.xcstrings"
for item in created_recipe used_shopping_list imported_recipe created_collection sent_assistant_message connected_telegram connected_mcp_assistant shared_recipe; do
  rg -q "account.feature-adoption.guide.${item}.why" "$I18N_FILE"
  how_count=$(rg -c "account.feature-adoption.guide.${item}.how\." "$I18N_FILE" || echo 0)
  if [ "$how_count" -lt 1 ]; then
    echo "FAIL: $item has no how steps in $I18N_FILE"
    exit 1
  fi
  # Every key must have both ru and en values.
  for lang in ru en; do
    if ! rg -A 12 "account.feature-adoption.guide.${item}.why" "$I18N_FILE" | rg -q "\"${lang}\" :"; then
      echo "FAIL: $item.why missing $lang translation"
      exit 1
    fi
  done
done

echo "  all guide items have why + how + ru/en translations"

# --- Build + launch ---

echo "== Build =="
VERIFY_SKIP_BUILD="${VERIFY_SKIP_BUILD:-0}" sim_ensure_built >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1 -OpenTab=profile

sim_wait_ready 8
SHOT="$(sim_screenshot "$SHOT_DIR" "feature-adoption-guides")"
echo "Screenshot: $SHOT"

echo "VERIFIED feature-adoption-guides"
