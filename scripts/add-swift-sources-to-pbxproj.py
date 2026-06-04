#!/usr/bin/env python3
"""Add Swift source files to RecipeScalerNative Xcode target (PBX)."""
from __future__ import annotations
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBX = ROOT / "RecipeScalerNative.xcodeproj" / "project.pbxproj"

NEW_FILES = [
    "RecipeScalerNative/Utils/ShoppingListConstants.swift",
    "RecipeScalerNative/Utils/ShoppingListFromRecipe.swift",
    "RecipeScalerNative/Utils/PublicURLBuilder.swift",
    "RecipeScalerNative/Models/YDoc/ShoppingListData.swift",
    "RecipeScalerNative/Services/YjsSync/DocumentManager+ShoppingList.swift",
    "RecipeScalerNative/Services/APIClient+Requests.swift",
    "RecipeScalerNative/Services/DiscoverAPI.swift",
    "RecipeScalerNative/Services/RecipeImportAPI.swift",
    "RecipeScalerNative/Services/RecipeImageUploadAPI.swift",
    "RecipeScalerNative/Services/SharingAPI.swift",
    "RecipeScalerNative/Services/AccountAPI.swift",
    "RecipeScalerNative/Services/AssistantAPI.swift",
    "RecipeScalerNative/Views/AppShellView.swift",
    "RecipeScalerNative/Views/ShoppingListView.swift",
    "RecipeScalerNative/Views/ImportRecipeSheet.swift",
    "RecipeScalerNative/Views/DiscoverRootView.swift",
    "RecipeScalerNative/Views/AccountView.swift",
    "RecipeScalerNative/Views/AssistantSheet.swift",
    "RecipeScalerNative/Views/MobileTimerPanel.swift",
    "RecipeScalerNative/Views/RecipeDetailActionsMenu.swift",
    "RecipeScalerNative/Views/RecipeDetailShareButton.swift",
    "RecipeScalerNative/Views/ScreenAwakeToggle.swift",
    "RecipeScalerNative/Views/ScreenAwakeStatusBanner.swift",
    "RecipeScalerNative/Utils/ScreenAwakeController.swift",
    "RecipeScalerNative/Utils/TimerUtils.swift",
    "RecipeScalerNative/Services/TimerSyncService.swift",
]


def uid(seed: str) -> str:
    h = hashlib.md5(seed.encode()).hexdigest().upper()[:24]
    return f"E5F60718293A4B70{h[:8]}"


def main() -> int:
    text = PBX.read_text()
    added = 0
    for rel in NEW_FILES:
        name = Path(rel).name
        if name in text:
            continue
        fr = uid(f"fr:{rel}")
        bf = uid(f"bf:{rel}")
        file_ref = f"\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n"
        build_file = f"\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};\n"
        text = text.replace("/* End PBXBuildFile section */", build_file + "/* End PBXBuildFile section */")
        text = text.replace("/* End PBXFileReference section */", file_ref + "/* End PBXFileReference section */")
        # Sources build phase — append before closing pbx sources list
        text = re.sub(
            r"(D48135388848E9FFF6A87142 /\* RecipeScalerNative \*/ = \{[^}]*files = \([^)]*)",
            lambda m: m.group(1) + f"\n\t\t\t\t{bf} /* {name} in Sources */,",
            text,
            count=1,
        )
        added += 1
        print(f"Added {rel}")
    if added:
        PBX.write_text(text)
    print(f"Done. {added} file(s) added.")
    return 0


if __name__ == "__main__":
    sys.exit(main())