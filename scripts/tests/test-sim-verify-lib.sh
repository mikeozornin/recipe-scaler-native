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

echo "PASS: sim-verify helper self-tests"
