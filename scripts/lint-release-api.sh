#!/usr/bin/env bash
# Release-boundary lint: catch debug-only helpers that leaked into Release API.
# See docs/agents/ASYNC-LIFECYCLE.md §6 and `llm/reviews/2026.08.06 review-aggregated-master.md`
# (replaceShoppingItems / NSSelectorFromString findings).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

violation_lines=()

# Detect public/internal functions whose name clearly marks them as debug-only
# (Fixture/Studio/ForScreenshot/ForTesting/Seed) but which are NOT guarded by
# `#if DEBUG`. We scan source; a full Release-binary check still belongs in CI.
while IFS= read -r raw; do
  file="${raw%%:*}"
  rest="${raw#*:}"
  lineno="${rest%%:*}"
  if ! rg -n -B 40 "$raw" "$file" 2>/dev/null \
       | rg -q '#if DEBUG'; then
    violation_lines+=("$raw")
  fi
done < <(rg -n --no-heading --color never \
  'func\s+(replace|seed|fixture|studio)[A-Za-z0-9_]*For(Screenshot|Testing|Seed)|^\s*public\s+(static\s+)?func\s+[A-Za-z0-9_]*(ForTesting|ForScreenshotSeed)\b' \
  -g '*.swift' \
  RecipeScalerNative RecipeScalerCore HomeWidgetExtension ShareExtensionUI ActionExtension \
  2>/dev/null || true)

if [[ ${#violation_lines[@]} -eq 0 ]]; then
  echo "PASS: no unguarded debug-only helpers detected in source."
  exit 0
fi

echo "WARN: ${#violation_lines[@]} potentially unguarded debug-only helper(s):"
printf '  %s\n' "${violation_lines[@]}"
echo
echo "Move under #if DEBUG, or rename if the helper is a real production"
echo "primitive, or document why Release visibility is required."

if [[ "${LINT_RELEASE_API_BLOCK:-0}" == "1" ]]; then
  exit 1
fi
