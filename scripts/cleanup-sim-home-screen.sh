#!/usr/bin/env bash
# Remove leftover SpringBoard icons that are not the real Recipe Scaler app:
# - old app bundle id (pre-rename)
# - XCUITest runner apps left after `xcodebuild test`
#
# Usage:
#   bash scripts/cleanup-sim-home-screen.sh              # all booted sims
#   bash scripts/cleanup-sim-home-screen.sh <udid|name>  # one device
set -euo pipefail

JUNK_BUNDLE_IDS=(
  # Legacy main app (renamed to ru.recipescaler.RecipeScaler)
  ru.recipescaler.RecipeScalerNative
  # UI test runners (current + legacy product bundle ids)
  ru.recipescaler.RecipeScalerUITests.xctrunner
  ru.recipescaler.RecipeScalerNativeUITests.xctrunner
)

resolve_targets() {
  if [[ $# -ge 1 && -n "${1:-}" ]]; then
    printf '%s\n' "$1"
    return
  fi
  xcrun simctl list devices booted -j \
    | python3 -c 'import json,sys; d=json.load(sys.stdin);
devs=d.get("devices",{})
for runtime, items in devs.items():
  for item in items:
    if item.get("state")=="Booted":
      print(item["udid"])'
}

uninstall_on() {
  local target=$1
  local bid
  for bid in "${JUNK_BUNDLE_IDS[@]}"; do
    if xcrun simctl uninstall "$target" "$bid" >/dev/null 2>&1; then
      echo "uninstalled $bid from $target"
    fi
  done
}

targets="$(resolve_targets "${1:-}")"
if [[ -z "$targets" ]]; then
  echo "No booted simulator (and no device argument). Nothing to clean."
  exit 0
fi

while IFS= read -r target; do
  [[ -z "$target" ]] && continue
  uninstall_on "$target"
done <<< "$targets"
