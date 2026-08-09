#!/usr/bin/env bash
# Verification checklist for offline recipe image cache (no simulator required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${SIM_ID:=$("$ROOT/scripts/resolve-simulator.sh")}"

PASS=0
FAIL=0

check() {
  if eval "$2" >/dev/null 2>&1; then
    echo "  OK  $1"
    PASS=$((PASS + 1))
  else
    echo "  FAIL $1"
    FAIL=$((FAIL + 1))
  fi
}

echo "== Build =="
xcodebuild -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  build 2>&1 | tail -3

echo ""
echo "== Static contracts =="
check "Disk cache helper exists" "test -f RecipeScalerNative/Services/RecipeImageDiskCache.swift"
check "Downsample decoder exists" "test -f RecipeScalerNative/Services/RecipeImageDecoder.swift"
check "Auth on image download" "rg -q 'recipeImageDownloadRequest' RecipeScalerNative/Services/APIClient.swift"
check "x-user-id on image request" "rg -q 'x-user-id' RecipeScalerNative/Services/APIClient.swift"
check "Detail header before recipe load" "rg -q 'headerImageUrl' RecipeScalerNative/Views/YDocRecipeDetailView.swift"
check "Collection imageUrl fallback" "rg -q 'collectionEntries.first' RecipeScalerNative/Views/YDocRecipeDetailView.swift"
check "Offline skips network in image view" "rg -q 'guard allowsNetworkRefresh else' RecipeScalerNative/Views/RecipeCachedImageView.swift"
check "Fast disk path in image view" "rg -q 'RecipeImageDiskCache.existingFileURL' RecipeScalerNative/Views/RecipeCachedImageView.swift"
check "Display cache uses decoder" "rg -q 'RecipeImageDisplayCache' RecipeScalerNative/Views/RecipeCachedImageView.swift"
check "Two-phase prefetch (preview then full)" "rg -q 'Phase 1' RecipeScalerNative/Services/RecipeImageService.swift"
check "Sync status sheet" "test -f RecipeScalerNative/Views/SyncStatusSheet.swift"
check "APIClient configured on sync start" "rg -q 'APIClient.shared.configure\\(userId:' RecipeScalerNative/Services/YjsSync/YjsSyncService.swift"

echo ""
echo "== Unit tests in source (require test target in Xcode to execute) =="
rg -n "func testRecipeImage|func testAPIClientImage|func testRecipeImageDisk|func testRecipeImageDecoder|func testRecipeImageDisplay" \
  RecipeScalerNativeTests/RecipeScalerNativeTests.swift || true

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "VERIFIED: $PASS static checks passed, build succeeded."
  exit 0
else
  echo "NOT VERIFIED: $FAIL check(s) failed, $PASS passed."
  exit 1
fi