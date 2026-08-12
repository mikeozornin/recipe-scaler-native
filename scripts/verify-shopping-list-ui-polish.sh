#!/usr/bin/env bash
# Simulator screenshots + toast record for shopping header/share/copy polish.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/024-shopping-list-completion/screenshots"
TOAST_HOST="$ROOT/.shopping-toast-verify.json"

echo "== Populate shopping list (smoke) =="
bash "$ROOT/scripts/verify-shopping-list-smoke.sh" >/dev/null

sim_build >/dev/null
sim_prepare
sim_install

read_toast_record() {
  local container
  container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -z "$container" ]]; then
    return 1
  fi
  local src="$container/Library/Caches/shopping-toast-verify.json"
  if [[ -f "$src" ]]; then
    cp "$src" "$TOAST_HOST"
    return 0
  fi
  return 1
}

echo "== Screenshot: shopping header =="
sim_terminate
container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
rm -f "$container/Library/Caches/shopping-toast-verify.json" 2>/dev/null || true
sim_launch -SkipSplash=1 -OpenTab=shopping
sim_wait_ready 6
HEADER_SHOT="$(sim_screenshot "$SHOT_DIR" "shopping-header")"
echo "Header: $HEADER_SHOT"

echo "== Screenshot: share sheet open =="
sim_terminate
sim_launch -SkipSplash=1 -OpenTab=shopping -OpenShoppingShare=1
sim_wait_ready 5
SHARE_SHOT="$(sim_screenshot "$SHOT_DIR" "shopping-share-sheet")"
echo "Share sheet: $SHARE_SHOT"

echo "== Copy-as-text → toast =="
sim_terminate
rm -f "$TOAST_HOST"
container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
rm -f "$container/Library/Caches/shopping-toast-verify.json" 2>/dev/null || true
sim_launch -SkipSplash=1 -OpenTab=shopping -ShoppingShareAutoCopyText=1
for _ in $(seq 1 35); do
  sleep 1
  if read_toast_record; then
    break
  fi
done

if [[ ! -f "$TOAST_HOST" ]]; then
  echo "FAIL: shopping-toast-verify.json not found" >&2
  exit 1
fi

cat "$TOAST_HOST"
python3 - <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(".shopping-toast-verify.json").read_text())
msg = data.get("message", "")
if not msg:
    print("FAIL: empty toast message", file=sys.stderr)
    sys.exit(1)
# Debug sim locale is typically ru for this project.
if "List copied" not in msg and "Список скопирован" not in msg and "скопирован" not in msg.lower():
    print("FAIL: unexpected toast:", msg, file=sys.stderr)
    sys.exit(1)
print("OK toast:", msg)
PY

sim_wait_ready 1
TOAST_SHOT="$(sim_screenshot "$SHOT_DIR" "shopping-toast-after-copy")"
echo "Toast screenshot: $TOAST_SHOT"

echo "== Leading swipe → toggle purchased =="
# Pre-swipe baseline: shopping tab with at least one item in «Купить».
sim_terminate
sim_launch -SkipSplash=1 -OpenTab=shopping
sim_wait_ready 6
BEFORE_SWIPE_SHOT="$(sim_screenshot "$SHOT_DIR" "shopping-swipe-before")"
echo "Pre-swipe screenshot: $BEFORE_SWIPE_SHOT"

# Swipe right-to-left from the leading edge of the first shopping row.
# Uses CGEvent drag (same mechanism as scripts/capture-app-store-screenshots.sh).
# Y is near the top of the shopping list (below the sort segmented control).
SWIPE_RESULT="$(
  SWIPE_Y="${SHOPPING_SWIPE_Y:-220}" \
  SWIPE_START_X="${SHOPPING_SWIPE_START_X:-12}" \
  SWIPE_END_X="${SHOPPING_SWIPE_END_X:-300}" \
  swift - <<'SWIFT'
import CoreGraphics
import Foundation

let env = ProcessInfo.processInfo.environment
guard let y = Double(env["SWIPE_Y"] ?? ""),
      let startX = Double(env["SWIPE_START_X"] ?? ""),
      let endX = Double(env["SWIPE_END_X"] ?? "") else {
  fputs("missing swipe coordinates\n", stderr); exit(1)
}

func post(_ type: CGEventType, _ x: Double, _ y: Double) {
  let p = CGPoint(x: x, y: y)
  if let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left) {
    e.post(tap: .cghidEventTap)
  }
}

post(.leftMouseDown, startX, y)
Thread.sleep(forTimeInterval: 0.05)
let steps = 18
for i in 1...steps {
  let t = Double(i) / Double(steps)
  post(.leftMouseDragged, startX + (endX - startX) * t, y)
  Thread.sleep(forTimeInterval: 0.012)
}
Thread.sleep(forTimeInterval: 0.05)
post(.leftMouseUp, endX, y)
print("ok")
SWIFT
)"

if [[ "$SWIPE_RESULT" != "ok" ]]; then
  echo "FAIL: leading swipe did not complete (swift helper error)" >&2
  exit 1
fi

# Allow staging (~1s) + exit animation (~0.4s) to settle, then capture the result.
sleep 2
AFTER_SWIPE_SHOT="$(sim_screenshot "$SHOT_DIR" "shopping-swipe-after")"
echo "Post-swipe screenshot: $AFTER_SWIPE_SHOT"

# Observational assert: the two screenshots must differ — leading-swipe toggle
# visually changes the row layout (item moves to «Куплено», strikethrough appears).
BEFORE_SIZE=$(stat -f%z "$BEFORE_SWIPE_SHOT" 2>/dev/null || stat -c%s "$BEFORE_SWIPE_SHOT")
AFTER_SIZE=$(stat -f%z "$AFTER_SWIPE_SHOT" 2>/dev/null || stat -c%s "$AFTER_SWIPE_SHOT")
if [[ "$BEFORE_SIZE" == "$AFTER_SIZE" ]]; then
  echo "FAIL: before/after swipe screenshots identical (size=$BEFORE_SIZE) — swipe likely did not toggle the item" >&2
  exit 1
fi
echo "OK leading-swipe screenshots differ (before=$BEFORE_SIZE after=$AFTER_SIZE)"
echo "Manual inspect recommended: diff '$BEFORE_SWIPE_SHOT' '$AFTER_SWIPE_SHOT'"

echo "VERIFIED shopping-list-ui-polish"