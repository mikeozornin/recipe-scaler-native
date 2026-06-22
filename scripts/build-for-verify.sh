#!/usr/bin/env bash
# One-shot Debug build for the verify-all pipeline. Run once before verify-all.sh
# so individual verify-*.sh scripts can skip redundant rebuilds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/sim-verify-lib.sh"

VERIFY_SKIP_BUILD=0 sim_ensure_built
export VERIFY_SKIP_BUILD=1

echo "VERIFY_SKIP_BUILD=1 — subsequent verify scripts will reuse this build."
