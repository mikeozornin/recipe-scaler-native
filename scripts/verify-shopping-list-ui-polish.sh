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
echo "VERIFIED shopping-list-ui-polish"