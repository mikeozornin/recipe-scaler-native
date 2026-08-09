#!/usr/bin/env bash
# Shared helpers for iOS Simulator verification scripts.
# Source: source "$(dirname "$0")/sim-verify-lib.sh"

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${SIM_ID:=$("$ROOT/scripts/resolve-simulator.sh")}"

BUNDLE_ID="ru.recipescaler.RecipeScaler"
VERIFY_BUILD_MANIFEST="${VERIFY_BUILD_MANIFEST:-$ROOT/.verify-build-manifest.json}"

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

# Build Debug and record the inputs that produced the app bundle.
#
# Xcode already performs incremental compilation. The old external stamp was
# unsafe because it only compared Swift source mtimes and could reuse an app
# after project, resource, package, or entitlement changes. Reuse is now
# opt-in and requires a matching build manifest.
sim_ensure_built() {
  if [[ "${VERIFY_SKIP_BUILD:-0}" == "1" ]] && sim_build_manifest_matches; then
    echo "== Build Debug (skipped — matching build manifest) =="
    return 0
  fi

  echo "== Build Debug =="
  xcode_clean_watch_tbd_stubs
  xcodebuild -scheme RecipeScalerNative \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -configuration Debug \
    build "$@"
  sim_write_build_manifest
}

sim_build_inputs() {
  local -a paths=(
    "$ROOT/RecipeScalerNative"
    "$ROOT/RecipeScalerCore"
    "$ROOT/RecipeScalerNativeWatch"
    "$ROOT/HomeWidgetExtension"
    "$ROOT/ShareExtensionUI"
    "$ROOT/ActionExtension"
    "$ROOT/RecipeScalerNative.xcodeproj/project.pbxproj"
    "$ROOT/RecipeScalerNative.xcodeproj/xcshareddata"
    "$ROOT/Package.swift"
    "$ROOT/Package.resolved"
  )
  printf '%s\0' "${paths[@]}" | while IFS= read -r -d '' path; do
    [[ -e "$path" ]] && printf '%s\0' "$path"
  done
}

sim_build_fingerprint() {
  python3 - "$ROOT" "$SIM_ID" <<'PY'
import hashlib
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
simulator_id = sys.argv[2]
paths = [
    root / "RecipeScalerNative",
    root / "RecipeScalerCore",
    root / "RecipeScalerNativeWatch",
    root / "HomeWidgetExtension",
    root / "ShareExtensionUI",
    root / "ActionExtension",
    root / "RecipeScalerNative.xcodeproj" / "project.pbxproj",
    root / "RecipeScalerNative.xcodeproj" / "xcshareddata",
    root / "Package.swift",
    root / "Package.resolved",
]

files: list[Path] = []
for path in paths:
    if path.is_file():
        files.append(path)
    elif path.is_dir():
        files.extend(
            candidate
            for candidate in path.rglob("*")
            if candidate.is_file()
            and "DerivedData" not in candidate.parts
            and ".git" not in candidate.parts
        )

digest = hashlib.sha256()
for path in sorted(set(files)):
    digest.update(str(path.relative_to(root)).encode())
    digest.update(b"\0")
    try:
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    except OSError:
        digest.update(b"<unreadable>")

for command in (["xcodebuild", "-version"], ["xcrun", "simctl", "list", "runtimes"]):
    try:
        output = subprocess.check_output(command, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError):
        output = b""
    digest.update(b"\0")
    digest.update(output)

digest.update(f"scheme=RecipeScalerNative\nconfiguration=Debug\ndestination={simulator_id}\n".encode())
print(digest.hexdigest())
PY
}

sim_write_build_manifest() {
  sim_resolve_app || return 1
  local fingerprint
  fingerprint="$(sim_build_fingerprint)"
  local app_path="$APP"
  python3 - "$VERIFY_BUILD_MANIFEST" "$fingerprint" "$SIM_ID" "$app_path" <<'PY'
import json
import sys
from pathlib import Path

manifest_path, fingerprint, simulator_id, app_path = sys.argv[1:]
payload = {
    "fingerprint": fingerprint,
    "simulatorId": simulator_id,
    "scheme": "RecipeScalerNative",
    "configuration": "Debug",
    "appPath": app_path,
}
Path(manifest_path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

sim_build_manifest_matches() {
  [[ -f "$VERIFY_BUILD_MANIFEST" ]] || return 1
  sim_resolve_app >/dev/null 2>&1 || return 1
  local expected
  expected="$(sim_build_fingerprint)"
  python3 - "$VERIFY_BUILD_MANIFEST" "$expected" "$SIM_ID" "$APP" <<'PY'
import json
import sys
from pathlib import Path

path, expected, simulator_id, app_path = sys.argv[1:]
try:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
if data.get("fingerprint") != expected:
    raise SystemExit(1)
if data.get("simulatorId") != simulator_id:
    raise SystemExit(1)
if data.get("appPath") != app_path or not Path(app_path).is_dir():
    raise SystemExit(1)
PY
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
  if [[ ! -d "${APP:-}" && -n "${DERIVED:-}" ]]; then
    APP="$DERIVED/Build/Products/Debug-iphonesimulator/RecipeScalerNative.app"
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

# Drop XCUITest runners / legacy app ids left on SpringBoard after UI tests.
sim_cleanup_home_screen() {
  bash "$ROOT/scripts/cleanup-sim-home-screen.sh" "$SIM_ID" || true
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

# Wait until the current launch emits a readiness marker in the debug log.
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
  echo "Timed out waiting for app readiness marker after ${timeout_seconds}s" >&2
  return 1
}
