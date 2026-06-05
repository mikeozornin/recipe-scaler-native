#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

RESULT_HOST="$ROOT/.shopping-smoke-result.json"
rm -f "$RESULT_HOST"

sim_build >/dev/null
sim_prepare
sim_install
sim_terminate
container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
if [[ -n "$container" ]]; then
  rm -f "$container/Library/Caches/shopping-smoke-result.json"
  rm -f "$container/Library/Caches/shopping-smoke-launch.json"
  db="$container/Library/Application Support/ydoc_snapshots.sqlite"
  if [[ -f "$db" ]]; then
    sqlite3 "$db" "DELETE FROM ydoc_snapshots WHERE docKey LIKE '%:shoppingList';" 2>/dev/null || true
  fi
fi
sim_launch -SkipSplash=1 -ShoppingSmokeTest=1

echo "Waiting for shopping smoke test (collection + adds)…"
for _ in $(seq 1 60); do
  sleep 2
  container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" ]]; then
    src="$container/Library/Caches/shopping-smoke-result.json"
    if [[ -f "$src" ]]; then
      cp "$src" "$RESULT_HOST"
      if python3 -c "import json,sys; d=json.load(open('$RESULT_HOST')); sys.exit(0 if d.get('finished') else 1)" 2>/dev/null; then
        break
      fi
    fi
  fi
done

if [[ ! -f "$RESULT_HOST" ]]; then
  echo "FAIL: shopping-smoke-result.json not found in simulator container" >&2
  sim_pull_debug_log || true
  exit 1
fi

# Do not relaunch until after result — second launch only for screenshot.

cat "$RESULT_HOST"
python3 - <<'PY'
import json, sys
from pathlib import Path
p = Path(".shopping-smoke-result.json")
data = json.loads(p.read_text())
if not data.get("finished"):
    print("FAIL: smoke test did not finish", data, file=sys.stderr)
    sys.exit(1)
if not data.get("passed"):
    print("FAIL: smoke test did not pass", data, file=sys.stderr)
    sys.exit(1)
print("OK steps:", data.get("steps"))
print("OK itemCount:", data.get("itemCount"))
PY

SHOT_DIR="$ROOT/specs/024-shopping-list-completion/screenshots"
if xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" -SkipSplash=1 -OpenTab=shopping >/dev/null 2>&1; then
  sim_wait_ready 6
  SHOT="$(sim_screenshot "$SHOT_DIR" "shopping-smoke")"
  echo "Screenshot: $SHOT"
fi
echo "VERIFIED shopping-list-smoke"