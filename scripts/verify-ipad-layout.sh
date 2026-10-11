#!/usr/bin/env bash
# Spec 081 — iPad layout screenshots and the iPhone pixel-regression gate.
#
# Usage:
#   bash scripts/verify-ipad-layout.sh                       # iPad: capture every state
#   bash scripts/verify-ipad-layout.sh --iphone-regression   # iPhone: compare with the baseline
#   bash scripts/verify-ipad-layout.sh --capture-baseline    # iPhone: write the baseline
#   bash scripts/verify-ipad-layout.sh --list-states
#   bash scripts/verify-ipad-layout.sh --compare-dirs <baseline-dir> <current-dir>
#
# Options:
#   --only <state>[,<state>...]  subset of states (names from --list-states)
#   --skip-build                 reuse the app only if the build manifest matches
#                                (VERIFY_SKIP_BUILD=1, see sim-verify-lib.sh)
#   --force                      let --capture-baseline overwrite an existing baseline
#
# iPad mode (default): resolves the iPad simulator (scripts/resolve-ipad-simulator.sh,
# override IPAD_SIM_ID), builds, installs and launches each state with existing DEBUG
# launch arguments. Screenshots: tmp/ipad-verify/<step>-<state>-<orient>-<window>.png.
# The verdict is CHECKED: layout acceptance is a visual comparison with layout.md.
#
# iPhone regression: resolves the iPhone simulator (scripts/resolve-simulator.sh,
# override SIM_ID), captures the same states into tmp/ipad-verify/iphone-regression/
# and compares them pixel by pixel with tmp/ipad-verify/iphone-baseline/.
# Pixels that already changed between frames while the baseline was captured
# (timer countdown, text cursor) are stored as masks next to the baseline and ignored.
# Any other differing pixel → FAILED (exit 1); diff images go to iphone-regression/diff/.
#
# Baseline: capture it on code without spec-081 Swift changes (tasks.md T002).
# Each state is launched IPAD_VERIFY_BASELINE_PASSES times; the unstable mask is
# the union of pixels that differed between passes and settle frames (random
# assistant placeholder, glass shimmer, animated icons), dilated by
# IPAD_VERIFY_MASK_RADIUS and filled to bounding boxes. A state whose mask exceeds IPAD_VERIFY_MAX_MASK_FRACTION
# fails the capture (baseline not trustworthy). In the regression a differing state
# is relaunched IPAD_VERIFY_RETRIES times before it counts as FAILED.
#
# Data and side effects: the app runs as the shared DEBUG simulator user against
# prod data (recipes, shopping list, discover feed). -ScreenshotCapture=1 hides
# release notes / system banners and deletes that user's active timers on every
# launch; the opt-in timers state creates one 42-minute timer that the next launch
# removes.
# If the account data changes, re-capture the baseline from a clean checkout.
#
# Env:
#   IPAD_SIM_ID / SIM_ID               simulator overrides (iPad / iPhone)
#   IPAD_VERIFY_OUT                    output root (default tmp/ipad-verify)
#   IPAD_VERIFY_RECIPE_NAME            recipe opened by recipe states (default «Баскский чизкейк»)
#   IPAD_VERIFY_DISCOVER_PROFILE       public profile for discover-author (default mike.ozornin)
#   IPAD_VERIFY_MAX_DIFF_PIXELS        allowed differing pixels per state (default 0)
#   IPAD_VERIFY_CHANNEL_TOLERANCE      per-channel delta treated as equal (default 2: Liquid Glass
#                                      blur dithers ±1–2 levels between launches; layout changes are far larger)
#   IPAD_VERIFY_MASK_RADIUS            mask dilation in pixels (default 8)
#   IPAD_VERIFY_MASK_BOXES             1 = fill each unstable region to its bounding box (default 1)
#   IPAD_VERIFY_MAX_MASK_FRACTION      max masked share of a baseline frame (default 0.10)
#   IPAD_VERIFY_SETTLE_TIMEOUT         seconds to wait for a still screen (default 25)
#   IPAD_VERIFY_SETTLE_PIXELS          frame-to-frame change treated as still (default 0.5% of pixels)
#   IPAD_VERIFY_INCLUDE_TIMERS=1       add recipes-timers (needs the notification alert answered once)
#   IPAD_VERIFY_BASELINE_PASSES        launches per state when capturing the baseline (default 3)
#   IPAD_VERIFY_RETRIES                re-captures of a differing state before FAILED (default 1)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
cd "$ROOT"

MODE="ipad"
CAPTURE_BASELINE=0
FORCE=0
ONLY=""
COMPARE_BASELINE_DIR=""
COMPARE_CURRENT_DIR=""

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while (($#)); do
  case "$1" in
    --iphone-regression) MODE="iphone-regression" ;;
    --capture-baseline)
      MODE="iphone-regression"
      CAPTURE_BASELINE=1
      ;;
    --list-states) MODE="list" ;;
    --compare-dirs)
      MODE="compare-dirs"
      COMPARE_BASELINE_DIR="${2:-}"
      COMPARE_CURRENT_DIR="${3:-}"
      if [[ -z "$COMPARE_BASELINE_DIR" || -z "$COMPARE_CURRENT_DIR" ]]; then
        echo "--compare-dirs needs <baseline-dir> <current-dir>" >&2
        exit 64
      fi
      shift 2
      ;;
    --only)
      ONLY="${2:-}"
      shift
      ;;
    --skip-build) export VERIFY_SKIP_BUILD=1 ;;
    --force) FORCE=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

OUT_DIR="${IPAD_VERIFY_OUT:-$ROOT/tmp/ipad-verify}"
BASELINE_DIR="$OUT_DIR/iphone-baseline"
REGRESSION_DIR="$OUT_DIR/iphone-regression"
RECIPE_NAME="${IPAD_VERIFY_RECIPE_NAME:-Баскский чизкейк}"
DISCOVER_PROFILE="${IPAD_VERIFY_DISCOVER_PROFILE:-mike.ozornin}"
MAX_DIFF_PIXELS="${IPAD_VERIFY_MAX_DIFF_PIXELS:-0}"
MASK_RADIUS="${IPAD_VERIFY_MASK_RADIUS:-8}"
# Box-fill connected unstable regions (see scripts/ipad-verify-pixels.swift).
export IPAD_VERIFY_MASK_BOXES="${IPAD_VERIFY_MASK_BOXES:-1}"
# Read by scripts/ipad-verify-pixels.swift for diffs, masks and settle detection.
export IPAD_VERIFY_CHANNEL_TOLERANCE="${IPAD_VERIFY_CHANNEL_TOLERANCE:-2}"
MAX_MASK_FRACTION="${IPAD_VERIFY_MAX_MASK_FRACTION:-0.10}"
SETTLE_TIMEOUT="${IPAD_VERIFY_SETTLE_TIMEOUT:-25}"
BASELINE_PASSES="${IPAD_VERIFY_BASELINE_PASSES:-3}"
RETRIES="${IPAD_VERIFY_RETRIES:-1}"

# ---------------------------------------------------------------------------
# States. Names are <step>-<state> from layout.md §Карта состояний. COMMON_STATES
# use only launch arguments that already exist on master, so the iPhone baseline
# can be captured before any Swift change. States that need typing, long press, menus or
# a menu bar (recipes-search, recipes-context, recipes-collections,
# assistant-history, import-photo, menubar-*) are not reachable by arguments and
# are reviewed manually; assistant-new / profile-private depend on server data.
# recipes-tabs / recipes-focus are iPad-only (DEBUG -IPadSidebarHidden /
# -IPadListHidden, T011); on the phone they collapse into recipes-sidebar (recipe
# on top of the stack), so the iPhone regression does not list them.
# ---------------------------------------------------------------------------
COMMON_STATES=(
  recipes-list
  recipes-sidebar
  recipes-collection
  recipes-cooking
  edit-edit
  assistant-chat
  shopping-az
  discover-feed
  discover-author
  import-text
  profile-public
)
# recipes-timers starts a timer, and the first timer asks for notification
# permission. simctl cannot answer that system alert, so the state is opt-in:
# answer the alert once on the simulator, then set IPAD_VERIFY_INCLUDE_TIMERS=1
# for both the baseline and the regression runs.
if [[ "${IPAD_VERIFY_INCLUDE_TIMERS:-0}" == "1" ]]; then
  COMMON_STATES+=(recipes-timers)
fi
IPHONE_STATES=("${COMMON_STATES[@]}")
IPAD_STATES=("${COMMON_STATES[@]}" recipes-tabs recipes-focus)

STATE_ARGS=()
STATE_WAIT="ready"
STATE_NOTE=""

# Fills STATE_ARGS / STATE_WAIT / STATE_NOTE for one state. Returns 1 if unknown.
state_spec() {
  local recipe_args=("-OpenTab=recipes" "-OpenRecipeName=$RECIPE_NAME" -recipe-list-view-mode flat)
  STATE_WAIT="ready"
  case "$1" in
    recipes-list)
      STATE_NOTE="recipe list, flat mode"
      STATE_ARGS=("-OpenTab=recipes" -recipe-list-view-mode flat)
      ;;
    recipes-sidebar)
      STATE_NOTE="recipe «${RECIPE_NAME}» open (phone: on top of the stack)"
      STATE_ARGS=("${recipe_args[@]}")
      STATE_WAIT="media"
      ;;
    recipes-tabs)
      STATE_NOTE="recipe «${RECIPE_NAME}» open, sidebar hidden (iPad only)"
      STATE_ARGS=("${recipe_args[@]}" "-IPadSidebarHidden=1")
      STATE_WAIT="media"
      ;;
    recipes-focus)
      STATE_NOTE="recipe «${RECIPE_NAME}» open, sidebar and list hidden (iPad only)"
      STATE_ARGS=("${recipe_args[@]}" "-IPadSidebarHidden=1" "-IPadListHidden=1")
      STATE_WAIT="media"
      ;;
    recipes-collection)
      STATE_NOTE="recipe list in collections mode, folders grid (no argument opens one folder yet)"
      STATE_ARGS=("-OpenTab=recipes" -recipe-list-view-mode collections -recipe-collections-root-layout folders)
      ;;
    recipes-cooking)
      STATE_NOTE="recipe open, «Не гасить экран» banner"
      STATE_ARGS=("${recipe_args[@]}" "-ScreenshotScreenAwake=1")
      STATE_WAIT="media"
      ;;
    recipes-timers)
      STATE_NOTE="recipe open, one running timer, expanded timer panel"
      STATE_ARGS=("${recipe_args[@]}" "-ScreenshotTimerSeconds=2530" "-ScreenshotTimerName=Духовка" "-MobileTimerPanelExpanded=1")
      STATE_WAIT="media"
      ;;
    edit-edit)
      STATE_NOTE="recipe open in edit mode"
      STATE_ARGS=("${recipe_args[@]}" "-StartInEditMode=1")
      STATE_WAIT="media"
      ;;
    assistant-chat)
      STATE_NOTE="assistant over the open recipe, fixture chat"
      STATE_ARGS=("${recipe_args[@]}" "-ShowAssistant=1" "-ScreenshotAssistantFixture=1")
      STATE_WAIT="media"
      ;;
    shopping-az)
      STATE_NOTE="shopping list (sort mode is account data)"
      STATE_ARGS=("-OpenTab=shopping")
      ;;
    discover-feed)
      STATE_NOTE="discover feed"
      STATE_ARGS=("-OpenTab=discover")
      ;;
    discover-author)
      STATE_NOTE="public profile @$DISCOVER_PROFILE"
      STATE_ARGS=("-OpenDiscoverProfile=$DISCOVER_PROFILE")
      STATE_WAIT="media"
      ;;
    import-text)
      STATE_NOTE="import sheet, «Текст» tab"
      STATE_ARGS=("-OpenTab=import")
      STATE_WAIT="import"
      ;;
    profile-public)
      STATE_NOTE="profile tab"
      STATE_ARGS=("-OpenTab=profile")
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Pixel tool (scripts/ipad-verify-pixels.swift), compiled once per source hash.
# ---------------------------------------------------------------------------
PIXELS_BIN=""
ensure_pixel_tool() {
  local src="$ROOT/scripts/ipad-verify-pixels.swift"
  local hash
  hash="$(shasum -a 256 "$src" | cut -c1-16)"
  local tools_dir="$OUT_DIR/.tools"
  PIXELS_BIN="$tools_dir/ipad-verify-pixels-$hash"
  if [[ -x "$PIXELS_BIN" ]]; then
    return 0
  fi
  mkdir -p "$tools_dir"
  echo "== Compile pixel tool =="
  if ! xcrun swiftc -O -o "$PIXELS_BIN.tmp" "$src"; then
    echo "FAILED: cannot compile $src" >&2
    return 1
  fi
  mv "$PIXELS_BIN.tmp" "$PIXELS_BIN"
}

# Prints the `differing=` count between two PNGs (size mismatch → total pixels).
frame_change() {
  local out
  out="$("$PIXELS_BIN" diff "$1" "$2")" || {
    local status=$?
    if [[ $status -eq 2 ]]; then
      echo 999999999
      return 0
    fi
    return "$status"
  }
  sed -E 's/.*differing=([0-9]+).*/\1/' <<<"$out"
}

# ---------------------------------------------------------------------------
# Comparison (also used directly by --compare-dirs and the fixture self-test).
# ---------------------------------------------------------------------------

# compare_one <baseline-dir> <current-dir> <diff-dir> <state>
# Prints one "ok"/"FAIL" line. Returns 0 on a match, 1 when it differs or is missing.
compare_one() {
  local baseline="$1" current="$2" diff_dir="$3" name="$4"
  local base="$baseline/$name.png" cur="$current/$name.png" mask="$baseline/masks/$name.mask.png"
  if [[ ! -f "$base" ]]; then
    echo "  FAIL $name: baseline screenshot missing ($base)"
    return 1
  fi
  if [[ ! -f "$cur" ]]; then
    echo "  FAIL $name: current screenshot missing ($cur)"
    return 1
  fi
  [[ -f "$mask" ]] || mask="-"
  mkdir -p "$diff_dir"
  local result status=0
  result="$("$PIXELS_BIN" diff "$base" "$cur" "$mask" "$diff_dir/$name.diff.png")" || status=$?
  if ((status == 2)); then
    echo "  FAIL $name: $result"
    return 1
  elif ((status != 0)); then
    echo "  FAIL $name: pixel tool exited $status"
    return 1
  fi
  local differing masked total
  differing="$(sed -E 's/.*differing=([0-9]+).*/\1/' <<<"$result")"
  masked="$(sed -E 's/.*masked=([0-9]+).*/\1/' <<<"$result")"
  total="$(sed -E 's/.*total=([0-9]+).*/\1/' <<<"$result")"
  if ((differing > MAX_DIFF_PIXELS)); then
    echo "  FAIL $name: $differing differing pixels (masked $masked of $total) → $diff_dir/$name.diff.png"
    return 1
  fi
  echo "  ok   $name: $differing differing pixels (masked $masked of $total)"
  rm -f "${diff_dir:?}/${name:?}.diff.png"
}

# compare_dirs <baseline-dir> <current-dir> <diff-dir> — every baseline PNG must match.
compare_dirs() {
  local baseline="$1" current="$2" diff_dir="$3"
  local -a names=()
  local f name failed=0
  shopt -s nullglob
  for f in "$baseline"/*.png; do
    names+=("$(basename "$f" .png)")
  done
  shopt -u nullglob
  if ((${#names[@]} == 0)); then
    echo "FAILED: no baseline screenshots in $baseline (run --capture-baseline on unchanged code)" >&2
    return 1
  fi
  for name in "${names[@]}"; do
    compare_one "$baseline" "$current" "$diff_dir" "$name" || failed=1
  done
  if ((failed)); then
    echo "FAILED: iPhone regression — differences against $baseline (diffs in $diff_dir)" >&2
    return 1
  fi
  echo "VERIFIED: iPhone regression — ${#names[@]} states, 0 unmasked pixel differences (max allowed $MAX_DIFF_PIXELS)"
}

# ---------------------------------------------------------------------------
# Simulator capture
# ---------------------------------------------------------------------------
# Fills SELECTED with the states of <pool> filtered by --only. Fails on unknown names.
SELECTED=()
select_states() {
  SELECTED=()
  if [[ -z "$ONLY" ]]; then
    SELECTED=("$@")
    return 0
  fi
  local -a wanted
  local s p found
  IFS=',' read -r -a wanted <<<"$ONLY"
  for s in "${wanted[@]}"; do
    found=0
    for p in "$@"; do
      [[ "$p" == "$s" ]] && found=1
    done
    if ((!found)); then
      echo "Unknown state for this mode: $s (see --list-states)" >&2
      return 1
    fi
    SELECTED+=("$s")
  done
}

# Launches one state and waits for its readiness marker. Fails closed.
launch_state() {
  local state="$1" log="$2"
  state_spec "$state" || {
    echo "Unknown state: $state" >&2
    return 1
  }
  export LOG_FILE="$log"
  capture_override_status_bar
  sim_launch -SkipSplash=1 -ScreenshotCapture=1 -AppLanguage=ru -AppTheme=light "${STATE_ARGS[@]}" >/dev/null
  if ! sim_wait_ready 30; then
    echo "  FAIL $state: no readiness marker (app_shell_start|container_constructed|contentview_init)" >&2
    return 1
  fi
  case "$STATE_WAIT" in
    media)
      # Emitted under -ScreenshotCapture once the opened recipe / profile media loaded.
      if ! sim_wait_log_line 'screenshot_media_ready' 45; then
        echo "  FAIL $state: no screenshot_media_ready marker ($STATE_NOTE)" >&2
        return 1
      fi
      ;;
    import)
      if ! sim_wait_log_line 'screenshot_import_ready' 30; then
        echo "  FAIL $state: import sheet did not report screenshot_import_ready" >&2
        return 1
      fi
      ;;
  esac
}

# Polls screenshots until three consecutive frames change by <= settle pixels.
# Writes the final frame to <out> and keeps the last three frames in <frames_dir>.
# Returns 0 when still, 3 when it timed out (the last frame is still written).
capture_settled() {
  local out="$1" frames_dir="$2"
  rm -rf "${frames_dir:?}"
  mkdir -p "$frames_dir"
  sleep 2
  local deadline=$((SECONDS + SETTLE_TIMEOUT))
  local n=0 still=0 change prev="" cur settle_pixels="${IPAD_VERIFY_SETTLE_PIXELS:-}" w h
  while :; do
    n=$((n + 1))
    cur="$frames_dir/$n.png"
    xcrun simctl io "$SIM_ID" screenshot "$cur" >/dev/null 2>&1
    if [[ -z "$settle_pixels" ]]; then
      read -r w h < <("$PIXELS_BIN" size "$cur")
      settle_pixels=$((w * h / 200))
    fi
    if [[ -n "$prev" ]]; then
      change="$(frame_change "$prev" "$cur")"
      if ((change <= settle_pixels)); then
        still=$((still + 1))
      else
        still=0
      fi
    fi
    if ((n > 3)); then
      rm -f "${frames_dir:?}/$((n - 3)).png"
    fi
    prev="$cur"
    if ((still >= 2)); then
      cp "$cur" "$out"
      return 0
    fi
    if ((SECONDS >= deadline)); then
      cp "$cur" "$out"
      return 3
    fi
    sleep 1
  done
}

orientation_of() {
  local w h
  read -r w h < <("$PIXELS_BIN" size "$1")
  if ((w > h)); then echo landscape; else echo portrait; fi
}

# Builds in a child shell so a failing xcodebuild cannot be masked, and keeps
# the noisy output in a log file.
build_app() {
  local build_log="$OUT_DIR/.logs/build.log"
  mkdir -p "$OUT_DIR/.logs"
  echo "== Build Debug for $SIM_ID (log: $build_log) =="
  if ! SIM_ID="$SIM_ID" ROOT="$ROOT" bash -c \
    'set -euo pipefail; source "$ROOT/scripts/sim-verify-lib.sh"; sim_ensure_built' \
    >"$build_log" 2>&1; then
    tail -40 "$build_log" >&2
    echo "FAILED: build failed (full log: $build_log)" >&2
    return 1
  fi
  grep -E 'BUILD SUCCEEDED|matching build manifest' "$build_log" | tail -1 || true
}

prepare_simulator() {
  sim_prepare
  build_app
  sim_install
}

finish_simulator() {
  sim_terminate
  xcrun simctl status_bar "$SIM_ID" clear >/dev/null 2>&1 || true
}

# capture_state <state> <out.png> <frames-dir> — launch, wait, capture a still frame.
capture_state() {
  local state="$1" out="$2" frames_dir="$3"
  mkdir -p "$OUT_DIR/.logs"
  launch_state "$state" "$OUT_DIR/.logs/$state.ndjson" || return 1
  local status=0
  capture_settled "$out" "$frames_dir" || status=$?
  if ((status == 3)); then
    echo "  warn $state: screen still changing after ${SETTLE_TIMEOUT}s — kept the last frame ($STATE_NOTE)"
  elif ((status != 0)); then
    return "$status"
  else
    echo "  shot $state → $out ($STATE_NOTE)"
  fi
}

# capture_pass <dest-dir> <frames-root> state... → <dest>/<state>.png
capture_pass() {
  local dest="$1" frames_root="$2"
  shift 2
  mkdir -p "$dest" "$frames_root"
  local state failed=0
  for state in "$@"; do
    capture_state "$state" "$dest/$state.png" "$frames_root/$state" || failed=1
  done
  return "$failed"
}

run_ipad() {
  IPAD_ID="$(bash "$ROOT/scripts/resolve-ipad-simulator.sh")"
  export SIM_ID="$IPAD_ID"
  # shellcheck source=scripts/sim-capture-lib.sh
  source "$ROOT/scripts/sim-capture-lib.sh"
  ensure_pixel_tool
  select_states "${IPAD_STATES[@]}"
  local -a states=("${SELECTED[@]}")
  echo "== iPad layout capture on $SIM_ID (${#states[@]} states) =="
  prepare_simulator
  local state failed=0 tmp final
  mkdir -p "$OUT_DIR/.frames/ipad"
  for state in "${states[@]}"; do
    tmp="$OUT_DIR/.frames/ipad/$state.final.png"
    if ! capture_state "$state" "$tmp" "$OUT_DIR/.frames/ipad/$state"; then
      failed=1
      continue
    fi
    # <step>-<state>-<orient>-<window>; the window matrix arrives with T049.
    final="$OUT_DIR/$state-$(orientation_of "$tmp")-full.png"
    cp "$tmp" "$final"
    echo "       saved $final"
  done
  finish_simulator
  if ((failed)); then
    echo "FAILED: one or more iPad states did not reach readiness" >&2
    return 1
  fi
  echo "CHECKED: ${#states[@]} iPad states captured in $OUT_DIR (layout acceptance is visual — compare with layout.md)"
}

swift_dirty_count() {
  git -C "$ROOT" status --porcelain -- '*.swift' ':!scripts' 'RecipeScalerNative.xcodeproj' | wc -l | tr -d ' '
}

write_baseline_manifest() {
  local dir="$1"
  shift
  local sim_name
  sim_name="$(xcrun simctl list devices -j | python3 -c '
import json, sys
udid = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["udid"] == udid:
            print(device["name"], "(" + runtime.rsplit(".", 1)[-1] + ")")
' "$SIM_ID")"
  {
    echo "captured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "git_head=$(git -C "$ROOT" rev-parse HEAD)"
    echo "git_branch=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
    echo "swift_dirty=$(swift_dirty_count)"
    echo "simulator=$sim_name $SIM_ID"
    echo "recipe=$RECIPE_NAME"
    echo "discover_profile=$DISCOVER_PROFILE"
    echo "passes=$BASELINE_PASSES mask_radius=$MASK_RADIUS mask_boxes=$IPAD_VERIFY_MASK_BOXES channel_tolerance=$IPAD_VERIFY_CHANNEL_TOLERANCE"
    local state
    for state in "$@"; do
      state_spec "$state"
      echo "state=$state | ${STATE_ARGS[*]} | $STATE_NOTE"
    done
  } >"$dir/manifest.txt"
}

run_capture_baseline() {
  local -a states=("$@")
  if [[ -f "$BASELINE_DIR/manifest.txt" && $FORCE -ne 1 ]]; then
    echo "FAILED: baseline already exists ($BASELINE_DIR/manifest.txt). It must come from code without spec-081 Swift changes; pass --force to overwrite." >&2
    return 1
  fi
  if ((BASELINE_PASSES < 2)); then
    echo "FAILED: IPAD_VERIFY_BASELINE_PASSES must be >= 2 to detect unstable pixels" >&2
    return 1
  fi
  local dirty
  dirty="$(swift_dirty_count)"
  if ((dirty > 0)); then
    echo "  warn: $dirty uncommitted Swift/project changes — the baseline should come from unchanged code"
  fi

  local staging="$OUT_DIR/.baseline-staging" pass
  rm -rf "${staging:?}"
  for ((pass = 1; pass <= BASELINE_PASSES; pass++)); do
    echo "== Baseline pass $pass/$BASELINE_PASSES =="
    if ! capture_pass "$staging/pass$pass" "$staging/frames$pass" "${states[@]}"; then
      finish_simulator
      echo "FAILED: baseline pass $pass did not reach readiness for every state" >&2
      return 1
    fi
  done
  finish_simulator

  mkdir -p "$staging/pass1/masks"
  local state result masked total failed=0 status
  local -a frames
  for state in "${states[@]}"; do
    frames=()
    for ((pass = 2; pass <= BASELINE_PASSES; pass++)); do
      frames+=("$staging/pass$pass/$state.png")
    done
    shopt -s nullglob
    for ((pass = 1; pass <= BASELINE_PASSES; pass++)); do
      frames+=("$staging/frames$pass/$state"/*.png)
    done
    shopt -u nullglob
    status=0
    result="$("$PIXELS_BIN" mask "$staging/pass1/masks/$state.mask.png" "$MASK_RADIUS" \
      "$staging/pass1/$state.png" "${frames[@]}")" || status=$?
    if ((status != 0)); then
      echo "  FAIL $state: $result (baseline passes differ in size)"
      failed=1
      continue
    fi
    masked="$(sed -E 's/.*masked=([0-9]+).*/\1/' <<<"$result")"
    total="$(sed -E 's/.*total=([0-9]+).*/\1/' <<<"$result")"
    if python3 -c "import sys; sys.exit(0 if $masked <= $MAX_MASK_FRACTION * $total else 1)"; then
      echo "  mask $state: $masked of $total pixels unstable"
      if ((masked == 0)); then
        rm -f "${staging:?}/pass1/masks/${state:?}.mask.png"
      fi
    else
      echo "  FAIL $state: $masked of $total pixels changed between baseline passes (> $MAX_MASK_FRACTION) — data or animation is not stable"
      failed=1
    fi
  done
  if ((failed)); then
    echo "FAILED: baseline is not stable; nothing written to $BASELINE_DIR (staging kept in $staging)" >&2
    return 1
  fi

  rm -rf "${BASELINE_DIR:?}"
  mkdir -p "$BASELINE_DIR"
  cp "$staging/pass1/"*.png "$BASELINE_DIR/"
  if compgen -G "$staging/pass1/masks/*.png" >/dev/null; then
    mkdir -p "$BASELINE_DIR/masks"
    cp "$staging/pass1/masks/"*.png "$BASELINE_DIR/masks/"
  fi
  write_baseline_manifest "$BASELINE_DIR" "${states[@]}"
  rm -rf "${staging:?}"
  echo "CHECKED: iPhone baseline captured — ${#states[@]} states × $BASELINE_PASSES passes in $BASELINE_DIR (now run --iphone-regression)"
}

run_iphone_regression() {
  if [[ -z "${SIM_ID:-}" ]]; then
    SIM_ID="$(bash "$ROOT/scripts/resolve-simulator.sh")"
  fi
  export SIM_ID
  # shellcheck source=scripts/sim-capture-lib.sh
  source "$ROOT/scripts/sim-capture-lib.sh"
  ensure_pixel_tool
  select_states "${IPHONE_STATES[@]}"
  local -a states=("${SELECTED[@]}")
  local label="regression"
  ((CAPTURE_BASELINE)) && label="baseline"
  echo "== iPhone $label on $SIM_ID (${#states[@]} states) =="

  if ((!CAPTURE_BASELINE)) && [[ ! -f "$BASELINE_DIR/manifest.txt" ]]; then
    echo "FAILED: no iPhone baseline in $BASELINE_DIR — capture it with --capture-baseline on code without spec-081 Swift changes" >&2
    return 1
  fi
  prepare_simulator

  if ((CAPTURE_BASELINE)); then
    run_capture_baseline "${states[@]}"
    return $?
  fi

  rm -rf "${REGRESSION_DIR:?}"
  mkdir -p "$REGRESSION_DIR"
  local state attempt matched
  local -a failed_states=()
  for state in "${states[@]}"; do
    matched=0
    for ((attempt = 0; attempt <= RETRIES; attempt++)); do
      if ((attempt > 0)); then
        echo "  retry $state ($attempt/$RETRIES)"
      fi
      if ! capture_state "$state" "$REGRESSION_DIR/$state.png" "$OUT_DIR/.frames/iphone/$state"; then
        continue
      fi
      if compare_one "$BASELINE_DIR" "$REGRESSION_DIR" "$REGRESSION_DIR/diff" "$state"; then
        matched=1
        break
      fi
    done
    if ((!matched)); then
      failed_states+=("$state")
    fi
  done
  finish_simulator
  if ((${#failed_states[@]} > 0)); then
    echo "FAILED: iPhone regression — ${#failed_states[@]} of ${#states[@]} states differ or did not load: ${failed_states[*]} (diffs in $REGRESSION_DIR/diff)" >&2
    return 1
  fi
  echo "VERIFIED: iPhone regression — ${#states[@]} states, 0 unmasked pixel differences against $BASELINE_DIR (max allowed $MAX_DIFF_PIXELS)"
}

case "$MODE" in
  list)
    echo "iPad states:"
    for s in "${IPAD_STATES[@]}"; do
      state_spec "$s"
      printf '  %-20s %s\n' "$s" "$STATE_NOTE"
    done
    echo "iPhone regression states:"
    printf '  %s\n' "${IPHONE_STATES[@]}"
    ;;
  compare-dirs)
    ensure_pixel_tool
    compare_dirs "$COMPARE_BASELINE_DIR" "$COMPARE_CURRENT_DIR" "$COMPARE_CURRENT_DIR/diff"
    ;;
  iphone-regression)
    run_iphone_regression
    ;;
  ipad)
    run_ipad
    ;;
esac
