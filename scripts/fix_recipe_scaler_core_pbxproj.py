#!/usr/bin/env python3
"""Fix RecipeScalerCore file paths and remove duplicate sources from main app target."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBX = ROOT / "RecipeScalerNative.xcodeproj" / "project.pbxproj"

# PBXBuildFile IDs to remove from RecipeScalerNative Sources phase only
MAIN_SOURCE_REMOVALS = {
    "0E2206C1B11DB3E5FF441BD4",  # APIClient.swift (wrong ref)
    "D4E5F6A7B8C9D0E1F2A3B4C6",  # SharedAuthStore shim
    "897E98ADC8B4B1C64BF6AA54",  # Config.swift
    "E5F60718293A4B702C6563FF",  # APIClient+Requests.swift
    "E5F60718293A4B70652DFDEF",  # RecipeImportAPI.swift
    "E5F60718293A4B7099AAB002",  # ImportContentClassifier.swift
    "E5F60718293A4B7099AAB004",  # ImportPhotoValidator.swift
    "E5F60718293A4B7099AAB006",  # ImportErrorLocalizer.swift
}

# fileRef ID -> path relative to RecipeScalerCore group
CORE_PATH_FIXES = {
    "B1FC95C981104E30AE6DFE07": "RecipeScalerCore.swift",
    "0F696F3421504AD3A7836B0C": "Auth/SharedAuthStore.swift",
    "E3CBCE9817864C1C8B333764": "Config/Config.swift",
    "922F28300880430B97A0348C": "Networking/APIClient.swift",
    "41F1A2877817482DAC0FE2DC": "Networking/APIClient+Requests.swift",
    "DA95C7943B584B11A547EB85": "Import/RecipeImportAPI.swift",
    "D24E09F4CE9D4C34852A98AF": "Import/ImportContentClassifier.swift",
    "6C6A0A37120248F8AAB066E8": "Import/ImportPhotoValidator.swift",
    "6A46C39B025B41C69FD12A6A": "Import/ImportErrorLocalizer.swift",
    "743247074D2B4CAFACB39F46": "UI/ShareContentLoader.swift",
    "5DE6F63FC7E14C8C979AACCE": "UI/ShareView.swift",
    "B723ECE01A3D4E2F85D856AC": "Resources/Shared.xcstrings",
}

# Remove these fileRef lines from PBXFileReference (stale duplicates)
STALE_FILE_REF_IDS = {
    "80636F48545B3EEDBF6BA3C5",
    "E4BC1DF4500B18B5CC3AFC71",
    "D4E5F6A7B8C9D0E1F2A3B4C5",
    "E5F60718293A4B70AC40BCFC",
    "E5F60718293A4B70177F16C9",
    "E5F60718293A4B7099AAB001",
    "E5F60718293A4B7099AAB003",
    "E5F60718293A4B7099AAB005",
}

# Remove from group children lists
STALE_GROUP_REFS = STALE_FILE_REF_IDS


def fix_file_ref_path(text: str, ref_id: str, new_path: str) -> str:
    pattern = (
        rf"(\t\t{ref_id} /\* [^*]+ \*/ = \{{isa = PBXFileReference; "
        rf"lastKnownFileType = [^;]+; path = )([^;]+)(; sourceTree)"
    )

    def repl(m: re.Match[str]) -> str:
        return f"{m.group(1)}{new_path}{m.group(3)}"

    return re.sub(pattern, repl, text, count=1)


def remove_lines_with_ids(text: str, ids: set[str]) -> str:
    lines = []
    for line in text.splitlines(keepends=True):
        if any(i in line for i in ids):
            # Keep if it's a core-target-only build file we still need
            if " in Sources */" in line or " in Resources */" in line:
                if any(rem in line for rem in MAIN_SOURCE_REMOVALS):
                    continue
            if line.strip().startswith(tuple(f"{i} /*" for i in STALE_FILE_REF_IDS)):
                continue
            if any(f"{i} /*" in line for i in STALE_GROUP_REFS) and "children" not in line:
                # group child line
                if re.search(rf"\t\t\t\t{list(STALE_GROUP_REFS)[0]}", line):
                    pass
        skip = False
        for i in ids:
            if i in line:
                if "PBXFileReference" in line and i in STALE_FILE_REF_IDS:
                    skip = True
                    break
                if i in MAIN_SOURCE_REMOVALS and "72A876A1FC6083C3018BF18A" not in text:
                    pass
        if skip:
            continue
        lines.append(line)
    return "".join(lines)


def remove_from_main_sources(text: str) -> str:
    in_main_sources = False
    out = []
    for line in text.splitlines(keepends=True):
        if "72A876A1FC6083C3018BF18A /* Sources */" in line:
            in_main_sources = True
        elif in_main_sources and line.strip() == ");" and "files" not in line:
            in_main_sources = False
        if in_main_sources and any(rid in line for rid in MAIN_SOURCE_REMOVALS):
            continue
        out.append(line)
    return "".join(out)


def remove_stale_refs_from_groups(text: str) -> str:
    for ref in STALE_GROUP_REFS:
        text = re.sub(rf"\t\t\t\t{ref} /\* [^*]+ \*/,?\n", "", text)
    return text


def remove_stale_file_reference_entries(text: str) -> str:
    for ref in STALE_FILE_REF_IDS:
        text = re.sub(
            rf"\t\t{ref} /\* [^\n]+\n",
            "",
            text,
        )
    return text


def main() -> None:
    text = PBX.read_text(encoding="utf-8")
    for ref_id, path in CORE_PATH_FIXES.items():
        text = fix_file_ref_path(text, ref_id, path)
    text = remove_from_main_sources(text)
    text = remove_stale_file_reference_entries(text)
    text = remove_stale_refs_from_groups(text)
    PBX.write_text(text, encoding="utf-8")
    print("Fixed RecipeScalerCore paths and trimmed main app duplicate sources.")


if __name__ == "__main__":
    main()