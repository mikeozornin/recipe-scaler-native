#!/usr/bin/env python3
"""Run layout-audit.json checks for a Spec Kit feature directory.

Usage (from repo root):
  python3 scripts/audit-ui-layout.py specs/030-timer-widget
  bash scripts/audit-ui-layout.sh specs/030-timer-widget
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def rg_match(pattern: str, paths: list[str], cwd: Path) -> bool:
    for rel in paths:
        target = cwd / rel
        if target.is_dir():
            cmd = ["rg", "-q", pattern, str(target)]
        elif target.is_file():
            cmd = ["rg", "-q", pattern, str(target)]
        else:
            # glob-ish: let rg search from repo with path filter
            cmd = ["rg", "-q", pattern, rel]
        result = subprocess.run(cmd, cwd=cwd, capture_output=True)
        if result.returncode == 0:
            return True
    return False


def rg_absent(pattern: str, paths: list[str], cwd: Path) -> bool:
    return not rg_match(pattern, paths, cwd)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    spec_dir = Path(sys.argv[1])
    if not spec_dir.is_absolute():
        spec_dir = repo_root() / spec_dir

    audit_path = spec_dir / "layout-audit.json"
    if not audit_path.is_file():
        print(f"[audit-ui-layout] FAIL: missing {audit_path}", file=sys.stderr)
        return 1

    root = repo_root()
    data = json.loads(audit_path.read_text(encoding="utf-8"))
    feature = data.get("feature", spec_dir.name)
    failures = 0

    layout_doc = data.get("layout_doc", "layout.md")
    layout_path = spec_dir / layout_doc
    if layout_path.is_file():
        print(f"[audit-ui-layout] OK  layout doc present ({layout_path.relative_to(root)})")
    else:
        print(f"[audit-ui-layout] FAIL missing layout doc: {layout_path}", file=sys.stderr)
        failures += 1

    for rel in data.get("required_files", []):
        path = root / rel
        if path.is_file():
            print(f"[audit-ui-layout] OK  required file {rel}")
        else:
            print(f"[audit-ui-layout] FAIL missing file {rel}", file=sys.stderr)
            failures += 1

    for item in data.get("must_contain", []):
        check_id = item.get("id", "?")
        pattern = item["pattern"]
        paths = item.get("paths", [])
        if rg_match(pattern, paths, root):
            print(f"[audit-ui-layout] OK  must_contain {check_id}")
        else:
            print(f"[audit-ui-layout] FAIL must_contain {check_id}", file=sys.stderr)
            failures += 1

    for item in data.get("must_not_contain", []):
        check_id = item.get("id", "?")
        pattern = item["pattern"]
        paths = item.get("paths", [])
        if rg_absent(pattern, paths, root):
            print(f"[audit-ui-layout] OK  must_not_contain {check_id}")
        else:
            print(f"[audit-ui-layout] FAIL must_not_contain {check_id}", file=sys.stderr)
            failures += 1

    for item in data.get("previews", []):
        check_id = item.get("id", "?")
        pattern = item["pattern"]
        paths = item.get("paths", [])
        if rg_match(pattern, paths, root):
            print(f"[audit-ui-layout] OK  preview {check_id}")
        else:
            print(f"[audit-ui-layout] FAIL preview {check_id}", file=sys.stderr)
            failures += 1

    manual = data.get("acceptance_claims", [])
    if manual:
        print(f"[audit-ui-layout] INFO {len(manual)} manual acceptance claim(s) — see {layout_path.name}")

    if failures:
        print(f"[audit-ui-layout] {failures} check(s) failed for {feature}", file=sys.stderr)
        return 1

    print(f"[audit-ui-layout] All checks passed for {feature}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
