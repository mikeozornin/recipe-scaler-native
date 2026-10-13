#!/usr/bin/env bash
# Spec 081 (US7, T049) — one window through the multitasking widths: IPadMultitaskingSpec
# with host screenshots. Also `bash scripts/verify-ipad-layout.sh --matrix [options]`.
#
# Usage:
#   bash scripts/verify-ipad-matrix.sh                      # build-for-testing + the whole spec
#   bash scripts/verify-ipad-matrix.sh --skip-build         # reuse the last build-for-testing
#   bash scripts/verify-ipad-matrix.sh --only testRecipesWidthsLandscape
#
# The app runs with `-DebugWindowWidthLive=1`: the test resizes its root at runtime, as Split
# View and Stage Manager resize a window (the simulator cannot script either), and checks the
# layout, the open recipe and its collection at every width (SC-005). With
# IPAD_MATRIX_SHOTS=1 in the test runner (passed as TEST_RUNNER_IPAD_MATRIX_SHOTS) the test
# prints `IPAD_MATRIX_SHOT <n> <name>` at each width; this script takes a `simctl io
# screenshot` (the XCTest one is a cropped portrait buffer in landscape; landscape shots are
# turned upright with sips) and answers over the
# Darwin notification `ru.recipescaler.debug.matrix-shot`; the test prints
# `IPAD_MATRIX_SHOT_TAKEN <n>`. `IPAD_MATRIX_ROW` lines (the measured layout of each step) go
# to matrix.txt.
#
# Needs: the loopback backend on 127.0.0.1:3001, or E2E_API_BASE (the spec registers fresh
# users: the screenshots carry no real data); an iPad simulator. iPadOS 26.2+ runs the
# adaptive shell; an older one (IPAD_SIM_ID) walks the old shell, the system tab bar (T051).
#
# Env:
#   IPAD_SIM_ID             iPad simulator override (scripts/resolve-ipad-simulator.sh)
#   IPAD_MATRIX_OUT         output dir (default tmp/ipad-verify/us7): <device>/<shot>.png,
#                           <device>/matrix.txt, build.log, test-<device>.log, shots-<device>.log,
#                           IPadMultitaskingSpec-<device>.xcresult
#   IPAD_MATRIX_SHOT_DELAY  seconds between a marker and its screenshot (default 1)
#
# Verdict: VERIFIED only when xcodebuild passes, at least one test ran, none was skipped, and
# every screenshot the tests asked for was taken and seen. The screenshots are judged by eye
# against layout.md §Матрица приёмки. FAILED otherwise (exit 1); INCONCLUSIVE when the
# backend or the simulator is missing (exit 2).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_BUILD=0
ONLY=""
while (($#)); do
  case "$1" in
    --matrix) ;;
    --skip-build) SKIP_BUILD=1 ;;
    --only)
      [[ $# -ge 2 ]] || { echo "FAILED: --only needs a test name" >&2; exit 1; }
      ONLY="$2"
      shift
      ;;
    -h|--help)
      sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "FAILED: unknown option $1" >&2
      exit 1
      ;;
  esac
  shift
done

OUT="${IPAD_MATRIX_OUT:-$ROOT/tmp/ipad-verify/us7}"
SHOT_DELAY="${IPAD_MATRIX_SHOT_DELAY:-1}"
TEST_ID="RecipeScalerNativeUITests/IPadMultitaskingSpec${ONLY:+/$ONLY}"
SHOT_NAME="ru.recipescaler.debug.matrix-shot"

inconclusive() {
  echo "INCONCLUSIVE: $*" >&2
  exit 2
}

failed() {
  echo "FAILED: $*" >&2
  exit 1
}

API_BASE="${E2E_API_BASE:-http://127.0.0.1:3001}"
if ! curl -s -o /dev/null --max-time 5 "$API_BASE/api/health"; then
  inconclusive "no backend at $API_BASE (the spec registers fresh users)"
fi

SIM="$(bash "$ROOT/scripts/resolve-ipad-simulator.sh")"
[[ -n "$SIM" ]] || inconclusive "no iPad simulator"
DEST="platform=iOS Simulator,id=$SIM"

# «iPad Pro 13-inch (M4)» → ipad-pro-13-inch-m4: one folder of screenshots per screen.
DEVICE_NAME="$(xcrun simctl list devices | { grep -F "($SIM)" || true; } | head -1 | sed -E 's/^ *//; s/ \([0-9A-F-]{36}\).*$//')"
[[ -n "$DEVICE_NAME" ]] || inconclusive "simulator $SIM is not in simctl list"
DEVICE="$(printf '%s' "$DEVICE_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"

SHOTS="$OUT/$DEVICE"
mkdir -p "$SHOTS"
BUILD_LOG="$OUT/build.log"
TEST_LOG="$OUT/test-$DEVICE.log"
SHOTS_LOG="$OUT/shots-$DEVICE.log"
MATRIX="$SHOTS/matrix.txt"
RESULT="$OUT/IPadMultitaskingSpec-$DEVICE.xcresult"
: >"$SHOTS_LOG"

if (( SKIP_BUILD )); then
  echo "== build-for-testing skipped (--skip-build): the verdict covers the last build =="
else
  echo "== build-for-testing ($DEVICE_NAME, $SIM) → $BUILD_LOG =="
  build_status=0
  xcodebuild build-for-testing -scheme RecipeScalerNative -destination "$DEST" >"$BUILD_LOG" 2>&1 || build_status=$?
  (( build_status == 0 )) || failed "build-for-testing exit $build_status (see $BUILD_LOG)"
fi

echo "== $TEST_ID on $DEVICE_NAME → $TEST_LOG, screenshots → $SHOTS =="
rm -rf "$RESULT"
export TEST_RUNNER_IPAD_MATRIX_SHOTS=1
xcodebuild test-without-building -scheme RecipeScalerNative -destination "$DEST" \
  "-only-testing:$TEST_ID" -resultBundlePath "$RESULT" >"$TEST_LOG" 2>&1 &
xc_pid=$!

stop_tests() {
  kill "$xc_pid" 2>/dev/null || true
  wait "$xc_pid" 2>/dev/null || true
}

# Turns a portrait-buffer screenshot of a landscape window upright (the status bar on top).
upright() {
  local dims width height
  dims="$(sips -g pixelWidth -g pixelHeight "$1" 2>>"$SHOTS_LOG")" || return 1
  width="$(awk '/pixelWidth/ {print $2}' <<<"$dims")"
  height="$(awk '/pixelHeight/ {print $2}' <<<"$dims")"
  [[ -n "$width" && -n "$height" ]] || return 1
  (( width < height )) || return 0
  sips -r 270 "$1" >>"$SHOTS_LOG" 2>&1
}

taken=0
shot_error=""
while :; do
  running=0
  kill -0 "$xc_pid" 2>/dev/null && running=1
  while read -r _ step name; do
    sleep "$SHOT_DELAY"
    if ! xcrun simctl io "$SIM" screenshot "$SHOTS/$name.png" >>"$SHOTS_LOG" 2>&1; then
      shot_error="simctl io screenshot failed for marker $step ($name), see $SHOTS_LOG"
      break 2
    fi
    # simctl keeps the portrait buffer: a landscape window comes out on its side.
    if [[ "$name" == *-landscape-* ]] && ! upright "$SHOTS/$name.png"; then
      shot_error="could not turn screenshot $step ($name) upright, see $SHOTS_LOG"
      break 2
    fi
    # The test holds the name, so the state outlives this notifyutil.
    if ! xcrun simctl spawn "$SIM" notifyutil -s "$SHOT_NAME" "$step" >>"$SHOTS_LOG" 2>&1 \
      || ! xcrun simctl spawn "$SIM" notifyutil -p "$SHOT_NAME" >>"$SHOTS_LOG" 2>&1; then
      shot_error="notifyutil could not answer marker $step, see $SHOTS_LOG"
      break 2
    fi
    echo "$step $name taken" | tee -a "$SHOTS_LOG"
    taken=$((taken + 1))
  done < <(grep -E '^IPAD_MATRIX_SHOT [0-9]+ [A-Za-z0-9._-]+$' "$TEST_LOG" | sed -n "$((taken + 1)),\$p")
  (( running )) || break
  sleep 1
done

if [[ -n "$shot_error" ]]; then
  stop_tests
  failed "$shot_error"
fi

test_status=0
wait "$xc_pid" || test_status=$?

{
  echo "# $DEVICE_NAME ($SIM) — IPadMultitaskingSpec, $(date '+%Y-%m-%d %H:%M')"
  echo "# root: the app root width; bar: tabs at the top (or sidebar) / the phone bottom bar;"
  echo "# list: the right edge of the list column (- none); columns: recipe columns;"
  echo "# left: the left recipe column width; panel: the assistant panel width."
  grep -E '^IPAD_MATRIX_(ROW|NOTE) ' "$TEST_LOG" | sed -E 's/^IPAD_MATRIX_ROW //; s/^IPAD_MATRIX_NOTE /note: /' || true
} >"$MATRIX"

grep -E "^Test Case .*(passed|failed|skipped)" "$TEST_LOG" | sed 's/^/  /' || true

(( test_status == 0 )) || failed "xcodebuild test-without-building exit $test_status (see $TEST_LOG)"

executed="$(sed -nE 's/.*Executed ([0-9]+) tests?,.*/\1/p' "$TEST_LOG" | tail -1)"
[[ -n "$executed" && "$executed" -gt 0 ]] || failed "zero tests executed (see $TEST_LOG)"

if grep -qE "^Test Case '.*' skipped" "$TEST_LOG"; then
  failed "a test skipped (not an iPad simulator? see $TEST_LOG)"
fi

(( taken > 0 )) || failed "the tests asked for no screenshot"
for step in $(grep -E '^IPAD_MATRIX_SHOT [0-9]+ ' "$TEST_LOG" | awk '{print $2}'); do
  grep -qE "^IPAD_MATRIX_SHOT_TAKEN $step\$" "$TEST_LOG" \
    || failed "screenshot $step was taken but the test did not see the answer"
done

echo "VERIFIED ipad-matrix ($executed tests on $DEVICE_NAME, $taken screenshots in $SHOTS, layout table $MATRIX)"
