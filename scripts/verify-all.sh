#!/usr/bin/env bash
# Run all simulator verification scripts (mobile web parity acceptance).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Self-tests first: fail closed before spending time on simulator work.
bash "$ROOT/scripts/tests/test-sim-verify-lib.sh"
bash "$ROOT/scripts/tests/test-verify-all-lock.sh"

# One shared Debug build for the whole pipeline.
VERIFY_SKIP_BUILD=0 "$ROOT/scripts/build-for-verify.sh"
export VERIFY_SKIP_BUILD=1

# Catalog drift gate: bundled ingredient-catalog.{json,ru.json,en.json,manifest.json}
# must match the web registry. Runs before any simulator work so failures are fast.
if ! node "$ROOT/scripts/sync-ingredient-illustrations.mjs" --check; then
  echo "FAILED: ingredient catalog drift — run 'node scripts/sync-ingredient-illustrations.mjs' and commit" >&2
  exit 1
fi

scripts=(
  verify-recipe-description-native.sh
  verify-app-shell.sh
  verify-collection-mutations.sh
  verify-description-editor.sh
  verify-recipe-collections.sh
  verify-shopping-list.sh
  verify-recipe-import.sh
  verify-discover-public.sh
  verify-sharing.sh
  verify-account-settings.sh
  verify-timers-sync.sh
  verify-timer-notifications.sh
  verify-assistant.sh
  verify-recipe-image-upload.sh
)

# Portable atomic-directory lock (no flock dependency). mkdir is atomic.
SIM_LOCK_DIR="$ROOT/.verify-sim.lock.d"
cleanup_lock() {
  rm -rf "$SIM_LOCK_DIR"
}
trap cleanup_lock EXIT

acquire_lock() {
  local waited=0
  while ! mkdir "$SIM_LOCK_DIR" 2>/dev/null; do
    if (( waited >= 600 )); then
      echo "FAILED: could not acquire simulator lock within 600s" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  printf '%s\n' "$$" > "$SIM_LOCK_DIR/pid"
}

failed=()
for s in "${scripts[@]}"; do
  echo ""
  echo "======== $s ========"
  acquire_lock
  if ! "./scripts/$s"; then
    failed+=("$s")
  fi
  cleanup_lock
done

echo ""
if ((${#failed[@]} > 0)); then
  echo "FAILED: ${failed[*]}" >&2
  exit 1
fi
echo "All ${#scripts[@]} verifiers passed."
