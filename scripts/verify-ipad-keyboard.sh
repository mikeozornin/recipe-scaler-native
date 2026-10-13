#!/usr/bin/env bash
# Spec 081 (US6) — the iPad keyboard shortcuts: IPadKeyboardSpec with the host keys.
#
# Usage:
#   bash scripts/verify-ipad-keyboard.sh                    # build-for-testing + the whole spec
#   bash scripts/verify-ipad-keyboard.sh --skip-build       # reuse the last build-for-testing
#   bash scripts/verify-ipad-keyboard.sh --only testHostKeys
#
# XCTest `typeKey` cannot press ⌘↩ or ⌘⌫ on the iPadOS 26 simulator; HID events from the
# host reach the app. With IPAD_KEYBOARD_HOST_KEYS=1 in the test runner (passed as
# TEST_RUNNER_IPAD_KEYBOARD_HOST_KEYS) `testHostKeys` runs instead of skipping. It prints
# `IPAD_KEYBOARD_HOST_KEY <n> <combo>` when it waits for a key; this script sends the combo
# with AXe (`axe key-combo`), and the test prints `IPAD_KEYBOARD_HOST_KEY_SEEN <n>` once it
# has seen what the key did.
#
# Needs: AXe on PATH (brew install cameroncooke/axe/axe); the loopback backend on
# 127.0.0.1:3001, or E2E_API_BASE (the spec registers fresh users); an iPadOS 26.2+
# simulator. Any ConnectHardwareKeyboard value, no Simulator window. Do not type on the
# Mac while it runs: the keys go to the booted simulator.
#
# Env:
#   IPAD_SIM_ID                 iPad simulator override (scripts/resolve-ipad-simulator.sh)
#   IPAD_KEYBOARD_OUT           output dir (default tmp/ipad-keyboard): build.log, test.log,
#                               keys.log, IPadKeyboardSpec.xcresult
#   IPAD_KEYBOARD_KEY_DELAY     seconds between a marker and its key (default 2)
#
# Verdict: VERIFIED only when xcodebuild passes, at least one test ran, testHostKeys
# passed (not skipped), and every key it asked for was sent and seen. FAILED otherwise
# (exit 1); INCONCLUSIVE when AXe or the backend is missing (exit 2).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_BUILD=0
ONLY=""
while (($#)); do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --only)
      [[ $# -ge 2 ]] || { echo "FAILED: --only needs a test name" >&2; exit 1; }
      ONLY="$2"
      shift
      ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "FAILED: unknown option $1" >&2
      exit 1
      ;;
  esac
  shift
done

OUT="${IPAD_KEYBOARD_OUT:-$ROOT/tmp/ipad-keyboard}"
KEY_DELAY="${IPAD_KEYBOARD_KEY_DELAY:-2}"
TEST_ID="RecipeScalerNativeUITests/IPadKeyboardSpec${ONLY:+/$ONLY}"
HOST_TEST="IPadKeyboardSpec testHostKeys"

inconclusive() {
  echo "INCONCLUSIVE: $*" >&2
  exit 2
}

failed() {
  echo "FAILED: $*" >&2
  exit 1
}

command -v axe >/dev/null 2>&1 || inconclusive "AXe is not on PATH (brew install cameroncooke/axe/axe)"

API_BASE="${E2E_API_BASE:-http://127.0.0.1:3001}"
if ! curl -s -o /dev/null --max-time 5 "$API_BASE/api/health"; then
  inconclusive "no backend at $API_BASE (the spec registers fresh users)"
fi

SIM="$(bash "$ROOT/scripts/resolve-ipad-simulator.sh")"
[[ -n "$SIM" ]] || inconclusive "no iPad simulator"
DEST="platform=iOS Simulator,id=$SIM"

mkdir -p "$OUT"
BUILD_LOG="$OUT/build.log"
TEST_LOG="$OUT/test.log"
KEYS_LOG="$OUT/keys.log"
RESULT="$OUT/IPadKeyboardSpec.xcresult"
: >"$KEYS_LOG"

if (( SKIP_BUILD )); then
  echo "== build-for-testing skipped (--skip-build): the verdict covers the last build =="
else
  echo "== build-for-testing ($SIM) → $BUILD_LOG =="
  build_status=0
  xcodebuild build-for-testing -scheme RecipeScalerNative -destination "$DEST" >"$BUILD_LOG" 2>&1 || build_status=$?
  (( build_status == 0 )) || failed "build-for-testing exit $build_status (see $BUILD_LOG)"
fi

# AXe HID usages: ⌘ 227; Return 40, Backspace 42, «2» 31.
combo_args() {
  case "$1" in
    cmd-return) echo "227 40" ;;
    cmd-delete) echo "227 42" ;;
    cmd-2) echo "227 31" ;;
    *) return 1 ;;
  esac
}

echo "== $TEST_ID with the host keys → $TEST_LOG =="
rm -rf "$RESULT"
export TEST_RUNNER_IPAD_KEYBOARD_HOST_KEYS=1
xcodebuild test-without-building -scheme RecipeScalerNative -destination "$DEST" \
  "-only-testing:$TEST_ID" -resultBundlePath "$RESULT" >"$TEST_LOG" 2>&1 &
xc_pid=$!

stop_tests() {
  kill "$xc_pid" 2>/dev/null || true
  wait "$xc_pid" 2>/dev/null || true
}

sent=0
key_error=""
while :; do
  running=0
  kill -0 "$xc_pid" 2>/dev/null && running=1
  while read -r _ step combo; do
    if ! args="$(combo_args "$combo")"; then
      key_error="unknown combo «$combo» in marker $step"
      break 2
    fi
    sleep "$KEY_DELAY"
    read -r mods key <<<"$args"
    if axe key-combo --modifiers "$mods" --key "$key" --udid "$SIM" >>"$KEYS_LOG" 2>&1; then
      echo "$step $combo sent" | tee -a "$KEYS_LOG"
    else
      key_error="axe key-combo failed for marker $step ($combo), see $KEYS_LOG"
      break 2
    fi
    sent=$((sent + 1))
  done < <(grep -E '^IPAD_KEYBOARD_HOST_KEY [0-9]+ [a-z0-9-]+$' "$TEST_LOG" | sed -n "$((sent + 1)),\$p")
  (( running )) || break
  sleep 1
done

if [[ -n "$key_error" ]]; then
  stop_tests
  failed "$key_error"
fi

test_status=0
wait "$xc_pid" || test_status=$?

grep -E "^Test Case .*(passed|failed|skipped)" "$TEST_LOG" | sed 's/^/  /' || true

(( test_status == 0 )) || failed "xcodebuild test-without-building exit $test_status (see $TEST_LOG)"

executed="$(sed -nE 's/.*Executed ([0-9]+) tests?,.*/\1/p' "$TEST_LOG" | tail -1)"
[[ -n "$executed" && "$executed" -gt 0 ]] || failed "zero tests executed (see $TEST_LOG)"

if [[ -z "$ONLY" || "$ONLY" == "testHostKeys" ]]; then
  grep -qE "Test Case '-\[[A-Za-z]+\.$HOST_TEST\]' passed" "$TEST_LOG" \
    || failed "testHostKeys did not pass (skipped or missing; see $TEST_LOG)"
  (( sent > 0 )) || failed "testHostKeys asked for no host key"
  for step in $(grep -E '^IPAD_KEYBOARD_HOST_KEY [0-9]+ ' "$TEST_LOG" | awk '{print $2}'); do
    grep -qE "^IPAD_KEYBOARD_HOST_KEY_SEEN $step\$" "$TEST_LOG" \
      || failed "host key $step was sent but the test did not see it"
  done
fi

echo "VERIFIED ipad-keyboard ($executed tests on $SIM, $sent host keys sent and seen)"
