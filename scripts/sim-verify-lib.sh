#!/usr/bin/env bash
# Shared helpers for iOS Simulator verification scripts.
# Source: source "$(dirname "$0")/sim-verify-lib.sh"

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${SIM_ID:=EFC65E55-4F28-4C21-B489-D9733D2BE6B5}"

BUNDLE_ID="ru.recipescaler.RecipeScalerNative"
VERIFY_BUILD_STAMP="${VERIFY_BUILD_STAMP:-$ROOT/.verify-build-stamp}"

# Stale EagerLinking TBD stubs for watchsimulator omit x86_64 (or arm64) and break
# RecipeScalerNativeWatch link when building the iPhone scheme. Safe to delete — Xcode
# regenerates on the next build. See verify-watch-timers.sh / AGENT-WORKFLOW.md.
xcode_clean_watch_tbd_stubs() {
  local count=0
  while IFS= read -r -d '' stub_dir; do
    rm -rf "$stub_dir"
    count=$((count + 1))
  done < <(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/EagerLinkingTBDs/Debug-watchsimulator' -type d -print0 2>/dev/null || true)
  if (( count > 0 )); then
    echo "== Cleared stale watchsimulator EagerLinking TBD stubs ($count) =="
  fi
}

sim_build() {
  sim_ensure_built "$@"
}

# Idempotent Debug build. Skips when:
# - VERIFY_SKIP_BUILD=1 and the app bundle already exists, or
# - the stamp file is newer than any Swift source under RecipeScalerNative/.
sim_ensure_built() {
  if [[ "${VERIFY_SKIP_BUILD:-0}" == "1" ]]; then
    if sim_resolve_app 2>/dev/null; then
      echo "== Build Debug (skipped — VERIFY_SKIP_BUILD=1) =="
      return 0
    fi
  fi

  local newest_source
  newest_source="$(find "$ROOT/RecipeScalerNative" "$ROOT/RecipeScalerCore" "$ROOT/RecipeScalerNativeWatch" \
    -name '*.swift' -print0 2>/dev/null \
    | xargs -0 stat -f '%m %N' 2>/dev/null \
    | sort -rn | head -1 | cut -d' ' -f1 || echo 0)"
  local stamp_mtime=0
  if [[ -f "$VERIFY_BUILD_STAMP" ]]; then
    stamp_mtime="$(stat -f '%m' "$VERIFY_BUILD_STAMP" 2>/dev/null || echo 0)"
  fi

  if sim_resolve_app 2>/dev/null \
    && [[ "$stamp_mtime" -ge "$newest_source" ]]; then
    echo "== Build Debug (skipped — app up to date) =="
    return 0
  fi

  echo "== Build Debug =="
  xcode_clean_watch_tbd_stubs
  xcodebuild -scheme RecipeScalerNative \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -configuration Debug \
    build "$@"
  touch "$VERIFY_BUILD_STAMP"
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
  local container
  container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" ]]; then
    rm -f \
      "$container/Library/Application Support/debug-session.ndjson" \
      "$container/Library/Application Support/debug-session.ndjson."{1,2,3} \
      "$container/Library/Caches/debug-session.ndjson" \
      "$container/Library/Caches/$BUNDLE_ID/debug-session.ndjson" 2>/dev/null || true
  fi
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

# Wait until the app emits a readiness marker in the debug log, or fall back to sleep.
# Markers (any match): app_shell_start, container_constructed, contentview_init
sim_wait_ready() {
  local timeout_seconds="${1:-12}"
  local log="${LOG_FILE:-$ROOT/.debug-session.ndjson}"
  local deadline=$((SECONDS + timeout_seconds))
  local markers='app_shell_start|container_constructed|contentview_init'

  while (( SECONDS < deadline )); do
    sim_pull_debug_log 2>/dev/null || true
    if [[ -f "$log" ]] && grep -qE "$markers" "$log" 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done

  sim_pull_debug_log || true
  return 0
}
