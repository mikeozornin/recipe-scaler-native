#!/usr/bin/env bash
# Self-tests for the shared simulator verifier helpers.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fake_bin="$TMP_DIR/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"get_app_container"* ]]; then
  printf '%s\n' "${FAKE_CONTAINER:?}"
elif [[ "$*" == *"simctl launch"* ]]; then
  exit 0
else
  exit 0
fi
SH
chmod +x "$fake_bin/xcrun"

export PATH="$fake_bin:$PATH"
export SIM_ID="test-simulator"
export BUNDLE_ID="ru.recipescaler.RecipeScaler"
export LOG_FILE="$TMP_DIR/host.ndjson"

mkdir -p "$TMP_DIR/container/Library/Application Support"
export FAKE_CONTAINER="$TMP_DIR/container"

export ROOT="$REPO_ROOT"
source "$REPO_ROOT/scripts/sim-verify-lib.sh"

if sim_wait_ready 1; then
  echo "FAIL: readiness timeout unexpectedly passed" >&2
  exit 1
fi

printf '{"message":"app_shell_start"}\n' > "$TMP_DIR/container/Library/Application Support/debug-session.ndjson"
if ! sim_wait_ready 1; then
  echo "FAIL: readiness marker was not accepted" >&2
  exit 1
fi

# xcode_derived_data_of: only folders built from the checkout itself, not from a sibling
# whose path shares the prefix, and not folders without info.plist.
derived_root="$TMP_DIR/DerivedData"
mkdir -p "$derived_root/A" "$derived_root/B" "$derived_root/C"
write_workspace_plist() {
  plutil -create xml1 "$1/info.plist"
  plutil -insert WorkspacePath -string "$2" "$1/info.plist"
}
write_workspace_plist "$derived_root/A" "$TMP_DIR/checkout/X.xcodeproj"
write_workspace_plist "$derived_root/B" "$TMP_DIR/checkout-other/X.xcodeproj"
found="$(xcode_derived_data_of "$TMP_DIR/checkout" "$derived_root" | tr '\0' '\n')"
if [[ "$found" != "$derived_root/A" ]]; then
  echo "FAIL: xcode_derived_data_of returned '$found', expected only $derived_root/A" >&2
  exit 1
fi
for empty_checkout in "" "/"; do
  found="$(xcode_derived_data_of "$empty_checkout" "$derived_root" | tr '\0' '\n')"
  if [[ -n "$found" ]]; then
    echo "FAIL: xcode_derived_data_of '$empty_checkout' returned '$found', expected nothing" >&2
    exit 1
  fi
done
found="$(xcode_derived_data_of "$TMP_DIR/checkout" "$TMP_DIR/no-such-dir" | tr '\0' '\n')"
if [[ -n "$found" ]]; then
  echo "FAIL: xcode_derived_data_of on a missing root returned '$found'" >&2
  exit 1
fi

echo "PASS: sim-verify helper self-tests"
