#!/usr/bin/env bash
# Run all simulator verification scripts (mobile web parity acceptance).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

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

failed=()
for s in "${scripts[@]}"; do
  echo ""
  echo "======== $s ========"
  if ! "./scripts/$s"; then
    failed+=("$s")
  fi
done

echo ""
if ((${#failed[@]} > 0)); then
  echo "FAILED: ${failed[*]}" >&2
  exit 1
fi
echo "All ${#scripts[@]} verifiers passed."