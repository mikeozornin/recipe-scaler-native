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

# Localized titles for the three actions + title/body
rg -q 'timer\.notification\.action\.add-minute'        "$TM"
rg -q 'timer\.notification\.action\.add-five-minutes'  "$TM"
rg -q 'timer\.notification\.action\.delete'            "$TM"
rg -q 'timer\.notification\.title'                     "$TM"
rg -q 'timer\.notification\.body'                      "$TM"

# xcstrings has the new keys
rg -q 'timer\.notification\.title'                     "$XC"
rg -q 'timer\.notification\.body'                      "$XC"
rg -q 'timer\.notification\.action\.add-minute'        "$XC"
rg -q 'timer\.notification\.action\.add-five-minutes'  "$XC"
rg -q 'timer\.notification\.action\.delete'            "$XC"

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

echo "VERIFIED timer-notification-actions (036 static + build; runtime QA on simulator)"
