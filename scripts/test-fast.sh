#!/usr/bin/env bash
# Fast unit-test gate: build-for-testing once, then run RecipeScalerNativeTests
# (no UI tests). Fails if any test case exceeds MAX_TEST_SECONDS wall time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${SIM_ID:=$("$ROOT/scripts/resolve-simulator.sh")}"
: "${MAX_TEST_SECONDS:=30}"
DESTINATION="platform=iOS Simulator,id=$SIM_ID"
RESULT_BUNDLE="${RESULT_BUNDLE:-$ROOT/.test-fast-results.xcresult}"
LOG_FILE="$ROOT/.test-fast.log"

rm -rf "$RESULT_BUNDLE" "$LOG_FILE"

echo "== build-for-testing =="
xcodebuild build-for-testing \
  -scheme RecipeScalerNative \
  -destination "$DESTINATION" \
  -configuration Debug

echo "== quarantine manifest =="
python3 "$ROOT/scripts/check-test-quarantine.py" "$ROOT/scripts/test-quarantine.json"

echo "== test-without-building (unit tests only) =="
# Suites are skipped only through `scripts/test-quarantine.json` (bounded,
# owner + expiry + exitCriteria). Direct `-skip-testing` without manifest
# entry is forbidden for suite exclusions.
QUARANTINE_TARGETS=(-skip-testing:RecipeScalerNativeUITests)
while IFS= read -r line; do
  [[ -n "$line" ]] && QUARANTINE_TARGETS+=("-skip-testing:${line}")
done < <(python3 - "$ROOT/scripts/test-quarantine.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for entry in data.get("suites", []):
    print(f"{entry['target']}/{entry['class']}")
PY
)
printf '%s\n' "Quarantined suites: ${QUARANTINE_TARGETS[*]}"

set +e
set -o pipefail
xcodebuild test-without-building \
  -scheme RecipeScalerNative \
  -destination "$DESTINATION" \
  -resultBundlePath "$RESULT_BUNDLE" \
  "${QUARANTINE_TARGETS[@]}" \
  2>&1 | tee "$LOG_FILE"
test_exit=${PIPESTATUS[0]}
set +o pipefail
set -e

if grep -qE '\*\* TEST FAILED \*\*|TEST BUILD FAILED' "$LOG_FILE"; then
  echo "FAILED: unit test bundle reported failures" >&2
  exit 1
fi

if [[ "$test_exit" -ne 0 ]]; then
  echo "FAILED: xcodebuild exited $test_exit" >&2
  exit 1
fi

# Flag any single test case that exceeded the wall-time budget.
slow_tests="$(grep -E "Test Case .* passed \([0-9]+\.[0-9]+ seconds\)" "$LOG_FILE" \
  | awk -v max="$MAX_TEST_SECONDS" '{
      if (match($0, /passed \([0-9]+\.[0-9]+ seconds\)/)) {
        s = substr($0, RSTART + 8, RLENGTH - 17)
        if (s + 0 > max + 0) print $0
      }
    }' || true)"

if [[ -n "$slow_tests" ]]; then
  echo "FAILED: test(s) exceeded ${MAX_TEST_SECONDS}s budget:" >&2
  echo "$slow_tests" >&2
  exit 1
fi

executed_line="$(grep -E 'Executed [0-9]+ test' "$LOG_FILE" | tail -1 || true)"
executed_count="$(printf '%s\n' "$executed_line" | sed -nE 's/.*Executed ([0-9]+) test.*/\1/p' | tail -1)"
if [[ -z "$executed_count" || "$executed_count" -le 0 ]]; then
  echo "FAILED: zero tests executed (false-green)" >&2
  exit 1
fi
echo "VERIFIED test-fast ($executed_line, max ${MAX_TEST_SECONDS}s per case)"
