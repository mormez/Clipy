#!/usr/bin/env python3
"""Generates Clipy.xcodeproj/project.pbxproj"""

import os

# ── UUID registry ──────────────────────────────────────────────────
def u(n): return f"A1B2C3D4E5F6{n:04X}00"   # 24-char padded UUIDs

PROJECT       = u(0x0001)
TARGET        = u(0x0002)
PRODUCT_APP   = u(0x0003)
MAIN_GROUP    = u(0x0010)
CLIPY_GROUP   = u(0x0011)
PRODUCTS_GRP  = u(0x0012)
SRC_BUILD     = u(0x0020)   # PBXSourcesBuildPhase
RES_BUILD     = u(0x0021)   # PBXResourcesBuildPhase
FWK_BUILD     = u(0x0022)   # PBXFrameworksBuildPhase
CFG_PROJ_DBG  = u(0x0030)
CFG_PROJ_REL  = u(0x0031)
CFG_TGT_DBG   = u(0x0032)
CFG_TGT_REL   = u(0x0033)
CFGL_PROJ     = u(0x0034)
CFGL_TGT      = u(0x0035)

# source swift files
SOURCES = [
    "main.swift",
    "AppDelegate.swift",
    "ClipItem.swift",
    "ClipboardHistory.swift",
    "ClipboardMonitor.swift",
    "PasteService.swift",
    "HotkeyManager.swift",
    "Snippet.swift",
    "SnippetFolder.swift",
    "SnippetManager.swift",
    "Preferences.swift",
    "MenuBarManager.swift",
    "PreferencesWindowController.swift",
    "SnippetsEditorWindowController.swift",
    "Extensions.swift",
]

# resource files
RESOURCES = ["Assets.xcassets"]

# map filename → (fileRef UUID, buildFile UUID)
refs = {}
for i, f in enumerate(SOURCES + RESOURCES):
    refs[f] = (u(0x0100 + i), u(0x0200 + i))

INFOPLIST_REF    = u(0x0300)
ENTITLEMENTS_REF = u(0x0301)

# ── helpers ────────────────────────────────────────────────────────
def file_type(name):
    if name.endswith(".swift"): return "sourcecode.swift"
    if name == "Assets.xcassets": return "folder.assetcatalog"
    if name.endswith(".plist"): return "text.plist.xml"
    if name.endswith(".entitlements"): return "text.plist.entitlements"
    return "file"

def pbx_build_files():
    lines = []
    for f in SOURCES:
        fref, bref = refs[f]
        lines.append(f'\t\t{bref} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {f} */; }};')
    for f in RESOURCES:
        fref, bref = refs[f]
        lines.append(f'\t\t{bref} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {f} */; }};')
    return "\n".join(lines)

def pbx_file_references():
    lines = []
    for f in SOURCES + RESOURCES:
        fref, _ = refs[f]
        ft = file_type(f)
        lines.append(f'\t\t{fref} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {f}; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{INFOPLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{ENTITLEMENTS_REF} /* Clipy.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Clipy.entitlements; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{PRODUCT_APP} /* Clipy.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Clipy.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
    return "\n".join(lines)

def clipy_group_children():
    children = [refs[f][0] for f in SOURCES + RESOURCES]
    children += [INFOPLIST_REF, ENTITLEMENTS_REF]
    return "\n".join(f"\t\t\t\t{c}," for c in children)

def sources_phase_files():
    return "\n".join(f"\t\t\t\t{refs[f][1]} /* {f} in Sources */," for f in SOURCES)

def resources_phase_files():
    return "\n".join(f"\t\t\t\t{refs[f][1]} /* {f} in Resources */," for f in RESOURCES)

# ── build settings ─────────────────────────────────────────────────
COMMON_PROJECT = """
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tSWIFT_VERSION = 5.0;"""

COMMON_TARGET = f"""
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Clipy/Clipy.entitlements;
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tENABLE_HARDENED_RUNTIME = NO;
\t\t\t\tINFOPLIST_FILE = Clipy/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.clipy.ModernClipy;
\t\t\t\tPRODUCT_NAME = ModernClipy;
\t\t\t\tSWIFT_VERSION = 5.0;"""

pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{pbx_build_files()}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{pbx_file_references()}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FWK_BUILD} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{MAIN_GROUP} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{CLIPY_GROUP} /* Clipy */,
\t\t\t\t{PRODUCTS_GRP} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{CLIPY_GROUP} /* Clipy */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{clipy_group_children()}
\t\t\t);
\t\t\tname = Clipy;
\t\t\tpath = Clipy;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{PRODUCTS_GRP} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{PRODUCT_APP} /* Clipy.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{TARGET} /* Clipy */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {CFGL_TGT} /* Build configuration list for PBXNativeTarget "Clipy" */;
\t\t\tbuildPhases = (
\t\t\t\t{SRC_BUILD} /* Sources */,
\t\t\t\t{RES_BUILD} /* Resources */,
\t\t\t\t{FWK_BUILD} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Clipy;
\t\t\tproductName = Clipy;
\t\t\tproductReference = {PRODUCT_APP} /* Clipy.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{PROJECT} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{TARGET} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {CFGL_PROJ} /* Build configuration list for PBXProject "Clipy" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP};
\t\t\tproductRefGroup = {PRODUCTS_GRP} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET} /* Clipy */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RES_BUILD} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resources_phase_files()}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{SRC_BUILD} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{sources_phase_files()}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{CFG_PROJ_DBG} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{COMMON_PROJECT}
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{CFG_PROJ_REL} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{COMMON_PROJECT}
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{CFG_TGT_DBG} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{COMMON_TARGET}
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{CFG_TGT_REL} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{COMMON_TARGET}
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{CFGL_PROJ} /* Build configuration list for PBXProject "Clipy" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{CFG_PROJ_DBG} /* Debug */,
\t\t\t\t{CFG_PROJ_REL} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{CFGL_TGT} /* Build configuration list for PBXNativeTarget "Clipy" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{CFG_TGT_DBG} /* Debug */,
\t\t\t\t{CFG_TGT_REL} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

\t}};
\trootObject = {PROJECT} /* Project object */;
}}
"""

out = os.path.join(os.path.dirname(__file__), "Clipy.xcodeproj", "project.pbxproj")
with open(out, "w") as f:
    f.write(pbx)
print(f"Written: {out}")
