#!/usr/bin/env python3
"""Remove PBXBuildFile entries whose fileRef has no PBXFileReference (breaks Xcode GUI)."""
from __future__ import annotations

import re
from pathlib import Path

PBX = Path(__file__).resolve().parents[1] / "RecipeScalerNative.xcodeproj" / "project.pbxproj"

ORPHAN_BUILD_FILE_IDS = {
    "D4E5F6A7B8C9D0E1F2A3B4C6",
    "0E2206C1B11DB3E5FF441BD4",
    "897E98ADC8B4B1C64BF6AA54",
    "E5F60718293A4B702C6563FF",
    "E5F60718293A4B70652DFDEF",
    "E5F60718293A4B7099AAB002",
    "E5F60718293A4B7099AAB004",
    "E5F60718293A4B7099AAB006",
}


def main() -> None:
    text = PBX.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    removed = 0
    for line in lines:
        if any(bid in line for bid in ORPHAN_BUILD_FILE_IDS) and "PBXBuildFile" in line:
            removed += 1
            continue
        out.append(line)
    text = "".join(out)
    text = text.replace(
        "\t\t\t\tE5F60718293A4B70DEADB001 /* SharingSettingsCache.swift */ = {isa = PBXFileReference;",
        "\t\tE5F60718293A4B70DEADB001 /* SharingSettingsCache.swift */ = {isa = PBXFileReference;",
    )
    text = text.replace(
        "\t\t\tE5F60718293A4B70F68BDA71 /* AppThemePreference.swift in Sources */",
        "\t\tE5F60718293A4B70F68BDA71 /* AppThemePreference.swift in Sources */",
    )
    text = text.replace(
        "\t\t\tE5F60718293A4B70C0C21DA6 /* AppThemePreference.swift */ = {isa = PBXFileReference;",
        "\t\tE5F60718293A4B70C0C21DA6 /* AppThemePreference.swift */ = {isa = PBXFileReference;",
    )
    PBX.write_text(text, encoding="utf-8")
    print(f"Removed {removed} orphan PBXBuildFile lines.")


if __name__ == "__main__":
    main()