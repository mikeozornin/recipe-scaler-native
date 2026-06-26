#!/usr/bin/env bash
# Remove stale EagerLinking TBD stubs that break RecipeScalerNativeWatch link
# (missing x86_64 / arm64 in RecipeScalerCore.tbd).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/sim-verify-lib.sh
source "$ROOT/scripts/sim-verify-lib.sh"
xcode_clean_watch_tbd_stubs
echo "Done."
