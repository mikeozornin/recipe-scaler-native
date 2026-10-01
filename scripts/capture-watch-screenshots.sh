#!/usr/bin/env bash
# Capture App Store screenshots of the watch companion.
#
# Two frames: three running timers, and the empty list.
# Canvas is Apple Watch Ultra 3 (422×514). App Store Connect accepts one
# watch size for every localization, and Ultra 3 is the current top class
# this app can run on (watchOS 10+).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_ROOT="$ROOT/store/screenshots/watch"
DERIVED="$ROOT/.build/watch-screenshots"
BUNDLE_ID="ru.recipescaler.RecipeScaler.watchkitapp"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-3-49mm"
SIM_NAME="Apple Watch Ultra 3 (49mm)"
ACCEPTED_W=422
ACCEPTED_H=514
STATUS_TIME="9:41"
SHOT_WAIT_SECONDS="${CAPTURE_SHOT_WAIT:-3}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --locale ru|en          repeatable; default ru and en
  --appearance light|dark repeatable; default light
  --shot timers|empty|01|02   repeatable; default both
  --skip-build

Writes store/screenshots/watch/{locale}/{appearance}/01-timers.png
and 02-empty.png. PNGs are gitignored.
EOF
}

LOCALES=()
APPEARANCES=()
SHOTS=()
SKIP_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --locale) LOCALES+=("$2"); shift 2 ;;
    --appearance) APPEARANCES+=("$2"); shift 2 ;;
    --shot) SHOTS+=("$2"); shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done
[[ ${#LOCALES[@]} -eq 0 ]] && LOCALES=(ru en)
[[ ${#APPEARANCES[@]} -eq 0 ]] && APPEARANCES=(light)
[[ ${#SHOTS[@]} -eq 0 ]] && SHOTS=(timers empty)

shot_slug() {
  case "$1" in
    01|timers|01-timers) echo "timers" ;;
    02|empty|02-empty) echo "empty" ;;
    *) echo "Unknown shot: $1" >&2; exit 1 ;;
  esac
}

normalize_shots() {
  local raw slug
  NORMALIZED_SHOTS=()
  for raw in "${SHOTS[@]}"; do
    slug="$(shot_slug "$raw")"
    NORMALIZED_SHOTS+=("$slug")
  done
}
normalize_shots

resolve_runtime() {
  python3 - <<'PY'
import json, subprocess, sys
raw = subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"], text=True)
runtimes = json.loads(raw).get("runtimes", [])
watch = [
    r for r in runtimes
    if r.get("isAvailable") and "watchOS" in (r.get("name") or "")
]
if not watch:
    sys.exit("No available watchOS simulator runtime. Install one in Xcode → Settings → Platforms.")
watch.sort(key=lambda r: r.get("version", ""))
print(watch[-1]["identifier"])
PY
}

resolve_watch_sim() {
  local runtime="$1"
  python3 - "$runtime" "$DEVICE_TYPE" "$SIM_NAME" <<'PY'
import json, subprocess, sys
runtime, device_type, name = sys.argv[1:]
raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"], text=True)
devices = json.loads(raw).get("devices", {}).get(runtime, [])
for device in devices:
    if device.get("name") == name and device.get("isAvailable", True):
        print(device["udid"])
        raise SystemExit
PY
}

create_watch_sim() {
  local runtime="$1"
  xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$runtime"
}

set_os_locale() {
  local udid="$1"
  local language="$2"
  local apple_locale="ru_RU"
  [[ "$language" == "en" ]] && apple_locale="en_US"
  python3 - "$udid" "$language" "$apple_locale" <<'PY'
import plistlib, sys
from pathlib import Path
udid, language, apple_locale = sys.argv[1:]
path = (
    Path.home()
    / "Library/Developer/CoreSimulator/Devices"
    / udid
    / "data/Library/Preferences/.GlobalPreferences.plist"
)
data = plistlib.loads(path.read_bytes()) if path.is_file() else {}
data["AppleLanguages"] = [language]
data["AppleLocale"] = apple_locale
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
PY
  xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$language" >/dev/null
  xcrun simctl spawn "$udid" defaults write -g AppleLocale -string "$apple_locale" >/dev/null
}

boot_watch() {
  local udid="$1"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
}

prepare_chrome() {
  local udid="$1"
  local appearance="$2"
  # watchOS 26 simulator rejects `simctl ui appearance` (userInterfaceStyle).
  if [[ "$appearance" == "dark" ]]; then
    xcrun simctl spawn "$udid" defaults write -g AppleInterfaceStyle -string Dark >/dev/null
  else
    xcrun simctl spawn "$udid" defaults delete -g AppleInterfaceStyle >/dev/null 2>&1 || true
  fi
  xcrun simctl status_bar "$udid" override \
    --time "$STATUS_TIME" \
    --batteryState charged \
    --batteryLevel 100 >/dev/null 2>&1 || true
}

build_watch() {
  local udid="$1"
  echo "== Build RecipeScalerNativeWatch =="
  xcodebuild \
    -scheme RecipeScalerNativeWatch \
    -destination "platform=watchOS Simulator,id=$udid" \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    -quiet \
    build
}

app_path() {
  echo "$DERIVED/Build/Products/Debug-watchsimulator/RecipeScalerNativeWatch.app"
}

launch_shot() {
  local udid="$1"
  local language="$2"
  local slug="$3"
  local apple_locale="ru_RU"
  [[ "$language" == "en" ]] && apple_locale="en_US"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" \
    -ScreenshotCapture=1 \
    -WatchScreenshot="$slug" \
    -AppLanguage="$language" \
    -AppleLanguages "($language)" \
    -AppleLocale "$apple_locale" >/dev/null
  sleep "$SHOT_WAIT_SECONDS"
}

# simctl writes RGBA (rounded-corner alpha). ASC wants 24-bit PNG.
# watchOS simulator also ignores status-bar overrides, so the corner clock
# is painted to 9:41 to match the iPhone shots.
polish_png() {
  python3 - "$1" "$STATUS_TIME" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

path = Path(sys.argv[1])
clock = sys.argv[2]
image = Image.open(path).convert("RGBA")
flat = Image.new("RGB", image.size, (0, 0, 0))
flat.paste(image, mask=image.getchannel("A"))

pixels = flat.load()
width, height = flat.size
xs = []
ys = []
for y in range(0, 90):
    for x in range(width):
        r, g, b = pixels[x, y]
        if r > 180 and g > 180 and b > 180:
            xs.append(x)
            ys.append(y)
if xs:
    pad = 3
    box = (
        max(0, min(xs) - pad),
        max(0, min(ys) - pad),
        min(width, max(xs) + pad + 1),
        min(height, max(ys) + pad + 1),
    )
    draw = ImageDraw.Draw(flat)
    draw.rectangle(box, fill=(0, 0, 0))
    target_h = max(ys) - min(ys)
    font_path = "/System/Library/Fonts/SFCompact.ttf"
    size = 18
    font = ImageFont.truetype(font_path, size)
    for candidate in range(14, 28):
        trial = ImageFont.truetype(font_path, candidate)
        bbox = trial.getbbox(clock)
        if bbox and (bbox[3] - bbox[1]) <= target_h + 2:
            size = candidate
            font = trial
    text_box = font.getbbox(clock)
    text_w = text_box[2] - text_box[0]
    text_h = text_box[3] - text_box[1]
    right = max(xs)
    top = min(ys) - text_box[1]
    draw.text((right - text_w, top), clock, font=font, fill=(255, 255, 255))

flat.save(path, format="PNG")
PY
}

validate_png() {
  local path="$1"
  python3 - "$path" "$ACCEPTED_W" "$ACCEPTED_H" <<'PY'
import struct, sys
from pathlib import Path
path, want_w, want_h = Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
data = path.read_bytes()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit(f"not a PNG: {path}")
color_type = data[25]
if color_type in (4, 6):
    raise SystemExit(f"PNG has alpha: {path}")
width, height = struct.unpack(">II", data[16:24])
if (width, height) != (want_w, want_h):
    raise SystemExit(f"unexpected PNG size {width}x{height} (want {want_w}x{want_h}): {path}")
print(f"{path.name}: {width}x{height}")
PY
}

RUNTIME="$(resolve_runtime)"
echo "== watchOS runtime: $RUNTIME =="
WATCH_UDID="$(resolve_watch_sim "$RUNTIME" || true)"
if [[ -z "${WATCH_UDID}" ]]; then
  echo "== Create $SIM_NAME =="
  WATCH_UDID="$(create_watch_sim "$RUNTIME")"
fi
echo "== Watch simulator: $SIM_NAME ($WATCH_UDID) =="

if [[ "$SKIP_BUILD" != "1" ]]; then
  # Destination must exist and be bootable before xcodebuild resolves it.
  boot_watch "$WATCH_UDID"
  build_watch "$WATCH_UDID"
fi
APP="$(app_path)"
if [[ ! -d "$APP" ]]; then
  echo "Watch app not found at $APP — run without --skip-build" >&2
  exit 1
fi

for language in "${LOCALES[@]}"; do
  echo "== Locale $language =="
  boot_watch "$WATCH_UDID"
  set_os_locale "$WATCH_UDID" "$language"
  xcrun simctl shutdown "$WATCH_UDID" >/dev/null 2>&1 || true
  boot_watch "$WATCH_UDID"
  xcrun simctl install "$WATCH_UDID" "$APP"
  for appearance in "${APPEARANCES[@]}"; do
    echo "== Appearance $appearance =="
    prepare_chrome "$WATCH_UDID" "$appearance"
    for slug in "${NORMALIZED_SHOTS[@]}"; do
      case "$slug" in
        timers) file="01-timers.png" ;;
        empty) file="02-empty.png" ;;
      esac
      out="$OUT_ROOT/$language/$appearance/$file"
      echo "  $language/$appearance/$file"
      launch_shot "$WATCH_UDID" "$language" "$slug"
      mkdir -p "$(dirname "$out")"
      xcrun simctl io "$WATCH_UDID" screenshot "$out"
      polish_png "$out"
      validate_png "$out"
    done
  done
done

echo "Watch screenshots written under $OUT_ROOT"
