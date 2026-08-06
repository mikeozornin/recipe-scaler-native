#!/usr/bin/env bash
# Increments CURRENT_PROJECT_VERSION in Config/Version.xcconfig.
# Called automatically before Archive (RecipeScalerNative scheme pre-action).
# Skip: RS_SKIP_BUILD_BUMP=1

set -euo pipefail

if [[ "${RS_SKIP_BUILD_BUMP:-}" == "1" ]]; then
  echo "bump-build-number: skipped (RS_SKIP_BUILD_BUMP=1)"
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCCONFIG="$ROOT/Config/Version.xcconfig"

if [[ ! -f "$XCCONFIG" ]]; then
  echo "bump-build-number: missing $XCCONFIG" >&2
  exit 1
fi

marketing="$(sed -n 's/^MARKETING_VERSION = //p' "$XCCONFIG" | tr -d '[:space:]')"
current="$(sed -n 's/^CURRENT_PROJECT_VERSION = //p' "$XCCONFIG" | tr -d '[:space:]')"

if [[ -z "$marketing" || -z "$current" ]]; then
  echo "bump-build-number: could not parse MARKETING_VERSION / CURRENT_PROJECT_VERSION" >&2
  exit 1
fi

next=$((current + 1))

if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${next}/" "$XCCONFIG"
else
  sed -i "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${next}/" "$XCCONFIG"
fi

echo "bump-build-number: ${marketing}.${current} → ${marketing}.${next} (build ${next})"
