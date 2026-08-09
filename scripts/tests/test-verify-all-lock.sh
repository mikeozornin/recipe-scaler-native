#!/usr/bin/env bash
# Self-test the portable atomic-directory simulator lock used by verify-all.
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
lock_dir="$TMP_DIR/lock.d"

if ! mkdir "$lock_dir"; then
  echo "FAIL: first lock acquisition failed" >&2
  exit 1
fi
if mkdir "$lock_dir" 2>/dev/null; then
  echo "FAIL: second lock acquisition unexpectedly passed" >&2
  exit 1
fi
rm -rf "$lock_dir"
if ! mkdir "$lock_dir"; then
  echo "FAIL: lock was not reusable after release" >&2
  exit 1
fi

echo "PASS: portable lock self-test"
