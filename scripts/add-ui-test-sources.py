#!/usr/bin/env python3
"""Register UI test infrastructure and spec files in project.pbxproj.

Adds new .swift files under RecipeScalerNativeUITests/ to the
RecipeScalerNativeUITests target (PBXNativeTarget ID UITESTTARGET0010000000,
created by add-ui-test-target.py).

Idempotent: re-running it after files are added is a no-op.

Usage:
    python3 scripts/add-ui-test-sources.py
"""
from __future__ import annotations
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBX = ROOT / "RecipeScalerNative.xcodeproj" / "project.pbxproj"

# Stable, descriptive 24-char hex IDs. Pattern: UITNNNN + filename hash.
def uid(seed: str) -> str:
    h = hashlib.md5(seed.encode()).hexdigest().upper()[:18]
    return f"UIT{h}"


# The Sources build phase ID for RecipeScalerNativeUITests target.
UITESTS_SOURCES_PHASE_ID = "UITESTSRCPHASE10000000"
# The RecipeScalerNativeUITests group ID.
UITESTS_GROUP_ID = "EE830B9272D882874906264B"


# All new source files to register, relative to repo root.
# Format: (path, group_subpath) — group_subpath describes the subgroup
# under UITests group (Helpers/, Fixtures/, Pages/, Specs/).
NEW_FILES = [
    # Phase 0 infrastructure
    ("RecipeScalerNativeUITests/BaseTestCase.swift", None),
    ("RecipeScalerNativeUITests/Helpers/Selectors.swift", "Helpers"),
    ("RecipeScalerNativeUITests/Helpers/Wait.swift", "Helpers"),
    ("RecipeScalerNativeUITests/Helpers/Navigation.swift", "Helpers"),
    ("RecipeScalerNativeUITests/Helpers/Page.swift", "Helpers"),
    ("RecipeScalerNativeUITests/Helpers/Logs.swift", "Helpers"),
    ("RecipeScalerNativeUITests/Helpers/E2EConfig.swift", "Helpers"),
    ("RecipeScalerNativeUITests/Helpers/TestUser.swift", "Helpers"),
    ("RecipeScalerNativeUITests/Helpers/Errors.swift", "Helpers"),
    ("RecipeScalerNativeUITests/Fixtures/DebugUser.swift", "Fixtures"),
    ("RecipeScalerNativeUITests/Fixtures/TestData.swift", "Fixtures"),
    ("RecipeScalerNativeUITests/Fixtures/SeedClient.swift", "Fixtures"),
    ("RecipeScalerNativeUITests/Helpers/Errors.swift", "Helpers"),
    ("RecipeScalerNativeUITests/Pages/RecipeListPage.swift", "Pages"),
    ("RecipeScalerNativeUITests/Pages/RecipeDetailPage.swift", "Pages"),
    ("RecipeScalerNativeUITests/Pages/ShoppingListPage.swift", "Pages"),
    ("RecipeScalerNativeUITests/Pages/CollectionsPage.swift", "Pages"),
    ("RecipeScalerNativeUITests/Pages/AccountPage.swift", "Pages"),
    ("RecipeScalerNativeUITests/Pages/DiscoverPage.swift", "Pages"),
    ("RecipeScalerNativeUITests/Pages/AssistantPage.swift", "Pages"),
    ("RecipeScalerNativeUITests/Pages/TimersPage.swift", "Pages"),
    ("RecipeScalerNativeUITests/Pages/ImportPage.swift", "Pages"),
    ("RecipeScalerNativeUITests/Pages/AuthPage.swift", "Pages"),
    # Iteration 1 — Core flow specs
    ("RecipeScalerNativeUITests/Specs/AppShellNavigationSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/RecipeEditingSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/ShoppingListCompletionSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/AccountSettingsSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/DiscoverPublicSpec.swift", "Specs"),
    # Iteration 2 — Read & list flows
    ("RecipeScalerNativeUITests/Specs/YrsNativeReadSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/DescriptionDisplaySpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/RecipeCollectionsSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/CollectionMutationsSpec.swift", "Specs"),
    # Iteration 3 — Import & export
    ("RecipeScalerNativeUITests/Specs/RecipeImportSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/PaprikaCroutonImportSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/AccountDataExportImportSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/ImportDecompressionBombSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/NativeExportAmountTextSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/AppLoggingSpec.swift", "Specs"),
    # Iteration 4 — Realtime & assistant
    ("RecipeScalerNativeUITests/Specs/TimersSyncSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/AssistantSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/AssistantFullSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/RecipeDescriptionInlineEditSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/DescriptionEditorRichtextSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/DescriptionEditorSpec.swift", "Specs"),
    # Iteration 5 — Auth, sharing, account
    ("RecipeScalerNativeUITests/Specs/AuthDeviceTokensSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/AuthStaleSessionRecoverySpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/SharingSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/AccountTelegramExportSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/I18nNewViewsSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/ErrorI18nSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/PushNotificationsSpec.swift", "Specs"),
    # Iteration 6 — Native-only features
    ("RecipeScalerNativeUITests/Specs/RecipeImageUploadSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/IngredientIllustrationsSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/PublicImageCacheSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/ShareExtensionSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/TimerNotificationActionsSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/DiscoverEnablementSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/FeatureAdoptionTrackerSpec.swift", "Specs"),
    ("RecipeScalerNativeUITests/Specs/FeatureAdoptionGuidesSpec.swift", "Specs"),
]


def create_subgroup_in_uitests(text: str, group_name: str) -> tuple[str, str]:
    """Create a NEW PBXGroup subgroup inside the UITests root group.

    Unlike the previous logic, we NEVER reuse an existing group with the same
    name elsewhere in the project (Fixtures/ exists in RecipeScalerNativeTests).
    Instead we always allocate a fresh group registered as a child of the
    UITests root group.
    """
    # Use a deterministic id so re-running is idempotent.
    group_id = uid(f"uitests-group:{group_name}")
    # Verify it isn't already defined.
    if f"{group_id} /* {group_name} */ = {{\n\t\t\tisa = PBXGroup;" in text:
        return text, group_id

    group_def = (
        f"\t\t{group_id} /* {group_name} */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t);\n"
        f"\t\t\tpath = {group_name};\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End PBXGroup section */",
        group_def + "/* End PBXGroup section */",
    )
    # Register in UITests root group's children, right after the existing
    # RecipeScalerNativeUITests.swift entry.
    text = text.replace(
        f"\t\t\t\t1A2C8350A32724EACB324178 /* RecipeScalerNativeUITests.swift */,",
        f"\t\t\t\t1A2C8350A32724EACB324178 /* RecipeScalerNativeUITests.swift */,\n"
        f"\t\t\t\t{group_id} /* {group_name} */,",
        1,
    )
    return text, group_id


def main() -> int:
    text = PBX.read_text()
    added = 0

    # Pre-create subgroups (always fresh, registered inside UITests group).
    subgroups: dict[str, str] = {}
    for _, group_name in NEW_FILES:
        if group_name and group_name not in subgroups:
            text, gid = create_subgroup_in_uitests(text, group_name)
            subgroups[group_name] = gid

    for rel, group_name in NEW_FILES:
        name = Path(rel).name
        # path attribute is RELATIVE to the parent group. The subgroup's
        # parent is the UITests root group, whose path is "RecipeScalerNativeUITests".
        # So file path inside e.g. the Fixtures subgroup is just "DebugUser.swift"
        # (subgroup already has path="Fixtures").
        path_attr = name

        # Idempotency: skip if file already present anywhere.
        idempotency_key = f"UITESTFILE:{rel}"
        # Use uid() to get the deterministic file ref id we'd generate.
        expected_fr = uid(f"fr:{rel}")
        if f"{expected_fr} /* {name} */" in text:
            continue

        fr = expected_fr
        bf = uid(f"bf:{rel}")
        file_ref = (
            f'\t\t{fr} /* {name} */ = {{isa = PBXFileReference; '
            f'lastKnownFileType = sourcecode.swift; '
            f'path = "{path_attr}"; sourceTree = "<group>"; }};\n'
        )
        build_file = (
            f'\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; '
            f'fileRef = {fr} /* {name} */; }};\n'
        )
        text = text.replace(
            "/* End PBXBuildFile section */",
            build_file + "/* End PBXBuildFile section */",
        )
        text = text.replace(
            "/* End PBXFileReference section */",
            file_ref + "/* End PBXFileReference section */",
        )

        # Add to Sources build phase of UITests target.
        sources_phase_pattern = re.compile(
            r"(" + UITESTS_SOURCES_PHASE_ID + r" /\* Sources \*/ = \{\s*"
            r"isa = PBXSourcesBuildPhase;\s*"
            r"buildActionMask = 2147483647;\s*"
            r"files = \([^)]*?)"
            r"(\);)",
            re.DOTALL,
        )
        m = sources_phase_pattern.search(text)
        if not m:
            print(f"ERROR: could not find UITests Sources phase {UITESTS_SOURCES_PHASE_ID}")
            return 1
        insert_at = m.end() - len(");")
        text = text[:insert_at] + f"\t\t\t\t{bf} /* {name} in Sources */,\n" + text[insert_at:]

        # Add to parent group's children.
        if group_name:
            target_group_id = subgroups[group_name]
            # The subgroup has children = ( ). Insert right after the opening paren.
            group_block_pattern = re.compile(
                r"(" + target_group_id + r" /\* " + re.escape(group_name) + r" \*/ = \{\s*"
                r"isa = PBXGroup;\s*"
                r"children = \()",
                re.DOTALL,
            )
            gm = group_block_pattern.search(text)
            if not gm:
                print(f"ERROR: could not find subgroup {group_name}")
                return 1
            insert_after = gm.end()
            text = text[:insert_after] + f"\n\t\t\t\t{fr} /* {name} */," + text[insert_after:]
        else:
            # Add directly to UITests root group.
            text = text.replace(
                f"\t\t\t\t1A2C8350A32724EACB324178 /* RecipeScalerNativeUITests.swift */,",
                f"\t\t\t\t1A2C8350A32724EACB324178 /* RecipeScalerNativeUITests.swift */,\n"
                f"\t\t\t\t{fr} /* {name} */,",
                1,
            )

        added += 1
        print(f"Added {rel}")

    if added:
        PBX.write_text(text)
    print(f"Done. {added} file(s) added.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
