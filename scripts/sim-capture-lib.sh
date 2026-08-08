#!/usr/bin/env bash
# Shared simulator capture helpers for App Store and Feature Adoption media.
#
# Source:
#   source "$ROOT/scripts/sim-capture-lib.sh"

set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/sim-verify-lib.sh"

: "${CAPTURE_STATUS_TIME:=9:41}"
: "${CAPTURE_SHOT_WAIT:=4}"

capture_resolve_sim() {
  local json name udid
  json="$(xcrun simctl list devices available -j)"
  for name in "iPhone Air" "iPhone 17 Pro Max" "iPhone 16 Pro Max"; do
    udid="$(python3 - "$json" "$name" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
want = sys.argv[2]
for devices in data.get("devices", {}).values():
    for device in devices:
        if device.get("name") == want and device.get("isAvailable", True):
            print(device["udid"])
            raise SystemExit
PY
)"
    if [[ -n "$udid" ]]; then
      SIM_ID="$udid"
      export SIM_ID
      echo "== Simulator: $name ($SIM_ID) =="
      return 0
    fi
  done

  echo "ERROR: no supported iPhone simulator found" >&2
  return 1
}

capture_override_status_bar() {
  xcrun simctl status_bar "$SIM_ID" clear >/dev/null 2>&1 || true
  xcrun simctl status_bar "$SIM_ID" override \
    --time "$CAPTURE_STATUS_TIME" \
    --dataNetwork wifi \
    --wifiMode active \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4 \
    --batteryState charged \
    --batteryLevel 100 \
    --operatorName '' >/dev/null
}

capture_set_os_locale() {
  local language="$1"
  local apple_locale="ru_RU"
  if [[ "$language" == "en" ]]; then
    apple_locale="en_US"
  fi

  python3 - "$SIM_ID" "$language" "$apple_locale" <<'PY'
import plistlib
import sys
from pathlib import Path

sim_id, language, apple_locale = sys.argv[1:]
path = (
    Path.home()
    / "Library/Developer/CoreSimulator/Devices"
    / sim_id
    / "data/Library/Preferences/.GlobalPreferences.plist"
)
data = plistlib.loads(path.read_bytes()) if path.is_file() else {}
data["AppleLanguages"] = [language]
data["AppleLocale"] = apple_locale
data["AKLastLocale"] = apple_locale
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
PY

  xcrun simctl spawn "$SIM_ID" defaults write -g AppleLanguages -array "$language" >/dev/null
  xcrun simctl spawn "$SIM_ID" defaults write -g AppleLocale -string "$apple_locale" >/dev/null
  xcrun simctl spawn "$SIM_ID" killall -9 SpringBoard >/dev/null 2>&1 || true
  sleep 3
  capture_override_status_bar
}

capture_set_appearance() {
  xcrun simctl ui "$SIM_ID" appearance "$1" >/dev/null
}

capture_launch() {
  local scene_id="$1"
  local language="$2"
  local appearance="$3"
  local sequence="${4:-}"
  shift 4 || true

  export SIMCTL_CHILD_AGENT_DEBUG_LOG_DISABLED=1
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  local args=(
    -SkipSplash=1
    -ScreenshotCapture=1
    "-AppLanguage=$language"
    "-AppTheme=$appearance"
    "-OpenGuideMediaScene=$scene_id"
  )
  if [[ -n "$sequence" ]]; then
    args+=("-GuideMediaSequence=$sequence")
  fi
  if [[ "$scene_id" == sent_assistant_message.* ]]; then
    args+=("-ScreenshotAssistantFixture=1")
  fi
  args+=("$@")
  xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" "${args[@]}"
  sleep "${CAPTURE_SHOT_WAIT}"
  capture_override_status_bar
}

capture_png() {
  local output="$1"
  mkdir -p "$(dirname "$output")"
  xcrun simctl io "$SIM_ID" screenshot "$output"
}

capture_video() {
  local output="$1"
  local duration="$2"
  mkdir -p "$(dirname "$output")"

  rm -f "$output"
  xcrun simctl io "$SIM_ID" recordVideo \
    --codec=h264 \
    --force \
    "$output" &
  local recorder_pid=$!
  sleep "$duration"
  kill -INT "$recorder_pid" >/dev/null 2>&1 || true
  wait "$recorder_pid" >/dev/null 2>&1 || true
}

capture_validate_png_dimensions() {
  local path="$1"
  python3 - "$path" <<'PY'
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit(f"not a PNG: {path}")
size = struct.unpack(">II", data[16:24])
accepted = {(1260, 2736), (1320, 2868), (1290, 2796)}
if size not in accepted:
    raise SystemExit(f"unexpected PNG size {size[0]}x{size[1]}: {path}")
print(f"{path}: {size[0]}x{size[1]}")
PY
}
