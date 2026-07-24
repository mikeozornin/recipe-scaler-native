#!/usr/bin/env python3
"""
Add RecipeScalerCore, ShareExtension, and ActionExtension targets to project.pbxproj.
Run from repo root: python3 scripts/add_share_extension_targets.py
"""
from __future__ import annotations

import re
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBX = ROOT / "RecipeScalerNative.xcodeproj" / "project.pbxproj"

MAIN_APP_TARGET = "D48135388848E9FFF6A87142"
MAIN_SOURCES_PHASE = "72A876A1FC6083C3018BF18A"
MAIN_FRAMEWORKS_PHASE = "B723C003B318C8956FF9B79E"
MAIN_GROUP = "3EE100FD9182D08689E780CD"
PRODUCTS_GROUP = "76B3DA4533E03AE5D9E730B3"
PROJECT_OBJECT = "5EE18DEE47E00A9648AA02B9"

# Remove these from main app Sources (now in RecipeScalerCore)
MAIN_SOURCE_REMOVALS = {
    "0E2206C1B11DB3E5FF441BD4",  # APIClient.swift
    "E5F60718293A4B702C6563FF",  # APIClient+Requests.swift
    "E5F60718293A4B70652DFDEF",  # RecipeImportAPI.swift
    "E5F60718293A4B7099AAB002",  # ImportContentClassifier.swift
    "E5F60718293A4B7099AAB004",  # ImportPhotoValidator.swift
    "E5F60718293A4B7099AAB006",  # ImportErrorLocalizer.swift
    "897E98ADC8B4B1C64BF6AA54",  # Config.swift
    "D4E5F6A7B8C9D0E1F2A3B4C6",  # SharedAuthStore.swift
}


def uid() -> str:
    return uuid.uuid4().hex[:24].upper()


def main() -> None:
    text = PBX.read_text(encoding="utf-8")
    if "RecipeScalerCore" in text and "ShareExtension" in text and "product-type.app-extension" in text:
        print("Targets already present in pbxproj; skipping.")
        return

    # --- IDs ---
    core_target = uid()
    share_target = uid()
    action_target = uid()

    core_product = uid()
    share_product = uid()
    action_product = uid()

    core_sources = uid()
    core_resources = uid()
    core_frameworks = uid()
    share_sources = uid()
    share_frameworks = uid()
    share_resources = uid()
    action_sources = uid()
    action_frameworks = uid()
    action_resources = uid()

    embed_frameworks = uid()
    embed_extensions = uid()

    dep_core = uid()
    dep_share = uid()
    dep_action = uid()
    proxy_core = uid()
    proxy_share = uid()
    proxy_action = uid()

    core_fw_build = uid()
    core_fw_ref = uid()
    share_fw_build = uid()
    share_fw_ref = uid()
    action_fw_build = uid()
    action_fw_ref = uid()

    embed_core_build = uid()
    embed_share_build = uid()
    embed_action_build = uid()

    core_bcl = uid()
    share_bcl = uid()
    action_bcl = uid()
    core_dbg = uid()
    core_rel = uid()
    share_dbg = uid()
    share_rel = uid()
    action_dbg = uid()
    action_rel = uid()

    group_core = uid()
    group_share = uid()
    group_action = uid()

    # File references (path relative to group)
    files_core = [
        ("RecipeScalerCore.swift", "RecipeScalerCore/RecipeScalerCore.swift"),
        ("SharedAuthStore.swift", "RecipeScalerCore/Auth/SharedAuthStore.swift"),
        ("Config.swift", "RecipeScalerCore/Config/Config.swift"),
        ("APIClient.swift", "RecipeScalerCore/Networking/APIClient.swift"),
        ("APIClient+Requests.swift", "RecipeScalerCore/Networking/APIClient+Requests.swift"),
        ("RecipeImportAPI.swift", "RecipeScalerCore/Import/RecipeImportAPI.swift"),
        ("ImportContentClassifier.swift", "RecipeScalerCore/Import/ImportContentClassifier.swift"),
        ("ImportPhotoValidator.swift", "RecipeScalerCore/Import/ImportPhotoValidator.swift"),
        ("ImportErrorLocalizer.swift", "RecipeScalerCore/Import/ImportErrorLocalizer.swift"),
        ("ShareContentLoader.swift", "RecipeScalerCore/UI/ShareContentLoader.swift"),
        ("ShareView.swift", "RecipeScalerCore/UI/ShareView.swift"),
        ("Shared.xcstrings", "RecipeScalerCore/Resources/Shared.xcstrings"),
    ]
    files_share = [
        ("ShareViewController.swift", "ShareExtension/ShareViewController.swift"),
        ("Info.plist", "ShareExtension/Info.plist"),
        ("ShareExtension.entitlements", "ShareExtension/ShareExtension.entitlements"),
    ]
    files_action = [
        ("ActionViewController.swift", "ActionExtension/ActionViewController.swift"),
        ("GetURLFromPage.js", "ActionExtension/GetURLFromPage.js"),
        ("Info.plist", "ActionExtension/Info.plist"),
        ("ActionExtension.entitlements", "ActionExtension/ActionExtension.entitlements"),
    ]

    core_refs: dict[str, str] = {}
    core_builds: dict[str, str] = {}
    for name, path in files_core:
        ref = uid()
        build = uid()
        core_refs[name] = ref
        core_builds[name] = build

    share_refs = {n: uid() for n, _ in files_share}
    share_builds = {n: uid() for n, _ in files_share if n.endswith(".swift")}

    action_refs = {n: uid() for n, _ in files_action}
    action_builds_swift = {n: uid() for n, _ in files_action if n.endswith(".swift")}
    action_build_js = uid()

    # PBXFileReference block additions
    file_ref_lines = []
    for name, path in files_core:
        r = core_refs[name]
        if name.endswith(".xcstrings"):
            ft = "text.json.xcstrings"
        else:
            ft = "sourcecode.swift"
        file_ref_lines.append(
            f"\t\t{r} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {path.split('/')[-1] if '/' in path else name}; sourceTree = \"<group>\"; }};"
        )
    for name, path in files_share:
        r = share_refs[name]
        if name.endswith(".plist"):
            ft = "text.plist.xml" if name == "Info.plist" else "text.plist.entitlements"
        else:
            ft = "sourcecode.swift"
        file_ref_lines.append(
            f"\t\t{r} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {name}; sourceTree = \"<group>\"; }};"
        )
    for name, path in files_action:
        r = action_refs[name]
        if name.endswith(".js"):
            ft = "sourcecode.javascript"
        elif name.endswith(".plist"):
            ft = "text.plist.xml" if name == "Info.plist" else "text.plist.entitlements"
        else:
            ft = "sourcecode.swift"
        file_ref_lines.append(
            f"\t\t{r} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {name}; sourceTree = \"<group>\"; }};"
        )

    file_ref_lines.append(
        f"\t\t{core_product} /* RecipeScalerCore.framework */ = {{isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = RecipeScalerCore.framework; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    file_ref_lines.append(
        f"\t\t{share_product} /* ShareExtension.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = ShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    file_ref_lines.append(
        f"\t\t{action_product} /* ActionExtension.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = ActionExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )

    # PBXBuildFile
    build_file_lines = []
    for name, _ in files_core:
        if name.endswith(".swift"):
            build_file_lines.append(
                f"\t\t{core_builds[name]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {core_refs[name]} /* {name} */; }};"
            )
        elif name.endswith(".xcstrings"):
            build_file_lines.append(
                f"\t\t{core_builds[name]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {core_refs[name]} /* {name} */; }};"
            )

    build_file_lines.append(
        f"\t\t{core_fw_build} /* RecipeScalerCore.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {core_fw_ref} /* RecipeScalerCore.framework */; }};"
    )
    build_file_lines.append(
        f"\t\t{share_fw_build} /* RecipeScalerCore.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {core_fw_ref} /* RecipeScalerCore.framework */; }};"
    )
    build_file_lines.append(
        f"\t\t{action_fw_build} /* RecipeScalerCore.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {core_fw_ref} /* RecipeScalerCore.framework */; }};"
    )
    build_file_lines.append(
        f"\t\t{embed_core_build} /* RecipeScalerCore.framework in Embed Frameworks */ = {{isa = PBXBuildFile; fileRef = {core_fw_ref} /* RecipeScalerCore.framework */; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};"
    )
    build_file_lines.append(
        f"\t\t{embed_share_build} /* ShareExtension.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {share_product} /* ShareExtension.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    build_file_lines.append(
        f"\t\t{embed_action_build} /* ActionExtension.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {action_product} /* ActionExtension.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )

    for name in share_builds:
        build_file_lines.append(
            f"\t\t{share_builds[name]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {share_refs[name]} /* {name} */; }};"
        )
    for name in action_builds_swift:
        build_file_lines.append(
            f"\t\t{action_builds_swift[name]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {action_refs[name]} /* {name} */; }};"
        )
    build_file_lines.append(
        f"\t\t{action_build_js} /* GetURLFromPage.js in Resources */ = {{isa = PBXBuildFile; fileRef = {action_refs['GetURLFromPage.js']} /* GetURLFromPage.js */; }};"
    )

    # core_fw_ref is built product reference - use core_product for linking from other targets
    # Fix: link against core_product file ref
    build_file_lines = [ln.replace(core_fw_ref, core_product) for ln in build_file_lines]
    core_fw_ref = core_product  # for framework phases

    # Insert build files before /* End PBXBuildFile section */
    text = text.replace(
        "/* End PBXBuildFile section */",
        "\n".join(build_file_lines) + "\n/* End PBXBuildFile section */",
    )

    # Insert file refs - fix paths for core files (use full relative path in group)
    # Regenerate file refs with correct paths
    file_ref_lines = []
    core_group_children = []
    for name, rel in files_core:
        r = core_refs[name]
        base = rel.split("/")[-1]
        if name.endswith(".xcstrings"):
            ft = "text.json.xcstrings"
        else:
            ft = "sourcecode.swift"
        # path = filename only, group has path RecipeScalerCore with subgroups - use path from rel
        parent_path = "/".join(rel.split("/")[:-1])
        file_ref_lines.append(
            f"\t\t{r} /* {base} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {base}; sourceTree = \"<group>\"; }};"
        )
        core_group_children.append(f"{r} /* {base} */")

    share_children = [f"{share_refs[n]} /* {n} */" for n, _ in files_share]
    action_children = [f"{action_refs[n]} /* {n} */" for n, _ in files_action]

    for name, _ in files_share:
        r = share_refs[name]
        if name.endswith(".entitlements"):
            ft = "text.plist.entitlements"
        elif name.endswith(".plist"):
            ft = "text.plist.xml"
        else:
            ft = "sourcecode.swift"
        file_ref_lines.append(
            f"\t\t{r} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {name}; sourceTree = \"<group>\"; }};"
        )
    for name, _ in files_action:
        r = action_refs[name]
        if name.endswith(".js"):
            ft = "sourcecode.javascript"
        elif name.endswith(".entitlements"):
            ft = "text.plist.entitlements"
        elif name.endswith(".plist"):
            ft = "text.plist.xml"
        else:
            ft = "sourcecode.swift"
        file_ref_lines.append(
            f"\t\t{r} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {name}; sourceTree = \"<group>\"; }};"
        )

    file_ref_lines.extend([
        f"\t\t{core_product} /* RecipeScalerCore.framework */ = {{isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = RecipeScalerCore.framework; sourceTree = BUILT_PRODUCTS_DIR; }};",
        f"\t\t{share_product} /* ShareExtension.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = ShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};",
        f"\t\t{action_product} /* ActionExtension.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = ActionExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};",
    ])

    text = text.replace(
        "/* End PBXFileReference section */",
        "\n".join(file_ref_lines) + "\n/* End PBXFileReference section */",
    )

    # Groups - simplified flat groups with path
    groups_block = f"""
\t\t{group_core} /* RecipeScalerCore */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join('\t\t\t\t' + c + ',' for c in core_group_children)}
\t\t\t);
\t\t\tpath = RecipeScalerCore;
\t\t\tsourceTree = \"<group>\";
\t\t}};
\t\t{group_share} /* ShareExtension */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join('\t\t\t\t' + c + ',' for c in share_children)}
\t\t\t);
\t\t\tpath = ShareExtension;
\t\t\tsourceTree = \"<group>\";
\t\t}};
\t\t{group_action} /* ActionExtension */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join('\t\t\t\t' + c + ',' for c in action_children)}
\t\t\t);
\t\t\tpath = ActionExtension;
\t\t\tsourceTree = \"<group>\";
\t\t}};
"""

    text = text.replace("/* End PBXGroup section */", groups_block + "\t/* End PBXGroup section */")

    # mainGroup children
    text = text.replace(
        f"\t\t\tchildren = (\n\t\t\t\t02AE57AC5FA5124D4D412BDA /* RecipeScalerNative */,",
        f"\t\t\tchildren = (\n\t\t\t\t{group_core} /* RecipeScalerCore */,\n\t\t\t\t{group_share} /* ShareExtension */,\n\t\t\t\t{group_action} /* ActionExtension */,\n\t\t\t\t02AE57AC5FA5124D4D412BDA /* RecipeScalerNative */,",
    )

    # Products group
    text = re.sub(
        r"(76B3DA4533E03AE5D9E730B3 /\* Products \*/ = \{[^}]+children = \([^)]+)",
        lambda m: m.group(0)
        + f"\n\t\t\t\t{core_product} /* RecipeScalerCore.framework */,\n\t\t\t\t{share_product} /* ShareExtension.appex */,\n\t\t\t\t{action_product} /* ActionExtension.appex */,",
        text,
        count=1,
    )

    # Frameworks phases
    frameworks_phases = f"""
\t\t{core_frameworks} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{share_frameworks} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{share_fw_build} /* RecipeScalerCore.framework in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{action_frameworks} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{action_fw_build} /* RecipeScalerCore.framework in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""
    text = text.replace("/* End PBXFrameworksBuildPhase section */", frameworks_phases + "\t/* End PBXFrameworksBuildPhase section */")

    # Main app link RecipeScalerCore
    text = text.replace(
        "\t\t\tfiles = (\n\t\t\t\tAABB0001000000010000AA01 /* YrsXCFramework.xcframework in Frameworks */,",
        f"\t\t\tfiles = (\n\t\t\t\t{core_fw_build} /* RecipeScalerCore.framework in Frameworks */,\n\t\t\t\tAABB0001000000010000AA01 /* YrsXCFramework.xcframework in Frameworks */,",
    )

    # Resources phases
    core_res_files = "\n".join(
        f"\t\t\t\t{core_builds[n]} /* {n} in Resources */,"
        for n, _ in files_core
        if n.endswith(".xcstrings")
    )
    resources_phases = f"""
\t\t{core_resources} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{core_res_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{share_resources} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{action_resources} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{action_build_js} /* GetURLFromPage.js in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""
    text = text.replace("/* End PBXResourcesBuildPhase section */", resources_phases + "\t/* End PBXResourcesBuildPhase section */")

    # Sources phases for new targets
    core_src_files = "\n".join(
        f"\t\t\t\t{core_builds[n]} /* {n} in Sources */,"
        for n, _ in files_core
        if n.endswith(".swift")
    )
    share_src_files = "\n".join(
        f"\t\t\t\t{share_builds[n]} /* {n} in Sources */," for n in share_builds
    )
    action_src_files = "\n".join(
        f"\t\t\t\t{action_builds_swift[n]} /* {n} in Sources */," for n in action_builds_swift
    )

    sources_add = f"""
\t\t{core_sources} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{core_src_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{share_sources} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{share_src_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{action_sources} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{action_src_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""
    text = text.replace("/* End PBXSourcesBuildPhase section */", sources_add + "\t/* End PBXSourcesBuildPhase section */")

    # Remove duplicate sources from main app
    for bid in MAIN_SOURCE_REMOVALS:
        text = re.sub(rf"\t\t\t\t{bid} /\* [^*]+ \*/ in Sources \*/,\n", "", text)

    # Copy files embed
    copy_phases = f"""
\t\t{embed_frameworks} /* Embed Frameworks */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = \"\";
\t\t\tdstSubfolderSpec = 10;
\t\t\tfiles = (
\t\t\t\t{embed_core_build} /* RecipeScalerCore.framework in Embed Frameworks */,
\t\t\t);
\t\t\tname = \"Embed Frameworks\";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{embed_extensions} /* Embed App Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = \"\";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{embed_share_build} /* ShareExtension.appex in Embed App Extensions */,
\t\t\t\t{embed_action_build} /* ActionExtension.appex in Embed App Extensions */,
\t\t\t);
\t\t\tname = \"Embed App Extensions\";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */"""
    if "/* End PBXCopyFilesBuildPhase section */" in text:
        text = text.replace("/* End PBXCopyFilesBuildPhase section */", copy_phases)
    else:
        text = text.replace(
            "/* End PBXResourcesBuildPhase section */",
            "/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXCopyFilesBuildPhase section */\n"
            + copy_phases.replace("/* End PBXCopyFilesBuildPhase section */", ""),
        )

    # Container proxies & dependencies
    container_block = f"""
/* Begin PBXContainerItemProxy section */
\t\t{proxy_core} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROJECT_OBJECT} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {core_target};
\t\t\tremoteInfo = RecipeScalerCore;
\t\t}};
\t\t{proxy_share} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROJECT_OBJECT} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {share_target};
\t\t\tremoteInfo = ShareExtension;
\t\t}};
\t\t{proxy_action} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROJECT_OBJECT} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {action_target};
\t\t\tremoteInfo = ActionExtension;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
\t\t{dep_core} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {core_target} /* RecipeScalerCore */;
\t\t\ttargetProxy = {proxy_core} /* PBXContainerItemProxy */;
\t\t}};
\t\t{dep_share} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {share_target} /* ShareExtension */;
\t\t\ttargetProxy = {proxy_share} /* PBXContainerItemProxy */;
\t\t}};
\t\t{dep_action} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {action_target} /* ActionExtension */;
\t\t\ttargetProxy = {proxy_action} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */
"""
    text = text.replace("/* Begin PBXNativeTarget section */", container_block + "\n/* Begin PBXNativeTarget section */")

    # Native targets
    native_targets = f"""
\t\t{core_target} /* RecipeScalerCore */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {core_bcl} /* Build configuration list for PBXNativeTarget \"RecipeScalerCore\" */;
\t\t\tbuildPhases = (
\t\t\t\t{core_sources} /* Sources */,
\t\t\t\t{core_frameworks} /* Frameworks */,
\t\t\t\t{core_resources} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = RecipeScalerCore;
\t\t\tproductName = RecipeScalerCore;
\t\t\tproductReference = {core_product} /* RecipeScalerCore.framework */;
\t\t\tproductType = \"com.apple.product-type.framework\";
\t\t}};
\t\t{share_target} /* ShareExtension */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {share_bcl} /* Build configuration list for PBXNativeTarget \"ShareExtension\" */;
\t\t\tbuildPhases = (
\t\t\t\t{share_sources} /* Sources */,
\t\t\t\t{share_frameworks} /* Frameworks */,
\t\t\t\t{share_resources} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{dep_core} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = ShareExtension;
\t\t\tproductName = ShareExtension;
\t\t\tproductReference = {share_product} /* ShareExtension.appex */;
\t\t\tproductType = \"com.apple.product-type.app-extension\";
\t\t}};
\t\t{action_target} /* ActionExtension */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {action_bcl} /* Build configuration list for PBXNativeTarget \"ActionExtension\" */;
\t\t\tbuildPhases = (
\t\t\t\t{action_sources} /* Sources */,
\t\t\t\t{action_frameworks} /* Frameworks */,
\t\t\t\t{action_resources} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{dep_core} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = ActionExtension;
\t\t\tproductName = ActionExtension;
\t\t\tproductReference = {action_product} /* ActionExtension.appex */;
\t\t\tproductType = \"com.apple.product-type.app-extension\";
\t\t}};
"""
    text = text.replace(
        "/* End PBXNativeTarget section */",
        native_targets + "\t/* End PBXNativeTarget section */",
    )

    # Update main app target phases and dependencies
    text = text.replace(
        f"\t\t\tbuildPhases = (\n\t\t\t\t{MAIN_SOURCES_PHASE} /* Sources */,\n\t\t\t\t8BDB73332B8DC3D03047EC69 /* Resources */,\n\t\t\t\t{MAIN_FRAMEWORKS_PHASE} /* Frameworks */,\n\t\t\t);",
        f"\t\t\tbuildPhases = (\n\t\t\t\t{MAIN_SOURCES_PHASE} /* Sources */,\n\t\t\t\t8BDB73332B8DC3D03047EC69 /* Resources */,\n\t\t\t\t{MAIN_FRAMEWORKS_PHASE} /* Frameworks */,\n\t\t\t\t{embed_frameworks} /* Embed Frameworks */,\n\t\t\t\t{embed_extensions} /* Embed App Extensions */,\n\t\t\t);",
    )
    text = text.replace(
        f"\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = RecipeScalerNative;",
        f"\t\t\tdependencies = (\n\t\t\t\t{dep_core} /* PBXTargetDependency */,\n\t\t\t\t{dep_share} /* PBXTargetDependency */,\n\t\t\t\t{dep_action} /* PBXTargetDependency */,\n\t\t\t);\n\t\t\tname = RecipeScalerNative;",
    )

    text = text.replace(
        "\t\t\ttargets = (\n\t\t\t\tD48135388848E9FFF6A87142 /* RecipeScalerNative */,\n\t\t\t);",
        f"\t\t\ttargets = (\n\t\t\t\tD48135388848E9FFF6A87142 /* RecipeScalerNative */,\n\t\t\t\t{core_target} /* RecipeScalerCore */,\n\t\t\t\t{share_target} /* ShareExtension */,\n\t\t\t\t{action_target} /* ActionExtension */,\n\t\t\t);",
    )

    # XCBuildConfiguration for new targets
    def fw_settings(bundle_id: str, plist: str, ent: str, ext_api: str) -> str:
        return f"""
\t\t\tbuildSettings = {{
\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = {ext_api};
\t\t\t\tCODE_SIGN_ENTITLEMENTS = {ent};
\t\t\t\tCODE_SIGN_IDENTITY = \"iPhone Developer\";
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = ZBPX4JYT24;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = {plist};
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t\"$(inherited)\",
\t\t\t\t\t\"@executable_path/Frameworks\",
\t\t\t\t\t\"@executable_path/../../Frameworks\",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {bundle_id};
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";
\t\t\t}};
"""

    core_fw_settings = """
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_IDENTITY = \"iPhone Developer\";
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEFINES_MODULE = YES;
\t\t\t\tDEVELOPMENT_TEAM = ZBPX4JYT24;
\t\t\t\tDYLIB_INSTALL_NAME_BASE = \"@rpath\";
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = RecipeScalerCore;
\t\t\t\tINSTALL_PATH = \"$(LOCAL_LIBRARY_DIR)/Frameworks\";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t\"$(inherited)\",
\t\t\t\t\t\"@executable_path/Frameworks\",
\t\t\t\t\t\"@loader_path/Frameworks\",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = ru.recipescaler.RecipeScaler.Core;
\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME:c99extidentifier)\";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";
\t\t\t};
"""

    xc_configs = f"""
\t\t{core_dbg} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
{core_fw_settings}
\t\t\tname = Debug;
\t\t}};
\t\t{core_rel} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
{core_fw_settings}
\t\t\tname = Release;
\t\t}};
\t\t{share_dbg} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
{fw_settings('ru.recipescaler.RecipeScaler.Share', 'ShareExtension/Info.plist', 'ShareExtension/ShareExtension.entitlements', 'YES')}
\t\t\tname = Debug;
\t\t}};
\t\t{share_rel} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
{fw_settings('ru.recipescaler.RecipeScaler.Share', 'ShareExtension/Info.plist', 'ShareExtension/ShareExtension.entitlements', 'YES')}
\t\t\tname = Release;
\t\t}};
\t\t{action_dbg} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
{fw_settings('ru.recipescaler.RecipeScaler.Action', 'ActionExtension/Info.plist', 'ActionExtension/ActionExtension.entitlements', 'YES')}
\t\t\tname = Debug;
\t\t}};
\t\t{action_rel} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
{fw_settings('ru.recipescaler.RecipeScaler.Action', 'ActionExtension/Info.plist', 'ActionExtension/ActionExtension.entitlements', 'YES')}
\t\t\tname = Release;
\t\t}};
"""
    text = text.replace("/* End XCBuildConfiguration section */", xc_configs + "\t/* End XCBuildConfiguration section */")

    xc_lists = f"""
\t\t{core_bcl} /* Build configuration list for PBXNativeTarget \"RecipeScalerCore\" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{core_dbg} /* Debug */,
\t\t\t\t{core_rel} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Debug;
\t\t}};
\t\t{share_bcl} /* Build configuration list for PBXNativeTarget \"ShareExtension\" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{share_dbg} /* Debug */,
\t\t\t\t{share_rel} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Debug;
\t\t}};
\t\t{action_bcl} /* Build configuration list for PBXNativeTarget \"ActionExtension\" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{action_dbg} /* Debug */,
\t\t\t\t{action_rel} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Debug;
\t\t}};
"""
    text = text.replace("/* End XCConfigurationList section */", xc_lists + "\t/* End XCConfigurationList section */")

    # Fix core group: files are in subdirs - Xcode needs correct paths
    # Use individual file refs with path including subfolder - update refs to use path RecipeScalerCore/Auth/...
    for name, rel in files_core:
        r = core_refs[name]
        text = text.replace(
            f"path = {rel.split('/')[-1]}; sourceTree = \"<group>\"; }};",
            f"path = {rel}; sourceTree = \"<group>\"; }};",
            1,
        )

    PBX.write_text(text, encoding="utf-8")
    print("Updated project.pbxproj with RecipeScalerCore, ShareExtension, ActionExtension targets.")


if __name__ == "__main__":
    main()