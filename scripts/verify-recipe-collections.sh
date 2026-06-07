#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/026-recipe-collections/screenshots"
mkdir -p "$SHOT_DIR"

test -f "$ROOT/specs/026-recipe-collections/spec.md"
test -f "$ROOT/specs/026-recipe-collections/contracts/collection-folders-yjs.md"

# Swift symbols from steps §1–§5 (foundation/UI worker lands them in parallel).
# Re-enable once YjsSyncService folders API and view files exist:
# rg -q 'readFolders|createFolder|renameFolder|deleteFolder|setRecipeFolders' \
#   RecipeScalerNative/Services/YjsSync/DocumentManager.swift
# rg -q 'CollectionsRootView|CollectionFolderView|CollectionAssignSheet|ManageCollectionRecipesSheet' \
#   RecipeScalerNative/Views/

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1

sim_wait_ready 6
SHOT="$(sim_screenshot "$SHOT_DIR" "recipe-collections")"
echo "Screenshot: $SHOT"
echo "VERIFIED recipe-collections"
