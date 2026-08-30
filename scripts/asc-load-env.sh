#!/usr/bin/env bash
# Load App Store Connect API env from store/asc.env.local (if present).
# Vars already set in the environment are not overwritten.
#
# Usage (bash):
#   source "$(dirname "$0")/asc-load-env.sh"
#
set -euo pipefail

_asc_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

ASC_ENV_FILE="${ASC_ENV_FILE:-$(_asc_repo_root)/store/asc.env.local}"

if [[ ! -f "$ASC_ENV_FILE" ]]; then
  return 0 2>/dev/null || exit 0
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    if [[ -z "${!key:-}" ]]; then
      export "$key=$val"
    fi
  fi
done < "$ASC_ENV_FILE"
