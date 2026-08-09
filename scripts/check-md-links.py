#!/usr/bin/env python3
"""Check relative markdown links inside repo docs.

Fails when a `[label](relative/path.md)` or `[label](relative/path.md#anchor)`
points to a file that does not exist. External URLs (http/https) and mailto/
absolute paths are ignored.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

LINK_RE = re.compile(r"\[(?P<label>[^\]]*)\]\((?P<url>[^)\s]+)(?:\s+\"[^\"]*\")?\)")


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {Path(sys.argv[0]).name} <file.md> [<file.md> ...]", file=sys.stderr)
        return 2

    failures: list[str] = []
    for argument in sys.argv[1:]:
        path = Path(argument)
        if not path.is_file():
            failures.append(f"{path}: file not found")
            continue
        base = path.parent
        text = path.read_text(encoding="utf-8")
        for match in LINK_RE.finditer(text):
            url = match.group("url").strip()
            if not url or url.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = url.split("#", 1)[0]
            if not target:
                continue
            resolved = (base / target).resolve()
            if not resolved.exists():
                failures.append(f"{path}: broken link → {url}")

    if failures:
        for fail in failures:
            print(f"FAIL {fail}", file=sys.stderr)
        return 1
    print(f"PASS: {len(sys.argv) - 1} markdown file(s) link-checked")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
