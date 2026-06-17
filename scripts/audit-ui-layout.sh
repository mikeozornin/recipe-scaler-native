#!/usr/bin/env bash
# Run layout-audit.json for a Spec Kit feature (Figma-driven UI).
#
# Usage:
#   bash scripts/audit-ui-layout.sh specs/030-timer-widget
#
# See docs/UI-LAYOUT-FROM-FIGMA.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_DIR="${1:-}"

if [[ -z "$SPEC_DIR" ]]; then
  echo "Usage: bash scripts/audit-ui-layout.sh <spec-dir>" >&2
  echo "Example: bash scripts/audit-ui-layout.sh specs/030-timer-widget" >&2
  exit 2
fi

exec python3 "$ROOT/scripts/audit-ui-layout.py" "$SPEC_DIR"
