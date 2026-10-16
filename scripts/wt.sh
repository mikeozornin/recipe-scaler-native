#!/usr/bin/env bash
# Parallel work: one git worktree + branch + pair of simulators per task (see AGENTS.md).
#
# Usage: bash scripts/wt.sh new <name> [base]   # ../recipe-scaler-native-wt/<name> on feature/<name> (from base, default master)
#                                               #   + sims RS-<name> (iPhone 17 Pro) and RS-<name>-ipad (iPad Pro 11" M4)
#        bash scripts/wt.sh run [--ipad] [args]  # inside a worktree: build, install and launch on RS-<name>
#                                               #   (or RS-<name>-ipad); args go to the app, e.g. -SkipSplash=1
#        bash scripts/wt.sh rm <name>           # remove worktree, its DerivedData and both simulators (branch is kept)
#        bash scripts/wt.sh ls
#        bash scripts/wt.sh udid [iphone|ipad] [name]  # simulator UDID (creates a missing one); used by resolve-*-simulator.sh
#        bash scripts/wt.sh inside              # exit 0 when this copy of the script lives in a feature worktree
set -euo pipefail
MAIN="$(dirname "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)")"
TOP="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
WT_ROOT="$(dirname "$MAIN")/recipe-scaler-native-wt"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
MIN_FREE_GB="${WT_MIN_FREE_GB:-8}"

# shellcheck source=scripts/xcode-derived-data-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/xcode-derived-data-lib.sh"

die() { echo "wt: $*" >&2; exit 1; }
check_name() { [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "name must be lowercase letters, digits, dashes"; }
# Exact name match: "RS-foo (" never matches "RS-foo-ipad (".
sim_udid() { xcrun simctl list devices | grep -E "^ +RS-$1 \(" | grep -oE '[0-9A-F-]{36}' | head -1 || true; }
# Simulator name suffix for a task and device: <name> for the iPhone, <name>-ipad for the iPad.
sim_suffix() {
  case "$2" in
    iphone) echo "$1" ;;
    ipad)   echo "$1-ipad" ;;
    *)      die "device must be iphone or ipad, not '$2'" ;;
  esac
}
latest_ios_runtime() { xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | sort -V | tail -1; }
device_type() {
  local types; types="$(xcrun simctl list devicetypes)"
  case "$1" in
    iphone) echo com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro ;;
    # Same preference as resolve-ipad-simulator.sh: iPad Pro 11" (M4), else the newest iPad Air 11".
    ipad)   { grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.iPad-Pro-11-inch-M4-8GB' <<<"$types" \
                || grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.iPad-Air-11-inch[A-Za-z0-9-]*' <<<"$types" | sort -V | tail -1; } | head -1 ;;
  esac
}
# Creates RS-<name>[-ipad] if missing; prints its UDID.
ensure_sim() {
  local suffix; suffix="$(sim_suffix "$1" "$2")"
  local udid; udid="$(sim_udid "$suffix")"
  if [[ -z "$udid" ]]; then
    local type; type="$(device_type "$2")"
    [[ -n "$type" ]] || die "no $2 device type in Xcode"
    udid="$(xcrun simctl create "RS-$suffix" "$type" "$(latest_ios_runtime)")"
    echo "wt: created simulator RS-$suffix" >&2
  fi
  echo "$udid"
}
is_inside() { [[ "$(dirname "$TOP")" == "$WT_ROOT" ]]; }
# The worktree this script lives in, unless a name is given.
current_name() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    is_inside || die "not inside a feature worktree; pass a name"
    name="$(basename "$TOP")"
  fi
  check_name "$name"
  echo "$name"
}
check_disk() {
  local free; free="$(df -g "$MAIN" | awk 'NR==2 {print $4}')"
  (( free >= MIN_FREE_GB )) || die "only ${free} GB free, need ${MIN_FREE_GB}+ GB (a build takes several GB)"
}
cmd_new() {
  local name="${1:-}" base="${2:-master}"; check_name "$name"
  # RS-foo-ipad is task foo's iPad; a task named foo-ipad would take the same simulator name.
  [[ "$name" == *-ipad ]] && die "name must not end in -ipad (reserved for the iPad simulator)"
  local dir="$WT_ROOT/$name" branch="feature/$name"
  [[ -e "$dir" ]] && die "$dir already exists"
  check_disk
  mkdir -p "$WT_ROOT"
  if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$MAIN" worktree add "$dir" "$branch"
  else
    git -C "$MAIN" worktree add -b "$branch" "$dir" "$base"
  fi
  ensure_sim "$name" iphone >/dev/null
  ensure_sim "$name" ipad >/dev/null
  echo "wt: ready — folder $dir, branch $branch, simulators RS-$name and RS-$name-ipad"
}

cmd_run() {
  local device="${WT_DEVICE:-iphone}"
  case "${1:-}" in
    --ipad) device=ipad; shift ;;
    --iphone) device=iphone; shift ;;
  esac
  local name; name="$(current_name)"
  check_disk
  # Older worktrees may miss a simulator: it's created on first use.
  SIM_ID="$(ensure_sim "$name" "$device")"
  # shellcheck source=scripts/sim-verify-lib.sh
  source "$TOP/scripts/sim-verify-lib.sh"
  sim_build -quiet
  sim_prepare
  open -a Simulator --args -CurrentDeviceUDID "$SIM_ID"
  sim_install
  sim_launch "$@" >/dev/null
  echo "wt: running on RS-$(sim_suffix "$name" "$device") ($SIM_ID)"
}

cmd_rm() {
  local name="${1:-}"; check_name "$name"
  local dir="$WT_ROOT/$name"
  if [[ -d "$dir" ]]; then
    # Refuses if there are uncommitted changes.
    git -C "$MAIN" worktree remove "$dir"
  fi
  # Xcode keeps one DerivedData folder per project path; drop the ones built from this worktree.
  local d
  while IFS= read -r -d '' d; do rm -rf "$d"; done < <(xcode_derived_data_of "$dir" "$DERIVED_DATA")
  local device udid
  for device in iphone ipad; do
    udid="$(sim_udid "$(sim_suffix "$name" "$device")")"
    [[ -n "$udid" ]] || continue
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    xcrun simctl delete "$udid"
  done
  echo "wt: removed $name (branch feature/$name kept; delete with: git branch -d feature/$name)"
}

cmd_udid() {
  local device="${1:-iphone}"
  local name; name="$(current_name "${2:-}")"
  ensure_sim "$name" "$device"
}

cmd_ls() {
  git -C "$MAIN" worktree list
  xcrun simctl list devices | grep -E '^ +RS-' || true
}

case "${1:-}" in
  new) shift; cmd_new "$@" ;;
  run) shift; cmd_run "$@" ;;
  rm)  shift; cmd_rm "$@" ;;
  udid) shift; cmd_udid "$@" ;;
  inside) is_inside ;;
  checkdisk) check_disk ;;
  ls)  cmd_ls ;;
  *)   sed -n '2,11p' "$0"; exit 1 ;;
esac
