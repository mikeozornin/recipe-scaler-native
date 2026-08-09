#!/usr/bin/env python3
"""Validate the minimum contract for new or explicitly selected feature plans."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REQUIRED_HEADINGS = (
    "## Границы",
    "## Конституционная проверка",
    "## Downstream consumers",
    "## Positive invariants",
    "## Async lifecycle",
    "## Teardown / resource inventory",
    "## Verification",
)
PLACEHOLDER_PATTERNS = (r"<название", r"YYYY-MM-DD", r"\|\s*…\s*\|")


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} specs/<feature>/plan.md", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    allow_template = path.name == "plan-template.md" and "templates" in path.parts
    if not allow_template:
        if path.parts[:1] != ("specs",) or path.name != "plan.md":
            fail("plan must be specs/<feature>/plan.md")
    if not path.is_file():
        fail(f"missing plan: {path}")

    text = path.read_text(encoding="utf-8")
    missing = [heading for heading in REQUIRED_HEADINGS if heading not in text]
    if missing:
        fail(f"missing required sections: {', '.join(missing)}")

    if allow_template:
        print(f"PASS: plan policy (template sections) {path}")
        return 0

    for pattern in PLACEHOLDER_PATTERNS:
        if re.search(pattern, text):
            fail(f"unresolved template placeholder: {pattern}")

    for section in ("## Downstream consumers", "## Positive invariants", "## Verification"):
        start = text.find(section) + len(section)
        end = text.find("\n## ", start)
        body = text[start:] if end == -1 else text[start:end]
        if not body.strip():
            fail(f"empty required section: {section}")

    print(f"PASS: plan policy {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
