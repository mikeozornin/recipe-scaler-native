#!/usr/bin/env bash
# Verify script for spec 027 (Paprika / Crouton import).
# Builds the app and runs the ThirdParty* XCTest suite.
set -euo pipefail

cd "$(dirname "$0")/.."

DEST_ID="${XCODE_DEST_ID:-EFC65E55-4F28-4C21-B489-D9733D2BE6B5}"

echo "==> Building RecipeScalerNative (Debug)"
xcodebuild \
  -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=${DEST_ID}" \
  build-for-testing

echo "==> Running ThirdParty* test suites"
xcodebuild \
  -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=${DEST_ID}" \
  test-without-building \
  -only-testing:RecipeScalerNativeTests/PaprikaRecipeParserTests \
  -only-testing:RecipeScalerNativeTests/CroutonRecipeParserTests \
  -only-testing:RecipeScalerNativeTests/ThirdPartyIngredientAmountSplitterTests \
  -only-testing:RecipeScalerNativeTests/ThirdPartyFormatDetectorTests \
  -only-testing:RecipeScalerNativeTests/DescriptionXmlFragmentWriterTests \
  -only-testing:RecipeScalerNativeTests/ThirdPartyImportIntegrationTests

echo "==> OK: third-party import tests passed"
