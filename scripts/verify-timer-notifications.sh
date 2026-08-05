#!/usr/bin/env bash
# Verifies spec 036 — timer notification action buttons (+1 / +5 / Delete).
# Static checks only: runtime notification UI requires manual QA on simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TM="RecipeScalerNative/Services/TimerManager.swift"
XC="RecipeScalerNative/Resources/Localizable.xcstrings"

echo "== spec 036: timer notification actions =="

# Spec exists
test -f specs/036-timer-notification-actions/spec.md

# New action identifiers registered
rg -q 'ADD_ONE_MINUTE'      "$TM"
rg -q 'ADD_FIVE_MINUTES'    "$TM"
rg -q 'DELETE_TIMER'        "$TM"

# New addTime API
rg -q 'func addTime\(id: String, minutes: Int\)' "$TM"

# Localized titles for the three actions + title/body (in-app locale, not String(localized:))
rg -q 'Bundle\.currentLocalizedString\("timer\.notification\.action\.add-minute"\)'        "$TM"
rg -q 'Bundle\.currentLocalizedString\("timer\.notification\.action\.add-five-minutes"\)'  "$TM"
rg -q 'Bundle\.currentLocalizedString\("timer\.notification\.action\.delete"\)'            "$TM"
rg -q 'Bundle\.currentLocalizedString\("timer\.notification\.title"\)'                     "$TM"
rg -q 'Bundle\.currentLocalizedString\("timer\.notification\.body"\)'                      "$TM"
if rg -n 'String\(localized: "timer\.notification\.' "$TM"; then
  echo "FAIL: timer.notification.* still uses String(localized:) — must use Bundle.currentLocalizedString" >&2
  exit 1
fi

# xcstrings has the new keys
rg -q 'timer\.notification\.title'                     "$XC"
rg -q 'timer\.notification\.body'                      "$XC"
rg -q 'timer\.notification\.action\.add-minute'        "$XC"
rg -q 'timer\.notification\.action\.add-five-minutes'  "$XC"
rg -q 'timer\.notification\.action\.delete'            "$XC"

# Web parity copy (server locales)
rg -q 'Проверьте, что вы там готовите'                 "$XC"
rg -q "Go and check what you're cooking"               "$XC"

# Old identifiers must be gone (replaced, not duplicated)
if rg -q 'SNOOZE_ACTION' "$TM"; then
    echo "FAIL: SNOOZE_ACTION still present in $TM" >&2
    exit 1
fi
if rg -q 'DISMISS_ACTION' "$TM"; then
    echo "FAIL: DISMISS_ACTION still present in $TM" >&2
    exit 1
fi
if rg -q 'snoozeTimer' "$TM"; then
    echo "FAIL: snoozeTimer still present in $TM" >&2
    exit 1
fi

# Cancel-id fix: deleteTimer references the "-complete" suffix
rg -q '"\\\(timer\.id\)-complete"' "$TM"

# Build the app
echo "== xcodebuild =="
source "$ROOT/scripts/sim-verify-lib.sh"
sim_build >/dev/null

echo "== xctest: TimerNotificationActionsTests =="
xcodebuild build-for-testing -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -configuration Debug \
  -quiet
xcodebuild test-without-building -scheme RecipeScalerNative \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -configuration Debug \
  -only-testing:RecipeScalerNativeTests/TimerNotificationActionsTests \
  -quiet

echo "== simulator smoke: +1 / +5 / delete =="
RESULT_HOST="$ROOT/.timer-notification-smoke-result.json"
rm -f "$RESULT_HOST"
SHOT_DIR="$ROOT/specs/036-timer-notification-actions/screenshots"
mkdir -p "$SHOT_DIR"

sim_prepare
sim_install
sim_terminate
container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
if [[ -n "$container" ]]; then
  rm -f "$container/Library/Caches/timer-notification-smoke-result.json"
fi

sim_launch -SkipSplash=1 -TimerNotificationSmokeTest=1

echo "Waiting for timer notification smoke test…"
CAPTURED_EXTENDED=0
CAPTURED_COMPLETED=0
for _ in $(seq 1 30); do
  sleep 1
  container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" ]]; then
    src="$container/Library/Caches/timer-notification-smoke-result.json"
    if [[ -f "$src" ]]; then
      cp "$src" "$RESULT_HOST"
      if [[ "$CAPTURED_COMPLETED" == "0" ]] && python3 -c "import json; d=json.load(open('$RESULT_HOST')); exit(0 if d.get('steps',{}).get('timerCompleted') else 1)" 2>/dev/null; then
        SHOT="$(sim_screenshot "$SHOT_DIR" "timer-notification-completed")"
        echo "Screenshot (completed): $SHOT"
        CAPTURED_COMPLETED=1
      fi
      if [[ "$CAPTURED_EXTENDED" == "0" ]] && python3 -c "import json; d=json.load(open('$RESULT_HOST')); exit(0 if d.get('steps',{}).get('addOneMinute') else 1)" 2>/dev/null; then
        SHOT="$(sim_screenshot "$SHOT_DIR" "timer-notification-extended")"
        echo "Screenshot (after +1): $SHOT"
        CAPTURED_EXTENDED=1
      fi
      if python3 -c "import json,sys; d=json.load(open('$RESULT_HOST')); sys.exit(0 if d.get('finished') else 1)" 2>/dev/null; then
        break
      fi
    fi
  fi
done

if [[ ! -f "$RESULT_HOST" ]]; then
  echo "FAIL: timer-notification-smoke-result.json not found" >&2
  sim_pull_debug_log || true
  exit 1
fi

cat "$RESULT_HOST"
python3 - <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(".timer-notification-smoke-result.json").read_text())
if not data.get("finished"):
    print("FAIL: smoke test did not finish", data, file=sys.stderr)
    sys.exit(1)
if not data.get("passed"):
    print("FAIL: smoke test did not pass", data, file=sys.stderr)
    sys.exit(1)
print("OK steps:", data.get("steps"))
PY

echo "VERIFIED timer-notification-actions (036 static + build + xctest + smoke; notification UI QA on simulator)"
