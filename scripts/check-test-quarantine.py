#!/usr/bin/env python3
"""Validate the bounded test quarantine manifest.

Rules:
- Manifest schema/version must match.
- Every entry has reason, owner, introducedAt, expiry (ISO date), exitCriteria,
  removalCondition.
- Expiry in the past => failure (no permanent suppressions).
- `target`/`class` must look like the values used by `xcodebuild -skip-testing`.
"""

from __future__ import annotations

import datetime as dt
import json
import re
import sys
from pathlib import Path

ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TARGET_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} scripts/test-quarantine.json", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        fail(f"missing manifest: {path}")

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON: {exc}")

    if data.get("schema") != "recipe-scaler.test-quarantine":
        fail("schema mismatch")
    if data.get("version") != "1.0":
        fail("only manifest version 1.0 is supported")

    today = dt.date.today()
    seen: set[tuple[str, str]] = set()
    for entry in data.get("suites", []):
        for key in ("target", "class", "reason", "owner", "introducedAt", "expiry", "exitCriteria", "removalCondition"):
            value = entry.get(key)
            if not value:
                fail(f"entry missing {key}: {entry}")
        if not TARGET_PATTERN.match(entry["target"]) or not TARGET_PATTERN.match(entry["class"]):
            fail(f"invalid target/class: {entry['target']}/{entry['class']}")

        for date_key in ("introducedAt", "expiry"):
            if not ISO_DATE.match(entry[date_key]):
                fail(f"{date_key} must be YYYY-MM-DD: {entry[date_key]}")

        expiry = dt.date.fromisoformat(entry["expiry"])
        if expiry < today:
            fail(f"quarantine expired: {entry['target']}/{entry['class']} expiry {entry['expiry']}")

        if not isinstance(entry["exitCriteria"], list) or not entry["exitCriteria"]:
            fail("exitCriteria must be a non-empty list")

        key = (entry["target"], entry["class"])
        if key in seen:
            fail(f"duplicate quarantine entry: {key}")
        seen.add(key)

    print(f"PASS: quarantine manifest {path} ({len(seen)} suite(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
