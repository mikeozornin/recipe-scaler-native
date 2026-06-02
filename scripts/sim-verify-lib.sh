#!/usr/bin/env bash
# Shared helpers for iOS Simulator verification scripts.
# Source: source "$(dirname "$0")/sim-verify-lib.sh"

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${SIM_ID:=C3ED7448-2C55-4F02-B5DA-721E2853FD0B}"

BUNDLE_ID="ru.recipescaler.RecipeScalerNative"

sim_build() {
  echo "== Build Debug =="
  xcodebuild -scheme RecipeScalerNative \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -configuration Debug \
    build "$@"
}

sim_resolve_app() {
  if [[ -n "${APP:-}" && -d "$APP" ]]; then
    return 0
  fi
  local settings
  settings="$(xcodebuild -scheme RecipeScalerNative \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -configuration Debug \
    -showBuildSettings 2>/dev/null)"
  local products
  products="$(echo "$settings" | awk -F ' = ' '/TARGET_BUILD_DIR/ {print $2; exit}')"
  local name
  name="$(echo "$settings" | awk -F ' = ' '/FULL_PRODUCT_NAME/ {print $2; exit}')"
  if [[ -n "$products" && -n "$name" ]]; then
    APP="$products/$name"
  fi
  if [[ ! -d "${APP:-}" ]]; then
    APP="${DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/RecipeScalerNative-diymkplxrwchdvgvqkoehouiygur}/Build/Products/Debug-iphonesimulator/RecipeScalerNative.app"
  fi
  if [[ ! -d "$APP" ]]; then
    echo "App bundle not found (set APP or DERIVED)" >&2
    return 1
  fi
}

sim_prepare() {
  xcrun simctl boot "$SIM_ID" 2>/dev/null || true
  xcrun simctl privacy "$SIM_ID" grant notifications "$BUNDLE_ID" 2>/dev/null || true
}

sim_install() {
  sim_resolve_app || return 1
  xcrun simctl install "$SIM_ID" "$APP"
}

sim_terminate() {
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
}

sim_launch() {
  sim_terminate
  local log="${LOG_FILE:-$ROOT/.debug-session.ndjson}"
  rm -f "$log"
  # App sandbox cannot write to host paths; logs live under Library/Caches (see AgentSyncDebugLog).
  unset AGENT_DEBUG_LOG
  unset SIMCTL_CHILD_AGENT_DEBUG_LOG
  xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" "$@"
}

sim_pull_debug_log() {
  local dest="${LOG_FILE:-$ROOT/.debug-session.ndjson}"
  local container
  container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -z "$container" ]]; then
    return 1
  fi
  local candidates=(
    "$container/Library/Application Support/debug-session.ndjson"
    "$container/Library/Caches/debug-session.ndjson"
    "$container/Library/Caches/$BUNDLE_ID/debug-session.ndjson"
  )
  while IFS= read -r -d '' found; do
    candidates+=("$found")
  done < <(find "$container/Library/Caches" -name 'debug-session.ndjson' -print0 2>/dev/null || true)
  local src=""
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      src="$c"
      break
    fi
  done
  if [[ -n "$src" ]]; then
    cp "$src" "$dest"
    return 0
  fi
  return 1
}

sim_screenshot() {
  local dir="$1"
  local prefix="$2"
  mkdir -p "$dir"
  local shot="$dir/${prefix}-$(date +%Y%m%d-%H%M%S).png"
  xcrun simctl io "$SIM_ID" screenshot "$shot"
  echo "$shot"
}

sim_wait_ready() {
  local seconds="${1:-12}"
  sleep "$seconds"
  sim_pull_debug_log || true
}