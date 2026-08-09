#!/usr/bin/env python3
"""Run layout-audit.json checks for a Spec Kit feature directory.

Usage (from repo root):
  python3 scripts/audit-ui-layout.py specs/030-timer-widget
  bash scripts/audit-ui-layout.sh specs/030-timer-widget

Verdicts (see docs/agents/VERIFICATION.md):
  STATIC PASS — machine checks green; human acceptance still pending
  VERIFIED    — static checks + matching layout-acceptance.json (human)
  FAILED      — static check failed, or --strict / LAYOUT_AUDIT_STRICT=1
                with pending acceptance
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def layout_hash(layout_path: Path) -> str:
    if not layout_path.is_file():
        return ""
    return hashlib.sha256(layout_path.read_bytes()).hexdigest()[:16]


def acceptance_payload(spec_dir: Path) -> dict:
    path = spec_dir / "layout-acceptance.json"
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


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
    args = [a for a in sys.argv[1:] if a != "--strict"]
    strict_mode = "--strict" in sys.argv or os.environ.get("LAYOUT_AUDIT_STRICT") == "1"

    if len(args) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    spec_dir = Path(args[0])
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
    pending_claims: list[dict] = []
    acceptance = acceptance_payload(spec_dir)
    current_hash = layout_hash(layout_path)
    acceptance_hash = acceptance.get("layoutHash")
    reviewer_type = acceptance.get("reviewerType")
    verified_at = acceptance.get("verifiedAt")

    # Claims with automatedCheck stay in the static audit path; others need human acceptance.
    for claim in manual:
        if claim.get("automatedCheck"):
            continue
        pending_claims.append(claim)

    acceptance_valid = (
        bool(acceptance)
        and acceptance_hash == current_hash
        and reviewer_type == "human"
        and bool(verified_at)
    )

    if acceptance_valid:
        print(
            f"[audit-ui-layout] OK  human acceptance recorded for {current_hash} on {verified_at}"
        )
    elif pending_claims:
        print(
            f"[audit-ui-layout] INFO {len(pending_claims)} manual acceptance claim(s) still pending "
            f"human review (see {layout_path.name})"
        )
    elif manual and not acceptance:
        print(
            f"[audit-ui-layout] INFO {len(manual)} manual claim(s) — no layout-acceptance.json yet"
        )

    if failures:
        print(f"[audit-ui-layout] {failures} check(s) failed for {feature}", file=sys.stderr)
        return 1

    if acceptance_valid and (not pending_claims or bool(acceptance)):
        # Matching human acceptance file is enough to promote STATIC PASS → VERIFIED.
        print(f"[audit-ui-layout] VERIFIED {feature} (static + human acceptance)")
        return 0

    if strict_mode and pending_claims and not acceptance_valid:
        print(
            "[audit-ui-layout] FAILED strict mode: manual claims pending human acceptance",
            file=sys.stderr,
        )
        return 1

    print(f"[audit-ui-layout] STATIC PASS for {feature}; acceptance pending")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
