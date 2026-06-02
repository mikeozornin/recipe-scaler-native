#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

LOG_FILE="${LOG_FILE:-$ROOT/.debug-session.ndjson}"
SHOT_DIR="${SHOT_DIR:-$ROOT/specs/004-description-read-only/screenshots}"

sim_build >/dev/null
sim_prepare
sim_install
sim_launch -SkipSplash=1 -ShowDescriptionFixture

sim_wait_ready 8
SHOT="$(sim_screenshot "$SHOT_DIR" "description-fixture")"
echo "Screenshot: $SHOT"

if [[ -f "$LOG_FILE" ]]; then
  grep -E 'description_fixture|fixture' "$LOG_FILE" || true
fi

echo "VERIFIED description-ui"