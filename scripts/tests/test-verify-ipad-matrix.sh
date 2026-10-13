#!/usr/bin/env bash
# Fixture self-test for scripts/verify-ipad-matrix.sh (spec 081, US7, T049): with fake curl,
# xcodebuild and xcrun on PATH, the verifier must say VERIFIED only when the tests passed,
# none skipped, and every screenshot they asked for was taken and answered; it must fail on
# a broken env or run. `verify-ipad-layout.sh --matrix` must reach the same verifier.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/verify-ipad-matrix.sh"
LAYOUT_SCRIPT="$REPO_ROOT/scripts/verify-ipad-layout.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SIM="11111111-2222-3333-4444-555555555555"
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

cat >"$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
exit "${FAKE_CURL_STATUS:-0}"
SH

# simctl list / io screenshot / spawn notifyutil. Each answered marker («-s <name> <n>»)
# is a line in FAKE_ANSWERS; FAKE_SHOT_STATUS and FAKE_NOTIFY_STATUS break a step.
cat >"$FAKE_BIN/xcrun" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "simctl" ]] || exit 64
shift
case "$1" in
  list)
    echo "-- iOS 26.3 --"
    [[ -n "${FAKE_NO_DEVICE:-}" ]] || echo "    iPad Pro 11-inch (M4) ($FAKE_SIM) (Booted) "
    ;;
  io)
    [[ "$2" == "$FAKE_SIM" && "$3" == "screenshot" ]] || exit 64
    [[ "${FAKE_SHOT_STATUS:-0}" == 0 ]] || exit "$FAKE_SHOT_STATUS"
    # A 1×2 portrait buffer, as simctl gives for any orientation; FAKE_BROKEN_PNG: not an image.
    if [[ -n "${FAKE_BROKEN_PNG:-}" ]]; then
      : >"$4"
    else
      echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAACAQAAAACx+ouKAAAADElEQVQI12NoYGgAAAIEAQEcETK/AAAAAElFTkSuQmCC" | base64 -D >"$4"
    fi
    ;;
  spawn)
    [[ "$2" == "$FAKE_SIM" && "$3" == "notifyutil" ]] || exit 64
    [[ "${FAKE_NOTIFY_STATUS:-0}" == 0 ]] || exit "$FAKE_NOTIFY_STATUS"
    if [[ "$4" == "-s" ]]; then
      [[ "$5" == "ru.recipescaler.debug.matrix-shot" ]] || exit 64
      echo "$6" >>"$FAKE_ANSWERS"
    fi
    ;;
  *) exit 64 ;;
esac
SH

# Plays one test run. FAKE_MODE: pass | skip | zero | fail. FAKE_MARKERS:
# "1 01-recipes-tabs-landscape-full1194,2 ..." — each marker waits for its answer, then
# the test sees it unless it is FAKE_UNSEEN.
cat >"$FAKE_BIN/xcodebuild" <<'SH'
#!/usr/bin/env bash
case "$1" in
  build-for-testing) exit "${FAKE_BUILD_STATUS:-0}" ;;
  test-without-building) ;;
  *) exit 64 ;;
esac
[[ "${TEST_RUNNER_IPAD_MATRIX_SHOTS:-}" == 1 ]] || exit 70
[[ " $* " == *" -only-testing:RecipeScalerNativeUITests/IPadMultitaskingSpec"* ]] || exit 71
test_case="Test Case '-[RecipeScalerNativeUITests.IPadMultitaskingSpec testRecipesWidthsLandscape]'"
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
  echo "IPAD_MATRIX_ROW ${marker#* } root=1194 bar=top list=398 columns=2"
  echo "IPAD_MATRIX_SHOT $marker"
  count=$((count + 1))
  for _ in $(seq 1 100); do
    [[ -f "$FAKE_ANSWERS" && "$(wc -l <"$FAKE_ANSWERS")" -ge "$count" ]] && break
    sleep 0.1
  done
  [[ "${marker%% *}" == "${FAKE_UNSEEN:-}" ]] || echo "IPAD_MATRIX_SHOT_TAKEN ${marker%% *}"
done
echo "$test_case passed (1.0 seconds)."
echo "Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.0) seconds"
SH

chmod +x "$FAKE_BIN"/*

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

case_index=0
# expect <exit-code> <needle> <case-name> <script> -- VAR=value... [-- script args...]
expect() {
  local want="$1" needle="$2" name="$3" script="$4"
  shift 5
  local vars=() args=()
  while (($#)) && [[ "$1" != "--" ]]; do vars+=("$1"); shift; done
  (($#)) && shift
  args=("$@")
  case_index=$((case_index + 1))
  LAST_OUT="$TMP_DIR/out-$case_index"
  LAST_ANSWERS="$TMP_DIR/answers-$case_index"
  local out status=0
  out="$(env -i HOME="$HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    IPAD_SIM_ID="$SIM" FAKE_SIM="$SIM" IPAD_MATRIX_OUT="$LAST_OUT" IPAD_MATRIX_SHOT_DELAY=0 \
    FAKE_ANSWERS="$LAST_ANSWERS" ${vars[@]+"${vars[@]}"} bash "$script" ${args[@]+"${args[@]}"} 2>&1)" || status=$?
  if [[ "$status" != "$want" ]]; then
    printf '%s\n' "$out" >&2
    fail "$name: exit $status, expected $want"
  fi
  if [[ "$out" != *"$needle"* ]]; then
    printf '%s\n' "$out" >&2
    fail "$name: output lacks '$needle'"
  fi
  echo "PASS: $name"
}

TWO="1 01-recipes-tabs-landscape-full1194,2 02-recipes-tabs-portrait-536of834"

expect 2 "INCONCLUSIVE: no backend" "backend down" "$SCRIPT" -- FAKE_CURL_STATUS=7
expect 2 "is not in simctl list" "unknown simulator" "$SCRIPT" -- FAKE_NO_DEVICE=1
expect 1 "FAILED: build-for-testing exit 65" "build fails" "$SCRIPT" -- FAKE_BUILD_STATUS=65
expect 1 "FAILED: xcodebuild test-without-building exit 65" "tests fail" "$SCRIPT" -- FAKE_MODE=fail
expect 1 "FAILED: zero tests executed" "zero tests" "$SCRIPT" -- FAKE_MODE=zero
expect 1 "FAILED: a test skipped" "test skipped" "$SCRIPT" -- FAKE_MODE=skip
expect 1 "FAILED: simctl io screenshot failed for marker 1" "screenshot fails" "$SCRIPT" -- \
  FAKE_MARKERS="$TWO" FAKE_SHOT_STATUS=1
expect 1 "FAILED: could not turn screenshot 1 (01-recipes-tabs-landscape-full1194) upright" "broken screenshot" "$SCRIPT" -- \
  FAKE_MARKERS="$TWO" FAKE_BROKEN_PNG=1
expect 1 "FAILED: notifyutil could not answer marker 1" "notifyutil fails" "$SCRIPT" -- \
  FAKE_MARKERS="$TWO" FAKE_NOTIFY_STATUS=1
expect 1 "FAILED: screenshot 2 was taken but the test did not see the answer" "answer not seen" "$SCRIPT" -- \
  FAKE_MARKERS="$TWO" FAKE_UNSEEN=2
expect 1 "FAILED: the tests asked for no screenshot" "no screenshots asked" "$SCRIPT" --

expect 0 "VERIFIED ipad-matrix (1 tests on iPad Pro 11-inch (M4), 2 screenshots" "screenshots taken and seen" \
  "$SCRIPT" -- FAKE_MARKERS="$TWO" -- --skip-build
shots="$LAST_OUT/ipad-pro-11-inch-m4"
for file in 01-recipes-tabs-landscape-full1194.png 02-recipes-tabs-portrait-536of834.png; do
  [[ -f "$shots/$file" ]] || fail "screenshot $file missing from $shots"
done
size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/ {printf "%s", (n++ ? "x" : "") $2}'; }
[[ "$(size "$shots/01-recipes-tabs-landscape-full1194.png")" == "2x1" ]] || fail "the landscape shot was not turned upright"
[[ "$(size "$shots/02-recipes-tabs-portrait-536of834.png")" == "1x2" ]] || fail "the portrait shot was turned"

[[ "$(cat "$LAST_ANSWERS")" == $'1\n2' ]] || fail "answers: «$(cat "$LAST_ANSWERS")», expected 1 then 2"
grep -q "^02-recipes-tabs-portrait-536of834 root=1194 bar=top list=398 columns=2$" "$shots/matrix.txt" \
  || fail "matrix.txt lacks the measured row: $(cat "$shots/matrix.txt")"
echo "PASS: screenshots per device, landscape upright, answers in order, the layout table"

expect 0 "VERIFIED ipad-matrix" "verify-ipad-layout.sh --matrix runs the matrix" \
  "$LAYOUT_SCRIPT" -- FAKE_MARKERS="$TWO" -- --matrix --skip-build

echo "verify-ipad-matrix self-test: all cases passed"
