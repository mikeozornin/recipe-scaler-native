#!/usr/bin/env bash
# Verify spec 039 — watchOS Timers.
#
# Automated claims: specs/039-watchos-timers/verify-claims.md (W1–W8).
#
# 1. Unit tests — presentation math, palette, sort order.
# 2. Static — TimelineView wraps List in TimerListView (live progress tick).
# 3. Build RecipeScalerNativeWatch.
# 4. Layout audit (spec 039).
#
# Run from repo root:
#   bash scripts/verify-watch-timers.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="RecipeScalerNative.xcodeproj"
IOS_SCHEME="RecipeScalerNative"
WATCH_SCHEME="RecipeScalerNativeWatch"
IOS_DEST="${IOS_DEST:-platform=iOS Simulator,id=EFC65E55-4F28-4C21-B489-D9733D2BE6B5}"
WATCH_DEST="${WATCH_DEST:-platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/verify-watch-timers-derived-data}"

if [[ ! -d "$PROJECT" ]]; then
  echo "[verify-watch] Run from repo root (RecipeScalerNative.xcodeproj not found)" >&2
  exit 1
fi

# shellcheck source=scripts/sim-verify-lib.sh
source "$ROOT/scripts/sim-verify-lib.sh"
xcode_clean_watch_tbd_stubs

echo "[verify-watch] Static: TimelineView at list level (claim W7)..."
if ! rg -q 'TimelineView\(\.periodic' RecipeScalerNativeWatch/Views/TimerListView.swift; then
  echo "[verify-watch] FAIL: TimerListView missing list-level TimelineView" >&2
  exit 1
fi
if rg -q 'TimelineView\(' RecipeScalerNativeWatch/Views/TimerRow.swift; then
  echo "[verify-watch] FAIL: TimerRow must not own TimelineView (use parent tick)" >&2
  exit 1
fi
echo "[verify-watch] Static OK"

echo "[verify-watch] Building for tests ($IOS_SCHEME)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$IOS_SCHEME" \
  -destination "$IOS_DEST" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build-for-testing \
  > /tmp/verify-watch-timers-test-build.log 2>&1 || {
    echo "[verify-watch] Test build failed. Tail:" >&2
    tail -40 /tmp/verify-watch-timers-test-build.log >&2
    exit 1
  }

echo "[verify-watch] Unit tests (claims W1–W6)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$IOS_SCHEME" \
  -destination "$IOS_DEST" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  test-without-building \
  -only-testing:RecipeScalerNativeTests/ActiveTimerPresentationTests \
  -only-testing:RecipeScalerNativeTests/TimerPaletteTests \
  -only-testing:RecipeScalerNativeTests/TimerOrderingTests \
  > /tmp/verify-watch-timers-test.log 2>&1 || {
    echo "[verify-watch] Tests failed. Tail:" >&2
    tail -40 /tmp/verify-watch-timers-test.log >&2
    exit 1
  }
echo "[verify-watch] Unit tests OK"

echo "[verify-watch] Building watch target (claim W8)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$WATCH_SCHEME" \
  -destination "$WATCH_DEST" \
  -configuration Debug \
  build \
  > /tmp/verify-watch-timers-watch-build.log 2>&1 || {
    echo "[verify-watch] Watch build failed. Tail:" >&2
    tail -40 /tmp/verify-watch-timers-watch-build.log >&2
    exit 1
  }
echo "[verify-watch] Watch build OK"

echo "[verify-watch] Layout audit (spec 039)..."
bash "$ROOT/scripts/audit-ui-layout.sh" specs/039-watchos-timers

echo ""
echo "[verify-watch] All automated checks passed."
echo "[verify-watch] Manual (simulator): see verify-claims.md — progress grows within 5s without restart."
