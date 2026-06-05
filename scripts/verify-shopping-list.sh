#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/024-shopping-list-completion/screenshots"

rg -q 'shopping_list_updated|shoppingList' RecipeScalerNative/Services/YjsSync/SyncEventHandler.swift
rg -q 'shoppingShareButton|clearPurchasedShoppingItems' \
  RecipeScalerNative/Views/ShoppingListView.swift \
  RecipeScalerNative/Services/YjsSync/DocumentManager+ShoppingList.swift

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1 -OpenTab=shopping

sim_wait_ready 8
SHOT="$(sim_screenshot "$SHOT_DIR" "shopping")"
echo "Screenshot: $SHOT"
echo "VERIFIED shopping-list"