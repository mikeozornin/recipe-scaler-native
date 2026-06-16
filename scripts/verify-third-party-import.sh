#!/usr/bin/env bash
# Verify script for spec 027 (Paprika / Crouton import).
# Builds the app and runs the ThirdParty* XCTest suite.
set -euo pipefail

cd "$(dirname "$0")/.."

DEST_ID="${XCODE_DEST_ID:-C3ED7448-2C55-4F02-B5DA-721E2853FD0B}"

echo "==> Building RecipeScalerNative (Debug)"
rtk xcodebuild \
  -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=${DEST_ID}" \
  build-for-testing

echo "==> Running ThirdParty* test suites"
rtk proxy xcodebuild \
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
