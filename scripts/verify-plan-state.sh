#!/usr/bin/env bash
# Validate the active Spec Kit context and plan status without guessing by mtime.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

feature_dir="${SPECIFY_FEATURE_DIRECTORY:-}"
if [[ -z "$feature_dir" && -n "${SPECIFY_FEATURE:-}" ]]; then
  feature_dir="specs/${SPECIFY_FEATURE}"
fi

if [[ -z "$feature_dir" ]]; then
  echo "PLAN STATE: no explicit active feature context" >&2
  exit 0
fi

[[ "$feature_dir" != /* ]] || {
  echo "FAIL: active feature path must be relative: $feature_dir" >&2
  exit 1
}
[[ "$feature_dir" != *".."* ]] || {
  echo "FAIL: active feature path must not contain '..': $feature_dir" >&2
  exit 1
}
[[ "$feature_dir" == specs/* ]] || {
  echo "FAIL: active feature must live under specs/: $feature_dir" >&2
  exit 1
}
[[ -f "$ROOT/$feature_dir/spec.md" ]] || {
  echo "FAIL: missing $feature_dir/spec.md" >&2
  exit 1
}
[[ -f "$ROOT/$feature_dir/plan.md" ]] || {
  echo "FAIL: missing $feature_dir/plan.md" >&2
  exit 1
}

echo "PLAN STATE: $feature_dir"
