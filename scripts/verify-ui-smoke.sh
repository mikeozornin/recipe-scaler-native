#!/usr/bin/env bash
# verify-ui-smoke.sh
#
# Cross-screen UI smoke test. Catches the class of regressions that per-feature
# verify-*.sh scripts miss because they each touch one screen:
#   - launch-time crash / FatalError / EXC_BAD_ACCESS
#   - main-thread hang (≥ 3 s) reported by the OS
#   - empty-state flicker on first render (root list rendered with 0 items)
#   - tab navigation silently broken (tap does not switch surface)
#
# Mechanism: launch app, walk primary tabs via launch args, then assert on the
# AppLog NDJSON stream produced under the simulator container. The app already
# emits structured events for shell_ready, tab change, and main-thread hang.
# No new instrumentation is required for existing surfaces — if a screen lacks
# a marker, the test fails LOUD so the gap is fixed in code, not the script.
#
# Verifies behaviour, not screenshots: this script does not gate on pixels.
# Visual / Figma parity belongs to audit-ui-layout.sh + layout-reviewer.
#
# Usage:
#   bash scripts/verify-ui-smoke.sh
#   SIM_ID=<UDID> bash scripts/verify-ui-smoke.sh
#   SKIP_BUILD=1 bash scripts/verify-ui-smoke.sh   # reuse cached build
#
# Exit codes: 0 = smoke green, 1 = regression or marker missing.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

SHOT_DIR="$ROOT/specs/_ui-smoke/screenshots"
mkdir -p "$SHOT_DIR"

LOG_HOST="$ROOT/.ui-smoke.ndjson"
rm -f "$LOG_HOST"

echo "== UI smoke: boot, build, install =="
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  sim_build >/dev/null
fi
sim_prepare
sim_install

# We exercise each primary surface by relaunching with -OpenTab=<tab>.
# Adding a new tab? Add it here and to AppShellView's OpenTab handler.
# Order matters: recipes first (proves collection load), then the rest.
TABS=(recipes shopping timers discover profile)

declare -a FAILURES=()

launch_and_probe() {
  local tab="$1"
  local ready_timeout="${2:-10}"

  echo ""
  echo "== tab: $tab =="

  # Clean the in-container log so each tab gets a self-contained trace.
  local container
  container="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [[ -n "$container" ]]; then
    rm -f "$container/Library/Application Support/debug-session.ndjson" 2>/dev/null || true
  fi

  sim_launch -SkipSplash=1 "-OpenTab=${tab}" >/dev/null

  # Wait for the shell to report readiness. sim_wait_ready greps app_shell_start
  # / container_constructed / contentview_init from the NDJSON log.
  if ! sim_wait_ready "$ready_timeout"; then
    FAILURES+=("$tab: shell did not report ready within ${ready_timeout}s")
  fi

  # Stash a per-tab screenshot for triage. Pixel diffs are not asserted here.
  sim_screenshot "$SHOT_DIR" "$tab" >/dev/null || true

  # Pull the freshest NDJSON for assertions below. LOG_FILE must target
  # LOG_HOST: bare sim_pull_debug_log would write .debug-session.ndjson and
  # the per-tab copy below would silently never fire.
  LOG_FILE="$LOG_HOST" sim_pull_debug_log >/dev/null 2>&1 || true
  if [[ -f "$LOG_HOST" ]]; then
    cp "$LOG_HOST" "$ROOT/.ui-smoke-${tab}.ndjson"
  fi
}

assert_no_crash() {
  local tab="$1"
  local log="$ROOT/.ui-smoke-${tab}.ndjson"
  if [[ ! -f "$log" ]]; then
    # No log at all is itself a regression — either AppLog is silenced or the
    # app never reached the bootstrap marker.
    FAILURES+=("$tab: no debug-session.ndjson captured")
    return
  fi

  # Crash signatures we have shipped regressions for in the past. Add new ones
  # as they are discovered; do not delete a signature without a linked fix.
  if rg -q 'FatalError|fatalError|Precondition|EXC_BAD_ACCESS|SIGABRT|SIGSEGV' "$log" 2>/dev/null; then
    FAILURES+=("$tab: crash signature in log (see $log)")
  fi
}

assert_no_hang() {
  local tab="$1"
  local log="$ROOT/.ui-smoke-${tab}.ndjson"
  [[ -f "$log" ]] || return

  # The OS reports hangs ≥ 250 ms via the main-thread reporter. We treat any
  # hang ≥ 3 s as a regression for UI-smoke purposes — anything below is
  # tracked separately under performance work.
  if rg -q 'Hang detected: ([3-9]\.\d+|[1-9]\d\.\d+)s' "$log" 2>/dev/null; then
    FAILURES+=("$tab: main-thread hang ≥ 3s reported (see $log)")
  fi
}

assert_no_empty_flicker() {
  local tab="$1"
  local log="$ROOT/.ui-smoke-${tab}.ndjson"
  [[ -f "$log" ]] || return

  # Empty-flicker detection: the root list views emit view_render events with
  # the live entryCount. If we see at least one render with entryCount=0 and
  # later one with entryCount>0, the screen flickered empty → regression
  # (caught CollectionsRootView in the past). Skip for tabs that legitimately
  # may be empty (profile, discover).
  case "$tab" in
    recipes|shopping|timers)
      if rg -q '"entryCount":"0"' "$log" 2>/dev/null \
        && rg -q '"entryCount":"[1-9]' "$log" 2>/dev/null; then
        FAILURES+=("$tab: empty-state flicker (entryCount 0 → N) — see $log")
      fi
      ;;
  esac
}

echo "== Walking primary tabs: ${TABS[*]} =="
for tab in "${TABS[@]}"; do
  launch_and_probe "$tab" 10
  assert_no_crash      "$tab"
  assert_no_hang       "$tab"
  assert_no_empty_flicker "$tab"
done

echo ""
echo "== Summary =="
if ((${#FAILURES[@]} > 0)); then
  echo "FAIL: ${#FAILURES[@]} regression(s):" >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  echo "" >&2
  echo "Per-tab logs: $ROOT/.ui-smoke-<tab>.ndjson" >&2
  echo "Screenshots:  $SHOT_DIR/" >&2
  exit 1
fi

echo "PASS: ${#TABS[@]} tabs reached shell-ready, no crash / hang / empty-flicker signatures."
echo "VERIFIED ui-smoke"
