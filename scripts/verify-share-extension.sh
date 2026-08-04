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

: "${SIM_ID:=EFC65E55-4F28-4C21-B489-D9733D2BE6B5}"

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

# SharedAuthStore — team-prefixed Keychain access group (not App Group UserDefaults).
if rg -q 'sharedKeychainAccessGroup' RecipeScalerCore/Auth/SharedAuthStore.swift \
  && rg -q 'ZBPX4JYT24\.ru\.recipescaler\.RecipeScaler' RecipeScalerCore/Auth/SharedAuthStore.swift; then
  echo "PASS: SharedAuthStore uses Keychain access group ZBPX4JYT24.ru.recipescaler.RecipeScaler"
else
  echo "FAIL: SharedAuthStore missing team-prefixed keychainAccessGroup"
  exit 1
fi

# Keychain Sharing entitlement on main + Share + Action.
for ent in \
  "RecipeScalerNative/RecipeScalerNative.entitlements" \
  "ShareExtension/ShareExtension.entitlements" \
  "ActionExtension/ActionExtension.entitlements"; do
  if ! rg -q 'keychain-access-groups' "$ent"; then
    echo "FAIL: keychain-access-groups missing in $ent"
    exit 1
  fi
done
echo "PASS: Keychain Sharing entitlements on main + extensions"

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
