#!/usr/bin/env bash
# Import locale zips + shopping seed into persistent store users (once).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

MANIFEST="$ROOT/store/screenshots/manifest.yaml"
KEYS=(ru en app-store-review)
SKIP_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --only) KEYS=("$2"); shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

manifest_value() {
  local locale="$1" key="$2"
  python3 - "$MANIFEST" "$locale" "$key" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
locale, key = sys.argv[2], sys.argv[3]
section = text.split(f"  {locale}:", 1)[1]
if locale == "ru":
    section = section.split("\n  en:", 1)[0]
for line in section.splitlines():
    line = line.strip()
    if line.startswith(key + ":"):
        print(line.split(":", 1)[1].strip().strip('"').strip("'"))
        break
PY
}

shopping_seed_arg() {
  local locale="$1"
  python3 - "$MANIFEST" "$locale" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
locale = sys.argv[2]
block = text.split(f"  {locale}:", 1)[1]
if locale == "ru":
    block = block.split("  en:", 1)[0]
in_items = False
items = []
for line in block.splitlines():
    if line.strip().startswith("shoppingItems:"):
        in_items = True
        continue
    if in_items:
        stripped = line.strip()
        if stripped.startswith("- "):
            items.append(stripped[2:].strip().strip('"'))
        elif stripped and not stripped.startswith("-") and not stripped.startswith("#"):
            break
print("|".join(items))
PY
}

json="$(xcrun simctl list devices available -j)"
SIM_ID="$(python3 - "$json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
for name in ("iPhone Air", "iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 17 + Watch"):
    for devices in data.get("devices", {}).values():
        for dev in devices:
            if dev.get("name") == name and dev.get("isAvailable", True):
                print(dev["udid"])
                raise SystemExit
raise SystemExit("no simulator")
PY
)"
echo "== Simulator $SIM_ID =="
if [[ "$SKIP_BUILD" != "1" ]]; then
  sim_ensure_built
fi
sim_prepare
sim_install

for key in "${KEYS[@]}"; do
  locale="$key"
  [[ "$key" == "app-store-review" ]] && locale="en"
  archive="$ROOT/store/fixtures/recipes-${locale}.zip"
  [[ -f "$archive" ]] || { echo "missing $archive" >&2; exit 1; }
  app_lang="$(manifest_value "$locale" appLanguage)"
  shop_seed="$(shopping_seed_arg "$locale")"
  user_id=""; token=""; seed=""
  {
    IFS= read -r user_id
    IFS= read -r token
    IFS= read -r seed
  } < <(python3 "$ROOT/scripts/store_users.py" login "$key")
  echo "== Bootstrap $key ($user_id) =="
  export SIMCTL_CHILD_E2E_OVERRIDE_USER_ID="$user_id"
  export SIMCTL_CHILD_E2E_OVERRIDE_DEVICE_TOKEN="$token"
  export SIMCTL_CHILD_E2E_OVERRIDE_SEED_PHRASE="$seed"
  export SIMCTL_CHILD_E2E_OVERRIDE_API_BASE="${E2E_API_BASE:-https://recipe-scaler.ru}"
  export SIMCTL_CHILD_AGENT_DEBUG_LOG_DISABLED=1
  xcrun simctl spawn "$SIM_ID" defaults write -g AppleLanguages -array "$app_lang" >/dev/null || true
  sim_launch \
    -SkipSplash=1 \
    -ScreenshotCapture=1 \
    -DisableDebugAutoLogin=1 \
    "-AppLanguage=$app_lang" \
    "-ImportNativeZip=$archive" \
    "-ScreenshotShoppingSeed=$shop_seed" \
    "-OpenTab=recipes"
  sleep 14
  sim_terminate
done

echo "Bootstrap done. Libraries live on the persistent store users."
