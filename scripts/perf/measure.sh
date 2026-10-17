#!/usr/bin/env bash
# Repeatable responsiveness numbers for one build of the app on the worktree simulator.
#
# Usage: bash scripts/perf/measure.sh <path/to/RecipeScalerNative.app> <label> [runs]
#
# Needs a build with PerfMark (Utils/AppLog.swift) and an account with recipes; Debug builds
# sign the debug user in by themselves. Build with -O so the numbers resemble Release:
#   xcodebuild ... -configuration Debug SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule
# The DEBUG file journal is switched off for every run, so DEBUG-only costs don't count.
#
# Writes tmp/perf/<label>/:
#   launch.tsv    cold launches: ms since process start to shell / data loaded / list on screen
#   open.tsv      recipe opens by deep link: ms from navigation to content (first and repeat open)
#   launch.trace, open.trace, scroll.trace   Time Profiler recordings (main thread CPU, hangs)
#   summary.txt   medians and trace totals
set -euo pipefail

APP=${1:?usage: measure.sh <App.app> <label> [runs]}
LABEL=${2:?usage: measure.sh <App.app> <label> [runs]}
RUNS=${3:-5}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SIM="$(bash "$ROOT/scripts/resolve-simulator.sh")"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
OUT="$ROOT/tmp/perf/$LABEL"
SWIPE_X=${SWIPE_X:-200}
mkdir -p "$OUT"
rm -f "$OUT"/launch.tsv "$OUT"/open.tsv
rm -rf "$OUT"/*.trace

export SIMCTL_CHILD_AGENT_DEBUG_LOG_DISABLED=1

xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl install "$SIM" "$APP"

perf_lines() {
  xcrun simctl spawn "$SIM" log show --start "$1" --style compact \
    --predicate 'subsystem == "com.recipescaler.native" AND category == "perf"' 2>/dev/null \
    | grep -oE 'perf_(mark|interval) .*' || true
}

now() { date '+%Y-%m-%d %H:%M:%S'; }

relaunch() {
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$SIM" "$BUNDLE" | awk '{print $NF}'
}

# Warm-up: first launch after install pays for dyld closures and font caches.
relaunch >/dev/null
sleep 10

echo "== cold launch x$RUNS"
for i in $(seq 1 "$RUNS"); do
  start=$(now)
  relaunch >/dev/null
  sleep 9
  perf_lines "$start" | grep perf_mark | sed "s/^/$i	/" >> "$OUT/launch.tsv"
done

container="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)"
ids=()
while IFS= read -r id; do ids+=("$id"); done < <(
  ls "$container/Library/Application Support/RecipeImages" 2>/dev/null \
    | sed -n 's/_preview\.webp$//p' | sort | head -8
)
[[ ${#ids[@]} -gt 0 ]] || { echo "no cached recipes to open" >&2; exit 1; }

open_sequence() { # $1 = tag written to open.tsv
  for id in "${ids[@]}"; do
    xcrun simctl openurl "$SIM" "recipe-scaler://home"
    sleep 1.2
    start=$(now)
    xcrun simctl openurl "$SIM" "recipe-scaler://recipe/$id"
    sleep 2.5
    perf_lines "$start" | grep perf_interval | sed "s/^/$1	$id	/" >> "$OUT/open.tsv" || true
  done
}

echo "== recipe opens (${#ids[@]} recipes, first and repeat)"
relaunch >/dev/null
sleep 10
open_sequence first
open_sequence repeat

trace() { # $1 = name, rest = xctrace target args
  local name=$1; shift
  xcrun xctrace record --template 'Time Profiler' --device "$SIM" --no-prompt \
    --output "$OUT/$name.trace" "$@" >/dev/null 2>&1
}

echo "== Time Profiler: cold launch"
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
sleep 1
trace launch --time-limit 12s --env AGENT_DEBUG_LOG_DISABLED=1 \
  --launch -- "$(xcrun simctl get_app_container "$SIM" "$BUNDLE" app)"

echo "== Time Profiler: recipe opens"
pid=$(relaunch)
sleep 10
trace open --time-limit 40s --attach "$pid" &
sleep 5
open_sequence traced
wait

echo "== Time Profiler: list scroll"
xcrun simctl openurl "$SIM" "recipe-scaler://home"
sleep 2
trace scroll --time-limit 20s --attach "$pid" &
sleep 5
for _ in 1 2 3 4 5; do
  axe swipe --start-x "$SWIPE_X" --start-y 700 --end-x "$SWIPE_X" --end-y 200 --duration 0.25 --udid "$SIM"
  sleep 0.6
done
for _ in 1 2 3 4 5; do
  axe swipe --start-x "$SWIPE_X" --start-y 200 --end-x "$SWIPE_X" --end-y 700 --duration 0.25 --udid "$SIM"
  sleep 0.6
done
wait

for name in launch open scroll; do
  python3 -I "$ROOT/scripts/perf/analyze-trace.py" "$OUT/$name.trace" --top 40 \
    --json "$OUT/$name.json" > "$OUT/$name.txt" || echo "trace $name: analysis failed" >&2
done

python3 -I - "$OUT" <<'PY' | tee "$OUT/summary.txt"
import json, re, statistics, sys
from collections import defaultdict
out = sys.argv[1]

def med(xs):
    return f"{statistics.median(xs):.0f}" if xs else "-"

launch = defaultdict(lambda: defaultdict(list))
for line in open(f"{out}/launch.tsv"):
    m = re.search(r"perf_mark (\S+) t=(-?\d+) idle=(-?\d+)", line)
    if m:
        launch[m[1]]["t"].append(int(m[2]))
        launch[m[1]]["idle"].append(int(m[3]))
print("cold launch, ms since process start (median t / median idle, n)")
for name in ("shell_visible", "recipes_loaded", "recipes_visible"):
    v = launch.get(name, {})
    print(f"  {name:16} {med(v.get('t', [])):>6} / {med(v.get('idle', [])):>6}  n={len(v.get('t', []))}")

opens = defaultdict(lambda: defaultdict(list))
for line in open(f"{out}/open.tsv"):
    tag = line.split("\t", 1)[0]
    m = re.search(r"perf_interval recipe_open ms=(\d+) idle=(\d+)", line)
    if m:
        opens[tag]["ms"].append(int(m[1]))
        opens[tag]["idle"].append(int(m[2]))
print("recipe open, ms from navigation to content (median ms / median idle, n)")
for tag in ("first", "repeat", "traced"):
    v = opens.get(tag, {})
    print(f"  {tag:16} {med(v.get('ms', [])):>6} / {med(v.get('idle', [])):>6}  n={len(v.get('ms', []))}")

print("Time Profiler (main thread CPU ms, hangs count / total ms)")
for name in ("launch", "open", "scroll"):
    try:
        d = json.load(open(f"{out}/{name}.json"))
    except OSError:
        print(f"  {name:16} -")
        continue
    hs = d["hangs"]
    print(f"  {name:16} {d['main_thread_ms']:>6.0f}   hangs {len(hs)} / {sum(h['duration_ms'] for h in hs):.0f}")
PY
