#!/usr/bin/env python3
"""Add RecipeScalerNativeUITests native target to project.pbxproj.

The existing `RecipeScalerNativeUITests.swift` file is registered as a
PBXFileReference and in the RecipeScalerNativeUITests group, but no
PBXNativeTarget exists for it — so the scheme's TestableReference points
at a missing target and `xcodebuild test -only-testing:RecipeScalerNativeUITests`
fails with "isn't a member of the specified test plan or scheme".

This script creates a proper UI-testing bundle target that mirrors the
existing RecipeScalerNativeTests (unit-test) target structure but uses
productType = "com.apple.product-type.bundle.ui-testing".

Idempotent: if the target already exists, exits with no changes.
"""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBX = ROOT / "RecipeScalerNative.xcodeproj" / "project.pbxproj"

# Stable, descriptive 24-char hex IDs (Xcode accepts any uppercase hex).
# Pattern: UITESTNNNNNNNNNNNNNNNN — easy to grep in the future.
def nid(suffix: str) -> str:
    padded = suffix.ljust(16, "0")[:16]
    return f"UITEST{padded}"


# All IDs needed for a complete UI-test target.
IDS = {
    # Product reference (the .xctest bundle)
    "product_ref": nid("PROD0001"),
    # PBXNativeTarget
    "target": nid("TARGET001"),
    # Build phases
    "sources_phase": nid("SRCPHASE1"),
    "frameworks_phase": nid("FWKPHASE1"),
    "resources_phase": nid("RSCPHASE1"),
    # Build files
    "sources_build_file": nid("SRCBF001"),
    # Build configurations
    "debug_config": nid("DBGCFG001"),
    "release_config": nid("RLSCFG001"),
    # Configuration list
    "config_list": nid("CFGLIST01"),
    # Target dependency on RecipeScalerNative.app
    "target_dep": nid("TGTDEP001"),
    "target_proxy": nid("TGTPROXY1"),
}

# Stable IDs for the existing entities we reference.
APP_TARGET_ID = "D48135388848E9FFF6A87142"  # RecipeScalerNative.app target
APP_TARGET_NAME = "RecipeScalerNative"
UITESTS_SWIFT_FILE_REF = "1A2C8350A32724EACB324178"  # RecipeScalerNativeUITests.swift
UITESTS_SWIFT_NAME = "RecipeScalerNativeUITests.swift"
UITESTS_GROUP_ID = "EE830B9272D882874906264B"  # RecipeScalerNativeUITests group
UITESTS_INFO_PLIST_REF = "D94F9413AB80FC3DB95DCD1C"


def patch(text: str) -> str:
    # Idempotency check: if native target block already exists, do nothing.
    if f"{IDS['target']} /* RecipeScalerNativeUITests */ = {{\n\t\t\tisa = PBXNativeTarget;" in text:
        return text

    # 1. Product reference — add to PBXFileReference section.
    product_ref_line = (
        f"\t\t{IDS['product_ref']} /* RecipeScalerNativeUITests.xctest */ = "
        f"{{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; "
        f"includeInIndex = 0; name = RecipeScalerNativeUITests.xctest; "
        f"path = RecipeScalerNativeUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
    )
    text = text.replace(
        "/* End PBXFileReference section */",
        product_ref_line + "/* End PBXFileReference section */",
    )

    # 2. Add product to main group's children (where other .xctest products live).
    #    Anchor: line with RecipeScalerNativeTests.xctest in main group children.
    if f"{IDS['product_ref']} /* RecipeScalerNativeUITests.xctest */" not in text:
        text = text.replace(
            "FBED86F57850D8012BF9D4BD /* RecipeScalerNativeTests.xctest */,",
            "FBED86F57850D8012BF9D4BD /* RecipeScalerNativeTests.xctest */,\n"
            f"\t\t\t\t{IDS['product_ref']} /* RecipeScalerNativeUITests.xctest */,",
            1,
        )

    # 3. PBXBuildFile for the swift source.
    sources_build_file_line = (
        f"\t\t{IDS['sources_build_file']} /* {UITESTS_SWIFT_NAME} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {UITESTS_SWIFT_FILE_REF} /* {UITESTS_SWIFT_NAME} */; }};\n"
    )
    text = text.replace(
        "/* End PBXBuildFile section */",
        sources_build_file_line + "/* End PBXBuildFile section */",
    )

    # 4. PBXContainerItemProxy for target dependency proxy.
    container_proxy_block = (
        f"\t\t{IDS['target_proxy']} /* PBXContainerItemProxy */ = {{\n"
        f"\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = 5EE18DEE47E00A9648AA02B9 /* Project object */;\n"
        f"\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {APP_TARGET_ID};\n"
        f"\t\t\tremoteInfo = {APP_TARGET_NAME};\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End PBXContainerItemProxy section */",
        container_proxy_block + "/* End PBXContainerItemProxy section */",
    )

    # 5. PBXTargetDependency.
    target_dep_block = (
        f"\t\t{IDS['target_dep']} /* PBXTargetDependency */ = {{\n"
        f"\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\tname = {APP_TARGET_NAME};\n"
        f"\t\t\ttarget = {APP_TARGET_ID} /* {APP_TARGET_NAME} */;\n"
        f"\t\t\ttargetProxy = {IDS['target_proxy']} /* PBXContainerItemProxy */;\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End PBXTargetDependency section */",
        target_dep_block + "/* End PBXTargetDependency section */",
    )

    # 6. Sources build phase.
    sources_phase_block = (
        f"\t\t{IDS['sources_phase']} /* Sources */ = {{\n"
        f"\t\t\tisa = PBXSourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{IDS['sources_build_file']} /* {UITESTS_SWIFT_NAME} in Sources */,\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End PBXSourcesBuildPhase section */",
        sources_phase_block + "/* End PBXSourcesBuildPhase section */",
    )

    # 7. Frameworks build phase (empty — UI tests use XCTest from Xcode SDK).
    frameworks_phase_block = (
        f"\t\t{IDS['frameworks_phase']} /* Frameworks */ = {{\n"
        f"\t\t\tisa = PBXFrameworksBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End PBXFrameworksBuildPhase section */",
        frameworks_phase_block + "/* End PBXFrameworksBuildPhase section */",
    )

    # 8. Resources build phase (Info.plist is implicit, no resources needed).
    resources_phase_block = (
        f"\t\t{IDS['resources_phase']} /* Resources */ = {{\n"
        f"\t\t\tisa = PBXResourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End PBXResourcesBuildPhase section */",
        resources_phase_block + "/* End PBXResourcesBuildPhase section */",
    )

    # 9. XCBuildConfiguration Debug.
    debug_config_block = (
        f"\t\t{IDS['debug_config']} /* Debug */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\tCLANG_ENABLE_OBJC_WEAK = NO;\n"
        f"\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        f"\t\t\t\tDEVELOPMENT_TEAM = ZBPX4JYT24;\n"
        f"\t\t\t\tINFOPLIST_FILE = RecipeScalerNativeUITests/Info.plist;\n"
        f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n"
        f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
        f"\t\t\t\t\t\"$(inherited)\",\n"
        f"\t\t\t\t\t\"@executable_path/Frameworks\",\n"
        f"\t\t\t\t\t\"@loader_path/Frameworks\",\n"
        f"\t\t\t\t);\n"
        f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = ru.recipescaler.RecipeScalerUITests;\n"
        f"\t\t\t\tSDKROOT = iphoneos;\n"
        f"\t\t\t\tSWIFT_VERSION = 5.9;\n"
        f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";\n"
        f"\t\t\t\tTEST_TARGET_NAME = {APP_TARGET_NAME};\n"
        f"\t\t\t}};\n"
        f"\t\t\tname = Debug;\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End XCBuildConfiguration section */",
        debug_config_block + "/* End XCBuildConfiguration section */",
    )

    # 10. XCBuildConfiguration Release.
    release_config_block = (
        f"\t\t{IDS['release_config']} /* Release */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\tCLANG_ENABLE_OBJC_WEAK = NO;\n"
        f"\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        f"\t\t\t\tDEVELOPMENT_TEAM = ZBPX4JYT24;\n"
        f"\t\t\t\tINFOPLIST_FILE = RecipeScalerNativeUITests/Info.plist;\n"
        f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n"
        f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
        f"\t\t\t\t\t\"$(inherited)\",\n"
        f"\t\t\t\t\t\"@executable_path/Frameworks\",\n"
        f"\t\t\t\t\t\"@loader_path/Frameworks\",\n"
        f"\t\t\t\t);\n"
        f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = ru.recipescaler.RecipeScalerUITests;\n"
        f"\t\t\t\tSDKROOT = iphoneos;\n"
        f"\t\t\t\tSWIFT_VERSION = 5.9;\n"
        f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";\n"
        f"\t\t\t\tTEST_TARGET_NAME = {APP_TARGET_NAME};\n"
        f"\t\t\t\tVALIDATE_PRODUCT = YES;\n"
        f"\t\t\t}};\n"
        f"\t\t\tname = Release;\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End XCBuildConfiguration section */",
        release_config_block + "/* End XCBuildConfiguration section */",
    )

    # 11. XCConfigurationList for the target.
    config_list_block = (
        f"\t\t{IDS['config_list']} /* Build configuration list for PBXNativeTarget \"RecipeScalerNativeUITests\" */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{IDS['debug_config']} /* Debug */,\n"
        f"\t\t\t\t{IDS['release_config']} /* Release */,\n"
        f"\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End XCConfigurationList section */",
        config_list_block + "/* End XCConfigurationList section */",
    )

    # 12. PBXNativeTarget — the main entry. Insert before End of section.
    native_target_block = (
        f"\t\t{IDS['target']} /* RecipeScalerNativeUITests */ = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {IDS['config_list']} /* Build configuration list for PBXNativeTarget \"RecipeScalerNativeUITests\" */;\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{IDS['sources_phase']} /* Sources */,\n"
        f"\t\t\t\t{IDS['frameworks_phase']} /* Frameworks */,\n"
        f"\t\t\t\t{IDS['resources_phase']} /* Resources */,\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n"
        f"\t\t\t);\n"
        f"\t\t\tdependencies = (\n"
        f"\t\t\t\t{IDS['target_dep']} /* PBXTargetDependency */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = RecipeScalerNativeUITests;\n"
        f"\t\t\tpackageProductDependencies = (\n"
        f"\t\t\t);\n"
        f"\t\t\tproductName = RecipeScalerNativeUITests;\n"
        f"\t\t\tproductReference = {IDS['product_ref']} /* RecipeScalerNativeUITests.xctest */;\n"
        f"\t\t\tproductType = \"com.apple.product-type.bundle.ui-testing\";\n"
        f"\t\t}};\n"
    )
    text = text.replace(
        "/* End PBXNativeTarget section */",
        native_target_block + "/* End PBXNativeTarget section */",
    )

    # 13. Register target in project.targets list (PBXProject section).
    text = text.replace(
        "\t\t\t\t68F78791FDCF7C81D2E64394 /* RecipeScalerNativeTests */,\n"
        "\t\t\t\t3B473A960C22798BD57B5308 /* HomeWidgetExtension */,",
        "\t\t\t\t68F78791FDCF7C81D2E64394 /* RecipeScalerNativeTests */,\n"
        f"\t\t\t\t{IDS['target']} /* RecipeScalerNativeUITests */,\n"
        "\t\t\t\t3B473A960C22798BD57B5308 /* HomeWidgetExtension */,",
        1,
    )

    return text


def main() -> int:
    text = PBX.read_text()
    patched = patch(text)
    if patched == text:
        print("No changes — target already exists.")
        return 0
    PBX.write_text(patched)
    print(f"Created RecipeScalerNativeUITests native target with ID {IDS['target']}")
    print(f"  product reference: {IDS['product_ref']}")
    print(f"  sources phase:     {IDS['sources_phase']}")
    print(f"  config list:       {IDS['config_list']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
