#!/usr/bin/env bash
# Fixture self-test for scripts/verify-ipad-keyboard.sh (spec 081, US6): with fake axe,
# curl, xcodebuild and xcrun on PATH, the verifier must say VERIFIED only when the host test
# passed and every key it asked for was sent and seen, and fail on a broken env or run. It
# must read the simulator's keyboard preferences before the spec and put them back after.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/verify-ipad-keyboard.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
NO_AXE_BIN="$TMP_DIR/bin-no-axe"
mkdir -p "$FAKE_BIN" "$NO_AXE_BIN"

cat >"$FAKE_BIN/axe" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_AXE_CALLS"
exit "${FAKE_AXE_STATUS:-0}"
SH

cat >"$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
exit "${FAKE_CURL_STATUS:-0}"
SH

# Plays one test run. FAKE_MODE: pass | skip | zero | fail. FAKE_MARKERS:
# "1 cmd-delete,2 cmd-return" — each marker waits for the matching axe call, then the
# test "sees" the key unless it is FAKE_UNSEEN.
cat >"$FAKE_BIN/xcodebuild" <<'SH'
#!/usr/bin/env bash
echo "xcodebuild $1" >>"$FAKE_TOOL_CALLS"
case "$1" in
  build-for-testing) exit "${FAKE_BUILD_STATUS:-0}" ;;
  test-without-building) ;;
  *) exit 64 ;;
esac
[[ "${IPAD_KEYBOARD_HOST_KEYS:-}${TEST_RUNNER_IPAD_KEYBOARD_HOST_KEYS:-}" == *1* ]] || exit 70
test_case="Test Case '-[RecipeScalerNativeUITests.IPadKeyboardSpec testHostKeys]'"
case "${FAKE_MODE:-pass}" in
  fail) echo "$test_case failed (1.0 seconds)."; exit 65 ;;
  zero) echo "Executed 0 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds"; exit 0 ;;
  skip)
    echo "$test_case skipped (0.1 seconds)."
    echo "Executed 1 test, with 0 failures (0 unexpected) in 0.1 (0.1) seconds"
    exit 0
    ;;
esac
count=0
IFS=',' read -ra markers <<<"${FAKE_MARKERS:-}"
for marker in "${markers[@]}"; do
  echo "IPAD_KEYBOARD_HOST_KEY $marker"
  count=$((count + 1))
  for _ in $(seq 1 100); do
    [[ -f "$FAKE_AXE_CALLS" && "$(wc -l <"$FAKE_AXE_CALLS")" -ge "$count" ]] && break
    sleep 0.1
  done
  [[ "${marker%% *}" == "${FAKE_UNSEEN:-}" ]] || echo "IPAD_KEYBOARD_HOST_KEY_SEEN ${marker%% *}"
done
echo "$test_case passed (1.0 seconds)."
echo "Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.0) seconds"
SH

# simctl as far as the verifier uses it. FAKE_PREFS: "AutomaticMinimizationEnabled=1 …" —
# a key not listed does not exist. FAKE_SIMCTL_STATUS: every simctl call fails with it, as
# for a simulator that is not booted.
cat >"$FAKE_BIN/xcrun" <<'SH'
#!/usr/bin/env bash
echo "xcrun $*" >>"$FAKE_TOOL_CALLS"
if [[ -n "${FAKE_SIMCTL_STATUS:-}" ]]; then
  echo "Invalid device: $3" >&2
  exit "$FAKE_SIMCTL_STATUS"
fi
case "$1 $2" in
  "simctl bootstatus") exit 0 ;;
  "simctl spawn") shift 3 ;;
  *) exit 64 ;;
esac
[[ "$1" == defaults ]] || exit 64
case "$2" in
  read)
    for pair in ${FAKE_PREFS:-}; do
      [[ "${pair%%=*}" == "$4" ]] && { echo "${pair#*=}"; exit 0; }
    done
    echo "The domain/default pair of ($3, $4) does not exist" >&2
    exit 1
    ;;
  write | delete) exit 0 ;;
esac
exit 64
SH

chmod +x "$FAKE_BIN"/*
cp "$FAKE_BIN/curl" "$FAKE_BIN/xcodebuild" "$FAKE_BIN/xcrun" "$NO_AXE_BIN/"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

case_index=0
# expect <exit-code> <needle> <case-name> <bin-dir> -- VAR=value...
expect() {
  local want="$1" needle="$2" name="$3" bin="$4"
  shift 5
  case_index=$((case_index + 1))
  local calls="$TMP_DIR/axe-calls-$case_index"
  local tools="$TMP_DIR/tool-calls-$case_index"
  local out status=0
  out="$(env -i HOME="$HOME" PATH="$bin:/usr/bin:/bin" \
    IPAD_SIM_ID=FAKE-SIM IPAD_KEYBOARD_OUT="$TMP_DIR/out-$case_index" IPAD_KEYBOARD_KEY_DELAY=0 \
    FAKE_AXE_CALLS="$calls" FAKE_TOOL_CALLS="$tools" "$@" bash "$SCRIPT" 2>&1)" || status=$?
  if [[ "$status" != "$want" ]]; then
    printf '%s\n' "$out" >&2
    fail "$name: exit $status, expected $want"
  fi
  if [[ "$out" != *"$needle"* ]]; then
    printf '%s\n' "$out" >&2
    fail "$name: output lacks '$needle'"
  fi
  LAST_CALLS="$calls"
  LAST_TOOLS="$tools"
  echo "PASS: $name"
}

expect 2 "INCONCLUSIVE: AXe" "no axe on PATH" "$NO_AXE_BIN" --
expect 2 "INCONCLUSIVE: no backend" "backend down" "$FAKE_BIN" -- FAKE_CURL_STATUS=7
expect 1 "FAILED: build-for-testing exit 65" "build fails" "$FAKE_BIN" -- FAKE_BUILD_STATUS=65
expect 1 "FAILED: xcodebuild test-without-building exit 65" "tests fail" "$FAKE_BIN" -- FAKE_MODE=fail
expect 1 "FAILED: zero tests executed" "zero tests" "$FAKE_BIN" -- FAKE_MODE=zero
expect 1 "FAILED: testHostKeys did not pass" "host test skipped" "$FAKE_BIN" -- FAKE_MODE=skip
expect 1 "FAILED: axe key-combo failed for marker 1" "axe fails" "$FAKE_BIN" -- \
  FAKE_MARKERS="1 cmd-delete" FAKE_AXE_STATUS=1
expect 1 "FAILED: unknown combo «cmd-x» in marker 1" "unknown combo" "$FAKE_BIN" -- \
  FAKE_MARKERS="1 cmd-x"
expect 1 "FAILED: host key 2 was sent but the test did not see it" "key not seen" "$FAKE_BIN" -- \
  FAKE_UNSEEN=2 FAKE_MARKERS="1 cmd-delete,2 cmd-return"
expect 1 "FAILED: testHostKeys asked for no host key" "no keys asked" "$FAKE_BIN" --

expect 0 "VERIFIED ipad-keyboard (1 tests on FAKE-SIM, 3 host keys sent and seen)" "host keys sent and seen" \
  "$FAKE_BIN" -- FAKE_MARKERS="1 cmd-delete,2 cmd-2,3 cmd-return"
want_calls=$'key-combo --modifiers 227 --key 42 --udid FAKE-SIM\nkey-combo --modifiers 227 --key 31 --udid FAKE-SIM\nkey-combo --modifiers 227 --key 40 --udid FAKE-SIM'
[[ "$(cat "$LAST_CALLS")" == "$want_calls" ]] || fail "host keys: axe got «$(cat "$LAST_CALLS")»"
echo "PASS: axe got ⌘⌫, ⌘2, ⌘↩ in order"

PREFS="xcrun simctl spawn FAKE-SIM defaults"
DOMAIN=com.apple.keyboard.preferences
expect 0 "keyboard preferences put back: AutomaticMinimizationEnabled=0 HardwareKeyboardLastSeen=absent" \
  "the keyboard preferences are read before the spec and put back after it" "$FAKE_BIN" -- \
  FAKE_MARKERS="1 cmd-delete" FAKE_PREFS="AutomaticMinimizationEnabled=0"
want_tools="xcodebuild build-for-testing
xcrun simctl bootstatus FAKE-SIM -b
$PREFS read $DOMAIN AutomaticMinimizationEnabled
$PREFS read $DOMAIN HardwareKeyboardLastSeen
xcodebuild test-without-building
$PREFS write $DOMAIN AutomaticMinimizationEnabled -bool NO
$PREFS delete $DOMAIN HardwareKeyboardLastSeen"
[[ "$(cat "$LAST_TOOLS")" == "$want_tools" ]] || fail "keyboard preferences: calls were «$(cat "$LAST_TOOLS")»"
echo "PASS: read before xcodebuild, the off key written back, the missing key deleted"

expect 1 "keyboard preferences put back: AutomaticMinimizationEnabled=1 HardwareKeyboardLastSeen=1" \
  "a failed run puts the keyboard preferences back" "$FAKE_BIN" -- \
  FAKE_MODE=fail FAKE_PREFS="AutomaticMinimizationEnabled=1 HardwareKeyboardLastSeen=1"
grep -qx "$PREFS write $DOMAIN AutomaticMinimizationEnabled -bool YES" "$LAST_TOOLS" \
  || fail "a failed run: AutomaticMinimizationEnabled was not written back"

expect 1 "FAILED: xcodebuild test-without-building exit 65" "unreadable preferences are left alone" "$FAKE_BIN" -- \
  FAKE_MODE=fail FAKE_SIMCTL_STATUS=148
if grep -qE "defaults (write|delete)" "$LAST_TOOLS"; then
  fail "unreadable preferences: the verifier wrote «$(grep -E "defaults (write|delete)" "$LAST_TOOLS")»"
fi
echo "PASS: nothing written when the keys cannot be read"

echo "verify-ipad-keyboard self-test: all cases passed"
