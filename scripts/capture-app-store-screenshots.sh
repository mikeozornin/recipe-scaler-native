#!/usr/bin/env bash
# Capture App Store screenshots: 8 shots × ru/en × light/dark on a 6.9″ simulator.
#
# Locale switch = E2E relogin only (no uninstall / no data wipe) so SpringBoard
# widget placement, app icon position, and push/LA TCC survive across ru↔en.
# OS locale (AppleLanguages / AppleLocale) is rewritten + SpringBoard bounced so
# lock-screen date and push relative time ("сейчас"/"now") match the shot locale.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

API_BASE="${E2E_API_BASE:-https://recipe-scaler.ru}"
OUT_ROOT="$ROOT/store/screenshots/iphone-6.9"
MANIFEST="$ROOT/store/screenshots/manifest.yaml"
STATUS_TIME="9:41"
# Keep these short — library is already on the store account; we only need UI settle.
SYNC_WAIT_SECONDS="${CAPTURE_SYNC_WAIT:-12}"
SHOT_WAIT_SECONDS="${CAPTURE_SHOT_WAIT:-5}"
# Push banner: short timer, Home, then wait for fire (do not use multi-minute polls).
PUSH_TIMER_SECONDS="${CAPTURE_PUSH_TIMER:-6}"
PUSH_BANNER_WAIT_SECONDS="${CAPTURE_PUSH_BANNER_WAIT:-5}"
CAPTURE_LOCK="$ROOT/.capture-screenshots.lock"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --locale ru|en
  --appearance light|dark
  --shot ID|slug|filename   e.g. 01, recipes, 01-recipes (repeatable)
  --skip-build
  --skip-sync               skip the locale relogin/sync launch (reuse current session)
  --validate-only
  --skip-validate           skip final matrix validation (useful for single-shot)

Captures raw 6.9″ PNGs into store/screenshots/iphone-6.9/{locale}/{appearance}/.
Uses persistent users from store/fixtures/users.yaml (not register-auto).
Does NOT uninstall between locales — only relaunches with E2E credentials.
Exclusive lock via `.capture-screenshots.lock.d` — do not run two captures in parallel.

Env overrides: CAPTURE_SYNC_WAIT (default 12), CAPTURE_SHOT_WAIT (default 5),
  CAPTURE_PUSH_TIMER (default 6), CAPTURE_PUSH_BANNER_WAIT (default 5).
EOF
}

LOCALES=(ru en)
APPEARANCES=(light dark)
# Empty = all shots. Populated via --shot.
SHOT_FILTER=()
SKIP_BUILD=0
SKIP_SYNC=0
VALIDATE_ONLY=0
SKIP_VALIDATE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --locale) LOCALES=("$2"); shift 2 ;;
    --appearance) APPEARANCES=("$2"); shift 2 ;;
    --shot) SHOT_FILTER+=("$2"); shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-sync) SKIP_SYNC=1; shift ;;
    --validate-only) VALIDATE_ONLY=1; shift ;;
    --skip-validate) SKIP_VALIDATE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$VALIDATE_ONLY" == "1" ]]; then
  exec bash "$ROOT/scripts/validate-app-store-screenshots.sh"
fi

# One capture process at a time (parallel runs fight over Home/Lock/timers).
# mkdir is atomic on macOS/Linux; no dependency on util-linux flock.
CAPTURE_LOCK_DIR="${CAPTURE_LOCK}.d"
acquire_capture_lock() {
  if mkdir "$CAPTURE_LOCK_DIR" 2>/dev/null; then
    echo "$$" >"$CAPTURE_LOCK_DIR/pid"
    trap 'rm -rf "$CAPTURE_LOCK_DIR"' EXIT INT TERM
    echo "  capture lock acquired (pid $$)"
    return 0
  fi
  local other=""
  other="$(cat "$CAPTURE_LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -n "$other" ]] && ! kill -0 "$other" 2>/dev/null; then
    echo "  clearing stale capture lock (dead pid $other)"
    rm -rf "$CAPTURE_LOCK_DIR"
    if mkdir "$CAPTURE_LOCK_DIR" 2>/dev/null; then
      echo "$$" >"$CAPTURE_LOCK_DIR/pid"
      trap 'rm -rf "$CAPTURE_LOCK_DIR"' EXIT INT TERM
      echo "  capture lock acquired (pid $$)"
      return 0
    fi
  fi
  echo "ERROR: another capture holds $CAPTURE_LOCK_DIR (pid ${other:-?}) — stop it first" >&2
  return 1
}
acquire_capture_lock || exit 1

# If capturing a subset, skip full-matrix validate by default.
if [[ ${#SHOT_FILTER[@]} -gt 0 ]]; then
  SKIP_VALIDATE=1
fi

ALL_SHOTS=(
  01-recipes
  02-cooking
  03-discover
  04-shopping
  05-assistant
  06-widget
  07-live-activity
  08-push
)

shot_wanted() {
  local name="$1"
  if [[ ${#SHOT_FILTER[@]} -eq 0 ]]; then
    return 0
  fi
  local f id slug
  id="${name%%-*}"
  slug="${name#*-}"
  for f in "${SHOT_FILTER[@]}"; do
    case "$f" in
      "$name"|"$id"|"$slug") return 0 ;;
    esac
  done
  return 1
}

any_shot_wanted() {
  local s
  for s in "$@"; do
    if shot_wanted "$s"; then
      return 0
    fi
  done
  return 1
}

resolve_sim() {
  local json name udid
  json="$(xcrun simctl list devices available -j)"
  for name in "iPhone Air" "iPhone 17 Pro Max" "iPhone 16 Pro Max"; do
    udid="$(python3 - "$json" "$name" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
want = sys.argv[2]
for runtime, devices in data.get("devices", {}).items():
    for dev in devices:
        if dev.get("name") == want and dev.get("isAvailable", True):
            print(dev["udid"])
            raise SystemExit
PY
)"
    if [[ -n "$udid" ]]; then
      SIM_ID="$udid"
      echo "== Simulator: $name ($SIM_ID) =="
      return 0
    fi
  done

  echo "== Creating iPhone Air simulator =="
  local runtime
  runtime="$(xcrun simctl list runtimes -j | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
runtimes = [r for r in data.get("runtimes", []) if r.get("platform") == "iOS" and r.get("isAvailable", True)]
runtimes.sort(key=lambda r: r.get("identifier", ""), reverse=True)
if not runtimes:
    raise SystemExit("no iOS simulator runtime")
print(runtimes[0]["identifier"])
PY
)"
  SIM_ID="$(xcrun simctl create "iPhone Air" "com.apple.CoreSimulator.SimDeviceType.iPhone-Air" "$runtime")"
  echo "== Simulator: iPhone Air ($SIM_ID, $runtime) =="
}

login_store_user() {
  python3 "$ROOT/scripts/store_users.py" login "$1"
}

override_status_bar() {
  # Plain "9:41" drives the in-app status bar. Lock Screen large clock on current
  # runtimes ignores overrides (wall clock) — known Simulator limitation.
  xcrun simctl status_bar "$SIM_ID" clear >/dev/null 2>&1 || true
  xcrun simctl status_bar "$SIM_ID" override \
    --time "$STATUS_TIME" \
    --dataNetwork wifi \
    --wifiMode active \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4 \
    --batteryState charged \
    --batteryLevel 100 \
    --operatorName '' >/dev/null
}

grant_capture_permissions() {
  # Notifications TCC — safe anytime.
  xcrun simctl privacy "$SIM_ID" grant notifications "$BUNDLE_ID" >/dev/null 2>&1 || true
  # liveactivitiesd owns this plist. Nested {Authorized,Enabled,...} records get
  # wiped; the granted shape observed on sim is bundleId -> true plus FirstResponse.
  # IMPORTANT: do not kill liveactivitiesd while a Live Activity is active — that
  # clears the in-memory grant and resurfaces the lock-screen "Allow?" chip.
  python3 - "$SIM_ID" "$BUNDLE_ID" <<'PY'
import plistlib, sys
from pathlib import Path

sim_id, bundle_id = sys.argv[1], sys.argv[2]
plist_path = (
    Path.home()
    / "Library/Developer/CoreSimulator/Devices"
    / sim_id
    / "data/Library/Preferences/com.apple.liveactivitiesd.plist"
)
data = {}
if plist_path.is_file():
    data = plistlib.loads(plist_path.read_bytes())

clients = list(dict.fromkeys((data.get("KnownClients") or []) + [bundle_id, "com.apple.springboard"]))
data["KnownClients"] = clients

records = dict(data.get("AppAuthorizationRecords") or {})
records[bundle_id] = True
data["AppAuthorizationRecords"] = records

first = list(data.get("FirstResponseRecords") or [])
if bundle_id not in first:
    first.append(bundle_id)
data["FirstResponseRecords"] = first

second = list(data.get("SecondResponseRecords") or [])
if bundle_id not in second:
    second.append(bundle_id)
data["SecondResponseRecords"] = second

plist_path.parent.mkdir(parents=True, exist_ok=True)
plist_path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
PY
}

# Cold grant: write plist then bounce the daemon once (session start only).
grant_capture_permissions_cold() {
  grant_capture_permissions
  xcrun simctl spawn "$SIM_ID" killall liveactivitiesd >/dev/null 2>&1 || true
  sleep 1
}

dismiss_notification_alert() {
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Simulator" to activate
delay 0.2
tell application "System Events"
  tell process "Simulator"
    set btnNames to {"Allow", "Разрешить", "Turn On", "Включить", "Enable", "OK", "ОК"}
    if exists sheet 1 of window 1 then
      repeat with btnName in btnNames
        if exists button btnName of sheet 1 of window 1 then
          click button btnName of sheet 1 of window 1
          return
        end if
      end repeat
    end if
    repeat with w in windows
      repeat with btnName in btnNames
        try
          if exists button btnName of w then
            click button btnName of w
            return
          end if
        end try
      end repeat
    end repeat
  end tell
end tell
APPLESCRIPT
}

set_flat_recipe_list() {
  xcrun simctl spawn "$SIM_ID" defaults write "$BUNDLE_ID" recipe-list-view-mode -string flat >/dev/null 2>&1 || true
}

# System locale for SpringBoard / Notification Center (push "now"/"сейчас",
# lock-screen date). App chrome still uses -AppLanguage= launch arg.
# Writing via defaults alone is ignored while SpringBoard caches the old locale —
# rewrite .GlobalPreferences.plist and bounce SpringBoard once per locale change.
set_os_locale() {
  local lang="$1"
  local apple_locale
  if [[ "$lang" == "en" ]]; then
    apple_locale="en_US"
  else
    apple_locale="ru_RU"
  fi
  echo "  OS locale → $lang ($apple_locale)"
  python3 - "$SIM_ID" "$lang" "$apple_locale" <<'PY'
import plistlib, sys
from pathlib import Path

sim_id, lang, apple_locale = sys.argv[1], sys.argv[2], sys.argv[3]
path = (
    Path.home()
    / "Library/Developer/CoreSimulator/Devices"
    / sim_id
    / "data/Library/Preferences/.GlobalPreferences.plist"
)
data = {}
if path.is_file():
    data = plistlib.loads(path.read_bytes())
data["AppleLanguages"] = [lang]
data["AppleLocale"] = apple_locale
data["AKLastLocale"] = apple_locale
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
PY
  # Also via defaults (some daemons read this path).
  xcrun simctl spawn "$SIM_ID" defaults write -g AppleLanguages -array "$lang" >/dev/null || true
  xcrun simctl spawn "$SIM_ID" defaults write -g AppleLocale -string "$apple_locale" >/dev/null || true
}

restart_springboard() {
  echo "  bouncing SpringBoard (apply OS locale)"
  xcrun simctl spawn "$SIM_ID" launchctl stop com.apple.SpringBoard >/dev/null 2>&1 || true
  xcrun simctl spawn "$SIM_ID" killall -9 SpringBoard >/dev/null 2>&1 || true
  # Short settle — do not poll for minutes.
  sleep 3
  override_status_bar
  # Re-seed LA TCC after SpringBoard/liveactivitiesd restart (no active LA yet).
  grant_capture_permissions_cold
}

set_languages() {
  local lang="$1"
  local prev="${PREV_OS_LANG:-}"
  local current=""
  current="$(python3 - "$SIM_ID" <<'PY'
import plistlib, sys
from pathlib import Path
path = (
    Path.home()
    / "Library/Developer/CoreSimulator/Devices"
    / sys.argv[1]
    / "data/Library/Preferences/.GlobalPreferences.plist"
)
try:
    data = plistlib.loads(path.read_bytes())
    langs = data.get("AppleLanguages") or []
    print(langs[0] if langs else "")
except Exception:
    print("")
PY
)"
  set_os_locale "$lang"
  if [[ "$prev" == "$lang" || "$current" == "$lang" ]]; then
    echo "  OS locale already $lang — skip SpringBoard bounce"
    PREV_OS_LANG="$lang"
    return 0
  fi
  restart_springboard
  PREV_OS_LANG="$lang"
}

set_appearance() {
  xcrun simctl ui "$SIM_ID" appearance "$1" >/dev/null
}

launch_capture() {
  local user_id="$1" token="$2" seed="$3"
  shift 3
  export SIMCTL_CHILD_E2E_OVERRIDE_USER_ID="$user_id"
  export SIMCTL_CHILD_E2E_OVERRIDE_DEVICE_TOKEN="$token"
  export SIMCTL_CHILD_E2E_OVERRIDE_SEED_PHRASE="$seed"
  export SIMCTL_CHILD_E2E_OVERRIDE_API_BASE="$API_BASE"
  export SIMCTL_CHILD_AGENT_DEBUG_LOG_DISABLED=1
  # Bring Simulator forward without sending the app to SpringBoard (no Cmd+Shift+H).
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Simulator" to activate
APPLESCRIPT
  sim_launch \
    -SkipSplash=1 \
    -ScreenshotCapture=1 \
    -DisableDebugAutoLogin=1 \
    "$@"
}

wait_ready() {
  sleep "${1:-4}"
}

assert_app_running() {
  local tries="${1:-8}"
  local i list
  for ((i = 1; i <= tries; i++)); do
    list="$(xcrun simctl spawn "$SIM_ID" launchctl list 2>/dev/null || true)"
    # Label form varies by iOS (`UIKitApplication:ru.recipescaler…` / short name).
    if printf '%s\n' "$list" | grep -qiE 'ru\.recipescaler\.RecipeScaler|RecipeScalerNative'; then
      return 0
    fi
    sleep 0.5
  done
  echo "ERROR: app process not running after launch" >&2
  return 1
}

# Heuristic: SpringBoard screenshots are large photographic wallpapers with
# little UI chrome density in the middle band; app screenshots of Recipe Scaler
# tend to have flatter content. More reliable gate: fail if PNG looks like
# home by checking for typical dock / search affordance via a cheap size+entropy
# is weak — instead re-launch once when caller asks, and rely on visual review.
capture_png() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  xcrun simctl io "$SIM_ID" screenshot "$dest"
  python3 - "$dest" <<'PY'
import struct, sys
from pathlib import Path
path = Path(sys.argv[1])
data = path.read_bytes()
assert data[:8] == b"\x89PNG\r\n\x1a\n", path
w, h = struct.unpack(">II", data[16:24])
ok = (w, h) in {(1260, 2736), (1320, 2868), (1290, 2796)}
print(f"  {path.name}: {w}x{h}{' OK' if ok else ' UNEXPECTED SIZE'}")
if not ok:
    raise SystemExit(f"unexpected screenshot size {w}x{h} for {path}")
PY
}

# Launch + wait + dismiss + assert running; retry once on failure.
# Optional 5th+ args are launch flags; set CAPTURE_LAUNCH_WAIT to override settle time.
launch_for_shot() {
  local user_id="$1" token="$2" seed="$3"
  shift 3
  local settle="${CAPTURE_LAUNCH_WAIT:-$SHOT_WAIT_SECONDS}"
  local attempt
  for attempt in 1 2; do
    echo "  launch attempt $attempt (wait ${settle}s): $*"
    launch_capture "$user_id" "$token" "$seed" "$@"
    wait_ready "$settle"
    dismiss_notification_alert
    if assert_app_running 10; then
      return 0
    fi
    echo "  app not running — retrying launch" >&2
  done
  echo "ERROR: failed to keep app running for shot" >&2
  return 1
}

lock_simulator() {
  # Device > Lock via menu bar item path (not menu "Device" of menu bar).
  local pass
  for pass in 1 2 3; do
    osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Simulator" to activate
delay 0.35
tell application "System Events"
  tell process "Simulator"
    try
      click menu item "Lock" of menu 1 of menu bar item "Device" of menu bar 1
    on error
      keystroke "l" using command down
    end try
  end tell
end tell
delay 1.0
tell application "System Events"
  tell process "Simulator"
    set btnNames to {"Allow", "Разрешить"}
    repeat with w in windows
      repeat with btnName in btnNames
        try
          if exists button btnName of w then
            click button btnName of w
            delay 0.5
          end if
        end try
      end repeat
    end repeat
  end tell
end tell
APPLESCRIPT
    sleep 0.8
  done
}

# Lock screen dims after a few seconds; LA then shows AOD compact "44m"
# instead of live MM:SS. Tap the wallpaper (not Home / not swipe) to wake
# without unlocking so the store frame captures seconds.
wake_lock_screen() {
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Simulator" to activate
APPLESCRIPT
  swift - <<'SWIFT'
import Cocoa
import CoreGraphics

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { exit(0) }
var chosen: (CGFloat, CGFloat, CGFloat, CGFloat)?
for win in info {
    let owner = win[kCGWindowOwnerName as String] as? String ?? ""
    let layer = win[kCGWindowLayer as String] as? Int ?? 0
    guard owner == "Simulator", layer == 0 else { continue }
    guard let b = win[kCGWindowBounds as String] as? [String: Any] else { continue }
    let x = CGFloat((b["X"] as? NSNumber)?.doubleValue ?? 0)
    let y = CGFloat((b["Y"] as? NSNumber)?.doubleValue ?? 0)
    let w = CGFloat((b["Width"] as? NSNumber)?.doubleValue ?? 0)
    let h = CGFloat((b["Height"] as? NSNumber)?.doubleValue ?? 0)
    if w < 300 || h < 500 { continue }
    chosen = (x, y, w, h)
    let name = win[kCGWindowName as String] as? String ?? ""
    if name.contains("iPhone") || h > w { break }
}
guard let (x, y, w, h) = chosen else { exit(0) }

func click(_ px: CGFloat, _ py: CGFloat) {
    if let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: px, y: py), mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
    Thread.sleep(forTimeInterval: 0.04)
    if let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: px, y: py), mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
}

// Upper-middle wallpaper — wakes display; avoid bottom LA / home indicator.
click(x + w * 0.50, y + h * 0.28)
Thread.sleep(forTimeInterval: 0.25)
click(x + w * 0.52, y + h * 0.32)
print("  woke lock screen via tap")
SWIFT
  sleep 0.8
}

dismiss_live_activity_allow_chip() {
  # Lock-screen "Allow Live Activities?" is often not exposed to AX in Simulator.
  # Tap the right-hand primary button by geometry inside the Simulator bezel.
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Simulator" to activate
APPLESCRIPT
  swift - <<'SWIFT'
import Cocoa
import CoreGraphics

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { exit(0) }
var chosen: (CGFloat, CGFloat, CGFloat, CGFloat)?
for win in info {
    let owner = win[kCGWindowOwnerName as String] as? String ?? ""
    let layer = win[kCGWindowLayer as String] as? Int ?? 0
    guard owner == "Simulator", layer == 0 else { continue }
    guard let b = win[kCGWindowBounds as String] as? [String: Any] else { continue }
    let x = CGFloat((b["X"] as? NSNumber)?.doubleValue ?? 0)
    let y = CGFloat((b["Y"] as? NSNumber)?.doubleValue ?? 0)
    let w = CGFloat((b["Width"] as? NSNumber)?.doubleValue ?? 0)
    let h = CGFloat((b["Height"] as? NSNumber)?.doubleValue ?? 0)
    if w < 300 || h < 500 { continue }
    chosen = (x, y, w, h)
    let name = win[kCGWindowName as String] as? String ?? ""
    if name.contains("iPhone") || h > w { break }
}
guard let (x, y, w, h) = chosen else { exit(0) }

func click(_ px: CGFloat, _ py: CGFloat) {
    if let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: px, y: py), mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
    Thread.sleep(forTimeInterval: 0.05)
    if let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: px, y: py), mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
}

// Primary "Allow" / "Разрешить" sits on the right half of the bottom sheet.
click(x + w * 0.68, y + h * 0.82)
Thread.sleep(forTimeInterval: 0.35)
click(x + w * 0.72, y + h * 0.85)
print("  tapped LA Allow chip region")
SWIFT
  sleep 0.5
  dismiss_notification_alert
}

press_home() {
  # Device > Home via menu bar item path (not menu "Device" of menu bar).
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Simulator" to activate
delay 0.35
tell application "System Events"
  tell process "Simulator"
    try
      click menu item "Home" of menu 1 of menu bar item "Device" of menu bar 1
    on error
      keystroke "h" using {command down, shift down}
    end try
  end tell
end tell
APPLESCRIPT
  sleep 1
}

unlock_simulator() {
  # After lock-screen shots, wake via Home.
  press_home
}

go_home() {
  # Hard home for widget page navigation (app not needed in foreground).
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  press_home
}

# Home Widget is placed manually once (see store/README.md). Find its IconState
# page; fall back to the rightmost home page. Navigate: left into App Library,
# then right-swipe back onto the target page.
open_widget_springboard_page() {
  local target_page=0
  target_page="$(python3 - "$SIM_ID" "$BUNDLE_ID" <<'PY'
from pathlib import Path
import plistlib, sys
sim, bundle = sys.argv[1], sys.argv[2]
path = Path.home() / f"Library/Developer/CoreSimulator/Devices/{sim}/data/Library/SpringBoard/IconState.plist"
try:
    data = plistlib.loads(path.read_bytes())
except Exception:
    print(0)
    raise SystemExit

def mentions_our_widget(item) -> bool:
    if isinstance(item, str):
        return False
    if not isinstance(item, dict):
        return False
    blob = " ".join(str(item.get(k, "")) for k in (
        "bundleIdentifier", "containerBundleIdentifier", "widgetIdentifier", "displayIdentifier"
    ))
    if bundle in blob or f"{bundle}.HomeWidget" in blob or "TimerWidget" in blob:
        return True
    for el in item.get("elements") or []:
        if mentions_our_widget(el):
            return True
    return False

lists = data.get("iconLists") or []
found = None
for i, page in enumerate(lists):
    for item in page:
        if mentions_our_widget(item):
            found = i
            break
    if found is not None:
        break
if found is None:
    # No widget placed yet — rightmost page is where README asks to put it.
    found = max(0, len(lists) - 1)
    print(f"WARN: RecipeScaler Home Widget not in IconState; opening page {found}", file=sys.stderr)
else:
    print(f"  IconState: Home Widget on page {found}/{len(lists)-1}", file=sys.stderr)
print(found)
PY
)"
  local pages
  pages="$(python3 - "$SIM_ID" <<'PY'
from pathlib import Path
import plistlib, sys
sim = sys.argv[1]
path = Path.home() / f"Library/Developer/CoreSimulator/Devices/{sim}/data/Library/SpringBoard/IconState.plist"
try:
    data = plistlib.loads(path.read_bytes())
    print(max(1, len(data.get("iconLists") or [])))
except Exception:
    print(1)
PY
)"
  # Overshoot into App Library, then right-swipe (pages - 1 - target) times to land on target.
  # From App Library: 1 right → last home page (index pages-1); N rights → page pages-N.
  local into_library=$((pages + 2))
  local rights_from_library=$((pages - target_page))
  if (( rights_from_library < 1 )); then rights_from_library=1; fi
  echo "  Springboard pages=$pages target=$target_page → library bounce ($into_library left, $rights_from_library right)"

  press_home
  sleep 0.5

  swift - "$into_library" "$rights_from_library" <<'SWIFT'
import Cocoa
import CoreGraphics

let intoLibrary = max(3, Int(CommandLine.arguments[1]) ?? 3)
let rights = max(1, Int(CommandLine.arguments[2]) ?? 1)

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    fputs("  widget swipe skipped: no window list\n", stderr)
    exit(0)
}
var chosen: (CGFloat, CGFloat, CGFloat, CGFloat)?
for win in info {
    let owner = win[kCGWindowOwnerName as String] as? String ?? ""
    let layer = win[kCGWindowLayer as String] as? Int ?? 0
    guard owner == "Simulator", layer == 0 else { continue }
    guard let b = win[kCGWindowBounds as String] as? [String: Any] else { continue }
    let x = CGFloat((b["X"] as? NSNumber)?.doubleValue ?? 0)
    let y = CGFloat((b["Y"] as? NSNumber)?.doubleValue ?? 0)
    let w = CGFloat((b["Width"] as? NSNumber)?.doubleValue ?? 0)
    let h = CGFloat((b["Height"] as? NSNumber)?.doubleValue ?? 0)
    if w < 300 || h < 500 { continue }
    chosen = (x, y, w, h)
    let name = win[kCGWindowName as String] as? String ?? ""
    if name.contains("iPhone") || h > w { break }
}
guard let (x, y, w, h) = chosen else {
    fputs("  widget swipe skipped: Simulator window not found\n", stderr)
    exit(0)
}

func post(_ type: CGEventType, _ px: CGFloat, _ py: CGFloat) {
    if let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: px, y: py), mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
}

func swipe(fromStartX startX: CGFloat, toEndX endX: CGFloat) {
    let sy = y + h * 0.48
    post(.leftMouseDown, startX, sy)
    Thread.sleep(forTimeInterval: 0.04)
    for i in 1...14 {
        let t = CGFloat(i) / 14.0
        post(.leftMouseDragged, startX + (endX - startX) * t, sy)
        Thread.sleep(forTimeInterval: 0.012)
    }
    post(.leftMouseUp, endX, sy)
    Thread.sleep(forTimeInterval: 0.35)
}

let leftStart = x + w * 0.82
let leftEnd = x + w * 0.18
let rightStart = x + w * 0.18
let rightEnd = x + w * 0.82

for _ in 0..<intoLibrary {
    swipe(fromStartX: leftStart, toEndX: leftEnd)
}
for _ in 0..<rights {
    swipe(fromStartX: rightStart, toEndX: rightEnd)
}
print("  opened springboard page via App Library bounce (\(intoLibrary) left + \(rights) right)")
SWIFT
  sleep 0.4
}

# Back-compat alias used nowhere else after rename.
open_last_springboard_page() {
  open_widget_springboard_page
}

manifest_value() {
  local locale="$1" key="$2"
  python3 - "$MANIFEST" "$locale" "$key" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
locale, key = sys.argv[2], sys.argv[3]
section = text.split(f"  {locale}:", 1)[1]
if locale == "ru":
    section = section.split("\n  en:", 1)[0]
for line in section.splitlines():
    line = line.strip()
    if line.startswith(key + ":"):
        value = line.split(":", 1)[1].strip().strip('"').strip("'")
        print(value)
        break
PY
}

shopping_seed_arg() {
  local locale="$1"
  python3 - "$MANIFEST" "$locale" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
locale = sys.argv[2]
block = text.split(f"  {locale}:", 1)[1]
if locale == "ru":
    block = block.split("  en:", 1)[0]
in_items = False
items = []
for line in block.splitlines():
    if line.strip().startswith("shoppingItems:"):
        in_items = True
        continue
    if in_items:
        stripped = line.strip()
        if stripped.startswith("- "):
            items.append(stripped[2:].strip().strip('"'))
        elif stripped and not stripped.startswith("-") and not stripped.startswith("#"):
            break
print("|".join(items))
PY
}

capture_shot() {
  local shot="$1" out_dir="$2" user_id="$3" token="$4" seed="$5"
  local app_lang="$6" appearance="$7" recipe_name="$8" timer_name="$9" discover_profile="${10}"
  local shopping_seed="${11}"

  case "$shot" in
    01-recipes)
      launch_for_shot "$user_id" "$token" "$seed" \
        "-AppLanguage=$app_lang" \
        "-AppTheme=$appearance" \
        "-OpenTab=recipes"
      # Extra settle: second timer sweep (~2s) + list thumbnails.
      wait_ready 3
      dismiss_notification_alert
      capture_png "$out_dir/01-recipes.png"
      ;;
    02-cooking)
      launch_for_shot "$user_id" "$token" "$seed" \
        "-AppLanguage=$app_lang" \
        "-AppTheme=$appearance" \
        "-OpenRecipeName=$recipe_name" \
        "-ScreenshotScaleFactor=2" \
        "-ScreenshotScreenAwake=1" \
        "-ScreenshotTimerSeconds=2700" \
        "-ScreenshotTimerName=$timer_name" \
        "-MobileTimerPanelExpanded=1"
      wait_ready 2
      dismiss_notification_alert
      capture_png "$out_dir/02-cooking.png"
      ;;
    03-discover)
      launch_for_shot "$user_id" "$token" "$seed" \
        "-AppLanguage=$app_lang" \
        "-AppTheme=$appearance" \
        "-OpenDiscoverProfile=$discover_profile"
      wait_ready 2
      capture_png "$out_dir/03-discover.png"
      ;;
    04-shopping)
      launch_for_shot "$user_id" "$token" "$seed" \
        "-AppLanguage=$app_lang" \
        "-AppTheme=$appearance" \
        "-OpenTab=shopping" \
        "-ScreenshotShoppingSeed=$shopping_seed"
      # Seed replaces list after ~0.8s launch hook — wait for UI refresh.
      wait_ready 4
      dismiss_notification_alert
      capture_png "$out_dir/04-shopping.png"
      ;;
    05-assistant)
      launch_for_shot "$user_id" "$token" "$seed" \
        "-AppLanguage=$app_lang" \
        "-AppTheme=$appearance" \
        "-ShowAssistant=1" \
        "-ScreenshotAssistantFixture=1"
      wait_ready 2
      capture_png "$out_dir/05-assistant.png"
      ;;
    06-widget)
      # Ensure timer snapshot exists for the widget timeline, then leave the app.
      # Cmd+Shift+H alone is flaky while the app is foreground — terminate first
      # (widget reads App Group / chronod, not the live process).
      grant_capture_permissions
      launch_for_shot "$user_id" "$token" "$seed" \
        "-AppLanguage=$app_lang" \
        "-AppTheme=$appearance" \
        "-ScreenshotTimerSeconds=2700" \
        "-ScreenshotTimerName=$timer_name" \
        "-MobileTimerPanelExpanded=1"
      dismiss_notification_alert
      wait_ready 2
      xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
      sleep 1
      press_home
      open_widget_springboard_page
      override_status_bar
      capture_png "$out_dir/06-widget.png"
      ;;
    07-live-activity)
      # Grant LA *before* starting the activity; never bounce liveactivitiesd here.
      # Give ActivityKit a few extra seconds so endDate lands in the LA before lock
      # (otherwise a late endDate + AOD dim can look wrong before wake).
      grant_capture_permissions
      CAPTURE_LAUNCH_WAIT=8 launch_for_shot "$user_id" "$token" "$seed" \
        "-AppLanguage=$app_lang" \
        "-AppTheme=$appearance" \
        "-ScreenshotTimerSeconds=2700" \
        "-ScreenshotTimerName=$timer_name" \
        "-MobileTimerPanelExpanded=1"
      dismiss_notification_alert
      lock_simulator
      sleep 1.5
      # AX-only Allow attempt (no geometry taps — those unlock the phone).
      dismiss_notification_alert
      # Lock screen ignores earlier status_bar override until re-applied (ISO time).
      override_status_bar
      sleep 0.4
      # Dimmed lock screen shows incomplete timer digits — wake with a tap.
      wake_lock_screen
      override_status_bar
      dismiss_notification_alert
      # Extra settle so ActivityKit paints the compact/expanded LA on lock.
      sleep 1.5
      capture_png "$out_dir/07-live-activity.png"
      unlock_simulator
      ;;
    08-push)
      grant_capture_permissions
      # Controlled timing: N-second timer, short settle, Home, wait for banner.
      # Do not wait minutes — banner auto-dismisses after a few seconds.
      local push_secs="$PUSH_TIMER_SECONDS"
      local settle=2
      CAPTURE_LAUNCH_WAIT=$settle launch_for_shot "$user_id" "$token" "$seed" \
        "-AppLanguage=$app_lang" \
        "-AppTheme=$appearance" \
        "-ScreenshotTimerSeconds=$push_secs" \
        "-ScreenshotTimerName=$timer_name" \
        "-MobileTimerPanelExpanded=1"
      dismiss_notification_alert
      # Banner needs background — Home without terminate so the timer can fire.
      press_home
      # Remaining ≈ push_secs - settle; +1s for banner paint.
      local after_home=$((push_secs - settle + 1))
      if (( after_home < PUSH_BANNER_WAIT_SECONDS )); then
        after_home="$PUSH_BANNER_WAIT_SECONDS"
      fi
      echo "  waiting ${after_home}s for push banner (timer ${push_secs}s)"
      wait_ready "$after_home"
      override_status_bar
      capture_png "$out_dir/08-push.png"
      ;;
    *)
      echo "Unknown shot: $shot" >&2
      return 1
      ;;
  esac
}

resolve_sim
if [[ "$SKIP_BUILD" != "1" ]]; then
  sim_ensure_built
fi
sim_prepare
# One install per session — never uninstall between locales (keeps widget / icon / TCC).
sim_install
grant_capture_permissions_cold
override_status_bar

PREV_LOCALE=""
PREV_OS_LANG=""
for locale in "${LOCALES[@]}"; do
  archive="$ROOT/store/fixtures/recipes-${locale}.zip"
  [[ -f "$archive" ]] || { echo "missing $archive" >&2; exit 1; }
  recipe_name="$(manifest_value "$locale" primaryRecipeName)"
  timer_name="$(manifest_value "$locale" timerName)"
  discover_profile="$(manifest_value "$locale" discoverProfileUsername)"
  app_lang="$(manifest_value "$locale" appLanguage)"
  shopping_seed="$(shopping_seed_arg "$locale")"

  echo "== Locale $locale: login store user =="
  user_id=""; token=""; seed=""
  {
    IFS= read -r user_id
    IFS= read -r token
    IFS= read -r seed
  } < <(login_store_user "$locale")

  # Relogin only — no uninstall / no container wipe.
  set_flat_recipe_list
  set_languages "$app_lang"

  if [[ "$PREV_LOCALE" != "$locale" ]]; then
    if [[ "$SKIP_SYNC" == "1" ]]; then
      echo "== $locale: skip sync (--skip-sync), reuse session ($user_id) =="
      PREV_LOCALE="$locale"
    else
      echo "== $locale: relogin + sync library ($user_id) =="
      set_appearance "${APPEARANCES[0]}"
      launch_capture "$user_id" "$token" "$seed" \
        "-AppLanguage=$app_lang" \
        "-AppTheme=${APPEARANCES[0]}" \
        "-OpenTab=recipes"
      wait_ready "$SYNC_WAIT_SECONDS"
      dismiss_notification_alert
      assert_app_running 10 || {
        echo "retry sync launch after assert failure" >&2
        launch_capture "$user_id" "$token" "$seed" \
          "-AppLanguage=$app_lang" \
          "-AppTheme=${APPEARANCES[0]}" \
          "-OpenTab=recipes"
        wait_ready "$SYNC_WAIT_SECONDS"
        dismiss_notification_alert
        assert_app_running 10
      }
      PREV_LOCALE="$locale"
    fi
  fi

  for appearance in "${APPEARANCES[@]}"; do
    if ! any_shot_wanted "${ALL_SHOTS[@]}"; then
      continue
    fi
    out_dir="$OUT_ROOT/$locale/$appearance"
    mkdir -p "$out_dir"
    echo "== $locale / $appearance =="
    # Do NOT unlock/Home before in-app shots — that parked us on SpringBoard for 01.
    set_appearance "$appearance"
    override_status_bar
    set_flat_recipe_list

    for shot in "${ALL_SHOTS[@]}"; do
      if shot_wanted "$shot"; then
        echo "-- shot $shot --"
        capture_shot "$shot" "$out_dir" "$user_id" "$token" "$seed" \
          "$app_lang" "$appearance" "$recipe_name" "$timer_name" "$discover_profile" \
          "$shopping_seed"
      fi
    done
  done
done

if [[ "$SKIP_VALIDATE" != "1" ]]; then
  bash "$ROOT/scripts/validate-app-store-screenshots.sh"
fi
echo "Done. PNGs in $OUT_ROOT"
