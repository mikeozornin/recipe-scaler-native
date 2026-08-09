#!/usr/bin/env bash
# Architecture policy lint: forbid `.shared` reach-back where injection is
# required. See docs/agents/ASYNC-LIFECYCLE.md §7 and docs/ARCHITECTURE.md
# (Composition Root).
#
# Output: report-only by default. New violations can be blocked once the
# baseline is captured (LINT_COMPOSITION_ROOT_BLOCK=1).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ALLOW_LIST=(
  "RecipeScalerNative/App/AppContainer.swift"
  "RecipeScalerNative/RecipeScalerNativeApp.swift"
  "RecipeScalerNative/App/AppEnvironment.swift"
)

is_allowlisted() {
  local file="$1"
  for allowed in "${ALLOW_LIST[@]}"; do
    [[ "$file" == "$allowed" ]] && return 0
  done
  return 1
}

violation_lines=()

scan_file() {
  local file="$1"
  is_allowlisted "$file" && return 0
  # Heuristic: catch AppContainer.shared and the most common service singletons
  # inside Services/ and Views/. Pre-bootstrap shims live in App/ and are
  # allow-listed above.
  while IFS= read -r raw; do
    violation_lines+=("$raw")
  done < <(rg -n --no-heading --color never \
    'AppContainer\.shared(\?|\.|$)' \
    "$file" 2>/dev/null || true)
}

for dir in "RecipeScalerNative/Services" "RecipeScalerNative/Views" "RecipeScalerNative/LiveActivity"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r -d '' f; do
    scan_file "$f"
  done < <(find "$dir" -name '*.swift' -print0)
done

if [[ ${#violation_lines[@]} -eq 0 ]]; then
  echo "PASS: no AppContainer.shared reach-back in Services/Views/LiveActivity."
  exit 0
fi

echo "WARN: ${#violation_lines[@]} AppContainer.shared reference(s) outside allow-list:"
printf '  %s\n' "${violation_lines[@]}"
echo
echo "Use injected dependencies via AppContainer / @Environment instead. If a"
echo "site is a legitimate OS facade (SharedAuthStore, AppGroup, APIClient.shared),"
echo "add it to scripts/lint-composition-root.sh allow-list with reason/owner."

if [[ "${LINT_COMPOSITION_ROOT_BLOCK:-0}" == "1" ]]; then
  exit 1
fi
