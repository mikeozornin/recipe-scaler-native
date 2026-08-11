#!/usr/bin/env bash
# Verify spec 062 — watchOS timer expiry notification + Settings toggle.
#
# Automated claims: specs/062-watch-timer-expiry-notify/verify-claims.md (W1–W8).
#
# 1. Static — SettingsRow present, scheduler/prefs files, i18n keys.
# 2. Unit tests — WatchExpiryNotificationPlanner pure logic.
# 3. Build RecipeScalerNativeWatch.
#
# Run from repo root:
#   bash scripts/verify-watch-timer-expiry-notify.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="RecipeScalerNative.xcodeproj"
IOS_SCHEME="RecipeScalerNative"
WATCH_SCHEME="RecipeScalerNativeWatch"
IOS_DEST="${IOS_DEST:-platform=iOS Simulator,id=$("$ROOT/scripts/resolve-simulator.sh")}"
WATCH_DEST="${WATCH_DEST:-platform=watchOS Simulator,name=Apple Watch Series 11 (46mm) - iPhone Air}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/verify-watch-timer-expiry-notify-derived-data}"

if [[ ! -d "$PROJECT" ]]; then
  echo "[verify-062] Run from repo root (RecipeScalerNative.xcodeproj not found)" >&2
  exit 1
fi

# shellcheck source=scripts/sim-verify-lib.sh
source "$ROOT/scripts/sim-verify-lib.sh"
xcode_clean_watch_tbd_stubs

echo "[verify-062] Static: SettingsRow present (claim W1)..."
if ! rg -q '^\s*SettingsRow\(\)' RecipeScalerNativeWatch/Views/TimerListView.swift; then
  echo "[verify-062] FAIL: TimerListView missing SettingsRow()" >&2
  exit 1
fi
if ! rg -q '^\s*SettingsRow\(\)' RecipeScalerNativeWatch/Views/WatchStateScreenLayout.swift; then
  echo "[verify-062] FAIL: WatchStateScreenLayout missing SettingsRow()" >&2
  exit 1
fi
echo "[verify-062] Static: SettingsRow OK"

echo "[verify-062] Static: scheduler + prefs files (claims W2, W3)..."
test -f RecipeScalerNativeWatch/Services/WatchExpiryNotificationScheduler.swift
test -f RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
test -f RecipeScalerCore/Networking/WatchExpiryNotificationPlanner.swift
rg -q '^actor WatchExpiryNotificationScheduler' RecipeScalerNativeWatch/Services/WatchExpiryNotificationScheduler.swift
rg -q 'static var isEnabled' RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
rg -q 'static func setEnabled' RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
rg -q 'static func registerDefaults' RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
rg -q 'didChangeNotification' RecipeScalerNativeWatch/Services/WatchExpiryNotificationsPrefs.swift
echo "[verify-062] Static: scheduler + prefs OK"

echo "[verify-062] Static: i18n keys (claim W4)..."
XC="RecipeScalerNative/Resources/Localizable.xcstrings"
rg -q 'watch\.timer\.notification\.title' "$XC"
rg -q 'watch\.timer\.notification\.body' "$XC"
rg -q 'watch\.timer\.settings\.title' "$XC"
rg -q 'watch\.timer\.settings\.expiry-toggle\.label' "$XC"
rg -q 'watch\.timer\.settings\.expiry-toggle\.hint' "$XC"
rg -q 'watch\.timer\.settings\.notifications-disabled\.footnote' "$XC"
echo "[verify-062] Static: i18n OK"

echo "[verify-062] Static: no forbidden String(localized:) in watch target (claim W5)..."
if rg -n 'String\(localized: "watch\.timer\.' RecipeScalerNativeWatch/; then
  echo "[verify-062] FAIL: forbidden String(localized:) pattern in watch target" >&2
  exit 1
fi
echo "[verify-062] Static: localization pattern OK"

echo "[verify-062] Static: unit test file (claim W6)..."
TM="RecipeScalerNativeTests/WatchExpiryNotificationSchedulerTests.swift"
test -f "$TM"
rg -q 'test_desiredSnapshots_schedules_for_active_timer' "$TM"
rg -q 'test_desiredSnapshots_skips_paused_timer' "$TM"
rg -q 'test_desiredSnapshots_skips_expired_timer' "$TM"
rg -q 'test_desiredSnapshots_skips_within_grace' "$TM"
rg -q 'test_reconcileDiff_cancels_orphan_pending' "$TM"
rg -q 'test_reconcileDiff_paused_timer_is_not_desired' "$TM"
rg -q 'test_timerId_from_invalid_identifier_returns_nil' "$TM"
rg -q 'test_keepEndDates_retains_timer_inside_grace' "$TM"
rg -q 'test_reconcileDiff_keeps_pending_inside_grace_without_readd' "$TM"
rg -q 'test_reconcileDiff_removes_and_readds_on_endDate_drift' "$TM"
echo "[verify-062] Static: test file OK"

echo "[verify-062] Building for tests ($IOS_SCHEME)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$IOS_SCHEME" \
  -destination "$IOS_DEST" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build-for-testing \
  > /tmp/verify-watch-timer-expiry-notify-test-build.log 2>&1 || {
    echo "[verify-062] Test build failed. Tail:" >&2
    tail -40 /tmp/verify-watch-timer-expiry-notify-test-build.log >&2
    exit 1
  }

echo "[verify-062] Unit tests (claim W6)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$IOS_SCHEME" \
  -destination "$IOS_DEST" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  test-without-building \
  -only-testing:RecipeScalerNativeTests/WatchExpiryNotificationSchedulerTests \
  > /tmp/verify-watch-timer-expiry-notify-test.log 2>&1 || {
    echo "[verify-062] Tests failed. Tail:" >&2
    tail -40 /tmp/verify-watch-timer-expiry-notify-test.log >&2
    exit 1
  }
echo "[verify-062] Unit tests OK"

echo "[verify-062] Building watch target (claim W7)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$WATCH_SCHEME" \
  -destination "$WATCH_DEST" \
  -configuration Debug \
  build \
  > /tmp/verify-watch-timer-expiry-notify-watch-build.log 2>&1 || {
    echo "[verify-062] Watch build failed. Tail:" >&2
    tail -40 /tmp/verify-watch-timer-expiry-notify-watch-build.log >&2
    exit 1
  }
echo "[verify-062] Watch build OK"

echo ""
echo "[verify-062] All automated checks passed."
echo "[verify-062] Manual (simulator): see quickstart.md — background notification, toggle OFF, pause cancel."
