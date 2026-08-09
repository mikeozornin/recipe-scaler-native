#!/usr/bin/env bash
# Built-bundle resource verifier. Verifies that a generated/required resource
# is actually present in a built `.app` / `.appex` — not only in the source tree.
#
# Usage:
#   scripts/check-bundle-resources.sh \
#     --app "<path-to-.app>" \
#     --manifest specs/<feature>/required-resources.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP=""
MANIFEST=""

while (($#)); do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$APP" && -n "$MANIFEST" ]] || {
  echo "usage: $0 --app <path> --manifest <required-resources.json>" >&2
  exit 2
}
[[ -d "$APP" ]] || { echo "FAIL: app bundle not found: $APP" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "FAIL: manifest not found: $MANIFEST" >&2; exit 1; }

python3 - "$APP" "$MANIFEST" <<'PY'
import json
import struct
import sys
from pathlib import Path

app = Path(sys.argv[1])
manifest = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

if manifest.get("schema") != "recipe-scaler.required-resources":
    print("FAIL: manifest.schema must be recipe-scaler.required-resources", file=sys.stderr)
    raise SystemExit(1)

resources = manifest.get("resources", [])
if not resources:
    print("FAIL: required resource matrix is empty", file=sys.stderr)
    raise SystemExit(1)

failures: list[str] = []
seen_paths: set[Path] = set()

for entry in resources:
    name = entry["name"]
    expected = app / name
    if not expected.is_file():
        if entry.get("optional"):
            print(f"OK  optional missing {name}")
            continue
        failures.append(f"missing required resource: {name}")
        continue
    if expected in seen_paths:
        failures.append(f"destination collision: {name}")
        continue
    seen_paths.add(expected)
    for key, expected_value in entry.get("constraints", {}).items():
        actual = expected.stat().st_size if key == "minBytes" else None
        if key == "minBytes" and actual < expected_value:
            failures.append(f"{name} below minBytes ({actual} < {expected_value})")
        if key == "magic" and expected.read_bytes()[:len(expected_value)] != expected_value.encode():
            failures.append(f"{name} magic mismatch")
    print(f"OK  required {name}")

if failures:
    print("bundle resource verification failed:", file=sys.stderr)
    for fail in failures:
        print(f"  - {fail}", file=sys.stderr)
    raise SystemExit(1)
print(f"VERIFIED bundle resources for {app.name} ({len(resources)} entries)")
PY
