#!/usr/bin/env bash
# Pull app NDJSON journal from the iOS Simulator into the repo root.
# Usage: bash scripts/pull-app-logs.sh
# Env: SIM_ID, LOG_FILE (optional overrides)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/sim-verify-lib.sh
source "$ROOT/scripts/sim-verify-lib.sh"

DEST="${LOG_FILE:-$ROOT/.debug-session.ndjson}"

if sim_pull_debug_log; then
  echo "$DEST"
  exit 0
fi

echo "No log file found in simulator container for $BUNDLE_ID (SIM_ID=$SIM_ID)" >&2
echo "Expected: Library/Application Support/debug-session.ndjson (DEBUG build, app has run)" >&2
exit 1
