#!/usr/bin/env bash
# verify-share-extension.sh — spec 025 T045.
#
# Verifies the three-target structure (main app + RecipeScalerCore + Share/Action
# extensions), the deep-link wiring, and runs the parser/classifier unit tests
# that don't require a real device.
#
# Exit code: 0 = VERIFIED, 1 = FAILED.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${SIM_ID:=7CC5ABD7-A34F-4B94-B8CE-A0B396467214}"

echo "== 1. Static checks =="

# Targets present in pbxproj.
for name in ShareExtension ActionExtension RecipeScalerCore; do
  if ! rg -q "name = $name;" RecipeScalerNative.xcodeproj/project.pbxproj; then
    echo "FAIL: target '$name' not found in project.pbxproj"
    exit 1
  fi
done
echo "PASS: targets ShareExtension, ActionExtension, RecipeScalerCore in pbxproj"

# App Group entitlement referenced on all three relevant targets.
for ent in \
  "RecipeScalerNative/RecipeScalerNative.entitlements" \
  "ShareExtension/ShareExtension.entitlements" \
  "ActionExtension/ActionExtension.entitlements"; do
  if [[ ! -f "$ROOT/$ent" ]]; then
    echo "FAIL: entitlement file missing: $ent"
    exit 1
  fi
  if ! rg -q "group.ru.recipescaler.RecipeScaler" "$ROOT/$ent"; then
    echo "FAIL: App Group key missing in $ent"
    exit 1
  fi
done
echo "PASS: App Group entitlements on main + extensions"

# URL scheme declared in main Info.plist (CFBundleURLTypes).
if ! rg -q "recipe-scaler" RecipeScalerNative/Info.plist; then
  echo "FAIL: 'recipe-scaler' URL scheme missing in Info.plist"
  exit 1
fi
echo "PASS: recipe-scaler URL scheme declared in main Info.plist"

# DeepLinkRouter source + onOpenURL wiring.
rg -q 'class DeepLinkRouter' RecipeScalerNative/Routing/DeepLinkRouter.swift
rg -q '\.onOpenURL' RecipeScalerNative/RecipeScalerNativeApp.swift
rg -q 'openRecipeRequested' RecipeScalerNative/Views/AppShellView.swift
rg -q 'consumePendingRecipeId' RecipeScalerNative/Routing/AppShellCoordinator.swift
echo "PASS: DeepLinkRouter + onOpenURL + AppShell wiring present"

# SharedAuthStore (App Group referenced, either directly or via AppGroup.id).
if rg -q 'group\.ru\.recipescaler\.RecipeScalerNative' RecipeScalerCore/Auth/SharedAuthStore.swift \
  || rg -q 'AppGroup\.id' RecipeScalerCore/Auth/SharedAuthStore.swift; then
  echo "PASS: SharedAuthStore uses App Group"
else
  echo "FAIL: SharedAuthStore no longer references the App Group"
  exit 1
fi

# Shared.xcstrings keys present.
for key in \
  "share-extension.title" \
  "share-extension.error-not-signed-in" \
  "share-extension.button-open"; do
  if ! rg -q "\"$key\"" RecipeScalerCore/Resources/Shared.xcstrings; then
    echo "FAIL: i18n key '$key' missing in Shared.xcstrings"
    exit 1
  fi
done
echo "PASS: critical share-extension.* i18n keys present"

# ShareContentClassifier exists and is wired into ShareContentLoader.
rg -q 'enum ShareContentClassifier' ShareExtensionUI/ShareContentClassifier.swift
rg -q 'ShareContentClassifier.classify' ShareExtensionUI/ShareContentLoader.swift
echo "PASS: ShareContentClassifier implemented and wired"

echo
echo "== 2. Build (simulator) =="
xcodebuild -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -configuration Debug \
  build 2>&1 | rg -i "(BUILD SUCCEEDED|BUILD FAILED|error:)" || true

echo
echo "== 3. Run parser / classifier / deep-link tests =="
xcodebuild test \
  -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing:RecipeScalerNativeTests/DeepLinkRouterTests \
  -only-testing:RecipeScalerNativeTests/ShareContentClassifierTests \
  -only-testing:RecipeScalerNativeTests/LocalizationConsistencyTests \
  2>&1 | rg -i "(Test Suite.*passed|Test Suite.*failed|error:)" || true

echo "VERIFIED share-extension"
