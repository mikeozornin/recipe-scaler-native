#!/usr/bin/env bash
# Fixture self-test for scripts/verify-ipad-keyboard.sh (spec 081, US6): with fake axe,
# curl and xcodebuild on PATH, the verifier must say VERIFIED only when the host test
# passed and every key it asked for was sent and seen, and fail on a broken env or run.
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

chmod +x "$FAKE_BIN"/*
cp "$FAKE_BIN/curl" "$FAKE_BIN/xcodebuild" "$NO_AXE_BIN/"

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
  local out status=0
  out="$(env -i HOME="$HOME" PATH="$bin:/usr/bin:/bin" \
    IPAD_SIM_ID=FAKE-SIM IPAD_KEYBOARD_OUT="$TMP_DIR/out-$case_index" IPAD_KEYBOARD_KEY_DELAY=0 \
    FAKE_AXE_CALLS="$calls" "$@" bash "$SCRIPT" 2>&1)" || status=$?
  if [[ "$status" != "$want" ]]; then
    printf '%s\n' "$out" >&2
    fail "$name: exit $status, expected $want"
  fi
  if [[ "$out" != *"$needle"* ]]; then
    printf '%s\n' "$out" >&2
    fail "$name: output lacks '$needle'"
  fi
  LAST_CALLS="$calls"
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

echo "verify-ipad-keyboard self-test: all cases passed"
