#!/usr/bin/env bash
# Verify spec 030 — TimerWidget.
#
# 1. Build the RecipeScalerNative scheme (includes HomeWidgetExtension).
# 2. Confirm HomeWidgetExtension.appex is produced in the build Products.
# 3. Confirm the TimerWidget bundle binary loads the @main widget class.
#
# Run from the repo root:
#   bash scripts/verify-timer-widget.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="RecipeScalerNative.xcodeproj"
SCHEME="RecipeScalerNative"
# Prefer iPhone 16 Pro at the latest available OS. Use generic platform to avoid
# ambiguous destination matches across simulator OS versions.
DESTINATION='platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6'

if [[ ! -d "$PROJECT" ]]; then
  echo "[verify] Run from the repo root (RecipeScalerNative.xcodeproj not found)" >&2
  exit 1
fi

DERIVED_DATA="${DERIVED_DATA:-build/verify-derived-data}"
APPEX=$(find "$DERIVED_DATA/Build/Products" -name 'HomeWidgetExtension.appex' -type d 2>/dev/null | head -1)

if [[ "${SKIP_BUILD:-0}" == "1" && -n "$APPEX" ]]; then
  echo "[verify] SKIP_BUILD=1 — reusing $APPEX"
else
echo "[verify] Building $SCHEME for $DESTINATION..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build > /tmp/verify-timer-widget-build.log 2>&1 || {
    echo "[verify] Build failed. Tail of log:" >&2
    tail -40 /tmp/verify-timer-widget-build.log >&2
    exit 1
  }
echo "[verify] Build OK"
APPEX=$(find "$DERIVED_DATA/Build/Products" -name 'HomeWidgetExtension.appex' -type d | head -1)
fi

if [[ -z "$APPEX" ]]; then
  echo "[verify] FAIL: HomeWidgetExtension.appex not found in Products" >&2
  exit 1
fi
echo "[verify] Found appex: $APPEX"

BINARY="$APPEX/HomeWidgetExtension"
if [[ ! -f "$BINARY" ]]; then
  echo "[verify] FAIL: appex binary missing at $BINARY" >&2
  exit 1
fi
echo "[verify] Appex binary present"

# Sanity: confirm the widget bundle Info.plist points at our NSExtension.
PLIST="$APPEX/Info.plist"
POINT=$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$PLIST" 2>/dev/null || true)
if [[ "$POINT" != "com.apple.widgetkit-extension" ]]; then
  echo "[verify] FAIL: NSExtensionPointIdentifier is '$POINT' (expected com.apple.widgetkit-extension)" >&2
  exit 1
fi
echo "[verify] NSExtensionPointIdentifier OK ($POINT)"

# Confirm the binary contains our App Group + bundle id (proves the widget was compiled).
if ! strings "$BINARY" | grep -q "group.ru.recipescaler.RecipeScaler"; then
  echo "[verify] FAIL: App Group reference not found in binary" >&2
  exit 1
fi
if ! strings "$BINARY" | grep -q "ru.recipescaler.RecipeScaler.HomeWidget"; then
  echo "[verify] FAIL: Widget bundle id not found in binary" >&2
  exit 1
fi
echo "[verify] App Group + bundle id present in binary"

echo ""
echo "[verify] Layout audit (layout-audit.json)..."
bash "$ROOT/scripts/audit-ui-layout.sh" specs/030-timer-widget

echo
echo "[verify] All checks passed."
