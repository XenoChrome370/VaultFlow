#!/usr/bin/env python3
"""Generate VaultFlow.xcodeproj so the app opens and builds directly in Xcode.

Open the generated project, press ⌘R to run and ⌘U to test. It builds the same
sources as Package.swift, as ordinary Xcode targets:

    VaultFlowCore       dynamic framework  ← Sources/VaultFlowCore
    VaultFlow           macOS app (.app)   ← Sources/VaultFlow   (links VaultFlowCore)
    VaultFlowCoreTests  xctest bundle      ← Tests/VaultFlowCoreTests (no test host)

Package.swift stays the source of truth for `swift build` / `swift test`, and
Support/build.sh still produces dist/VaultFlow.app. Shared build settings live in
Config/*.xcconfig and are imported as each target's base configuration.

Re-run this script after adding, removing or renaming a file:

    python3 Tools/generate_xcodeproj.py
"""

from __future__ import annotations

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "VaultFlow"
PROJECT_DIR = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj")

APP_NAME = "VaultFlow"
CORE_NAME = "VaultFlowCore"
TESTS_NAME = "VaultFlowCoreTests"

PROJECT_ID = "1A0000000000000000000000"
APP_ID = "1A0000000000000000000001"
CORE_ID = "1A0000000000000000000002"
TESTS_ID = "1A0000000000000000000003"

MARKETING_VERSION = "3.1"
CURRENT_PROJECT_VERSION = "3"

# ---------------------------------------------------------------------------
# Identifier allocation
# ---------------------------------------------------------------------------

_counter = 0
_used: set[str] = {PROJECT_ID, APP_ID, CORE_ID, TESTS_ID}


def new_id() -> tuple[str, None]:
    """Allocate a fresh 24-hex object id (the `None` keeps call sites terse)."""
    global _counter
    while True:
        _counter += 1
        value = f"1B{_counter:022X}"
        if value not in _used:
            _used.add(value)
            return value, None


def new_object(comment: str, props: dict) -> str:
    obj_id, _ = new_id()
    define(obj_id, comment, props)
    return obj_id


def oid() -> str:
    return new_id()[0]


def q(value: str) -> str:
    """Quote a pbxproj string unless it is a plain identifier.

    Only this narrow alphabet is emitted unquoted: plutil's OpenStep reader
    rejects bare strings containing `(`, `)`, `@`, `+`, `=` or `$(`-style
    build-setting references, which then fails with a useless
    "(Unexpected character / at line 1)".
    """
    if value != "" and re.fullmatch(r"^[A-Za-z0-9_./$-]+$", value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def swift_files(folder: str) -> list[str]:
    paths = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, folder)):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for name in sorted(filenames):
            if name.endswith(".swift"):
                paths.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    return sorted(paths)


def fixture_files() -> list[str]:
    base = os.path.join(ROOT, "Tests", TESTS_NAME, "Fixtures")
    return sorted(
        os.path.relpath(os.path.join(dirpath, name), ROOT)
        for dirpath, _dirs, names in os.walk(base)
        for name in names
        if name.endswith(".json")
    )


# ---------------------------------------------------------------------------
# Object table: id -> {"isa": ..., "comment": ..., "props": ordered dict}
# ---------------------------------------------------------------------------

objects: dict[str, dict] = {}
comments: dict[str, str] = {}
section_order = [
    "PBXBuildFile",
    "PBXContainerItemProxy",
    "PBXCopyFilesBuildPhase",
    "PBXFileReference",
    "PBXFrameworksBuildPhase",
    "PBXGroup",
    "PBXNativeTarget",
    "PBXProject",
    "PBXResourcesBuildPhase",
    "PBXSourcesBuildPhase",
    "PBXTargetDependency",
    "XCBuildConfiguration",
    "XCConfigurationList",
]

def define(obj_id: str, comment: str, props: dict) -> str:
    """Register an object; the dict is stored as given (no copies)."""
    objects[obj_id] = props
    comments[obj_id] = comment
    return obj_id


def R(obj_id: str) -> str:
    """Reference to an object, with its comment."""
    note = comments.get(obj_id, "")
    return f"{obj_id} /* {note} */" if note else obj_id


# ---------------------------------------------------------------------------
# Encoder
# ---------------------------------------------------------------------------

def encode_dict(props: dict, indent: int) -> str:
    pad = "\t" * indent
    out = []
    for key, value in props.items():
        if key in REFERENCE_KEYS and isinstance(value, str):
            out.append(f"{pad}{key} = {R(value)};\n")
        elif isinstance(value, str) and key in SCALAR_KEYS:
            out.append(f"{pad}{key} = {value};\n")
        else:
            out.append(f"{pad}{key} = {encode_value(value, indent)};\n")
    return "".join(out)


REFERENCE_KEYS = (
    "fileRef",
    "containerPortal",
    "buildConfigurationList",
    "productReference",
    "mainGroup",
    "productRefGroup",
    "target",
    "targetProxy",
)

SCALAR_KEYS = ("isa", "lastKnownFileType", "explicitFileType")


def encode_value(value, indent: int) -> str:
    """Encode `value`, whose property line starts at `indent` tabs."""
    if isinstance(value, list):
        pad = "\t" * (indent + 1)
        if not value:
            return "()"
        body = "".join(f"{pad}{encode_list_item(item)},\n" for item in value)
        return "(\n" + body + "\t" * indent + ")"
    if isinstance(value, dict):
        pad = "\t" * (indent + 1)
        body = "".join(f"{pad}{key} = {encode_value(item, indent + 1)};\n" for key, item in value.items())
        return "{\n" + body + "\t" * indent + "}"
    return q(str(value))


def encode_list_item(item) -> str:
    if isinstance(item, str) and item in comments:
        return R(item)
    return q(str(item))


def emit_object(obj_id: str) -> str:
    props = objects[obj_id]
    # `id /* comment */ = { isa = …; };` — the shape Xcode itself writes.
    pad = "\t" * 2
    return f"{pad}{R(obj_id)} = {{\n{encode_dict(props, 3)}\t\t}};"


# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

core_paths = swift_files(os.path.join("Sources", CORE_NAME))
app_paths = swift_files(os.path.join("Sources", APP_NAME))
test_paths = swift_files(os.path.join("Tests", TESTS_NAME))
fixture_paths = fixture_files()

file_refs: dict[str, str] = {}
build_refs: dict[tuple[str, str], str] = {}


def file_ref(path: str, kind: str) -> str:
    """One PBXFileReference per project-relative path, in exactly one group.

    Groups are flat (no nested `path`), so every reference is resolved from the
    project directory, which is what `path` is here.
    """
    if path in file_refs:
        return file_refs[path]
    fid, _ = new_id()
    define(
        fid,
        os.path.basename(path),
        {
            "isa": "PBXFileReference",
            "lastKnownFileType": kind,
            "path": path,
            "sourceTree": "<group>",
        },
    )
    file_refs[path] = fid
    return fid


def build_file(path: str, kind: str, phase: str) -> str:
    key = (path, phase)
    if key in build_refs:
        return build_refs[key]
    name = os.path.basename(path)
    bid, _ = new_id()
    define(
        bid,
        f"{name} in {phase}",
        {
            "isa": "PBXBuildFile",
            "fileRef": file_ref(path, kind),
        },
    )
    build_refs[key] = bid
    return bid


core_builds = [build_file(p, "sourcecode.swift", "Sources") for p in core_paths]
app_builds = [build_file(p, "sourcecode.swift", "Sources") for p in app_paths]
test_builds = [build_file(p, "sourcecode.swift", "Sources") for p in test_paths]
fixture_builds = [build_file(p, "text.json", "Resources") for p in fixture_paths]

assets_ref = file_ref("Support/Assets.xcassets", "folder.assetcatalog")
assets_build = build_file("Support/Assets.xcassets", "folder.assetcatalog", "Resources")

info_plist_ref = file_ref("Support/Info.plist", "text.plist.xml")
build_script_ref = file_ref("Support/build.sh", "text.script.sh")
package_ref = file_ref("Package.swift", "sourcecode.swift")
readme_ref = file_ref("README.md", "net.daringfireball.markdown")
generator_ref = file_ref("Tools/generate_xcodeproj.py", "text.script.python")

CONFIG_NAMES = ("VaultFlow", "VaultFlowApp", "VaultFlowCore", "VaultFlowCoreTests")
config_refs = {name: file_ref(f"Config/{name}.xcconfig", "text.xcconfig") for name in CONFIG_NAMES}

# Products.
def product(path: str, file_type: str) -> str:
    return define(
        oid(),
        path,
        {
            "isa": "PBXFileReference",
            "explicitFileType": file_type,
            "includeInIndex": "0",
            "path": path,
            "sourceTree": "BUILT_PRODUCTS_DIR",
        },
    )


APP_PRODUCT = product(f"{APP_NAME}.app", "wrapper.application")
CORE_PRODUCT = product(f"{CORE_NAME}.framework", "wrapper.framework")
TESTS_PRODUCT = product(f"{TESTS_NAME}.xctest", "wrapper.cfbundle")

CORE_FRAMEWORK = f"{CORE_NAME}.framework"
APP_CORE_LINK = define(
    oid(),
    f"{CORE_FRAMEWORK} in Frameworks",
    {"isa": "PBXBuildFile", "fileRef": CORE_PRODUCT},
)
TESTS_CORE_LINK = define(
    oid(),
    f"{CORE_FRAMEWORK} in Frameworks",
    {"isa": "PBXBuildFile", "fileRef": CORE_PRODUCT},
)

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------

gid = {name: oid() for name in ("main", "sources", "core", "app", "tests", "tests_inner", "fixtures", "config", "support", "assets", "tools", "products")}


def group(group_id: str, name: str, children: list[str], path: str | None = None) -> None:
    """A group without `path` is purely organisational: it adds no prefix."""
    props = {"isa": "PBXGroup", "children": children, "name": name}
    if path is not None:
        props["path"] = path
    else:
        props["name"] = name
    props["sourceTree"] = "<group>"
    define(group_id, name, props)


group(gid["core"], CORE_NAME, [file_ref(p, "sourcecode.swift") for p in core_paths])
group(gid["app"], APP_NAME, [file_ref(p, "sourcecode.swift") for p in app_paths])
group(gid["sources"], "Sources", [gid["core"], gid["app"]])

group(gid["fixtures"], "Fixtures", [file_ref(p, "text.json") for p in fixture_paths])
group(
    gid["tests_inner"],
    TESTS_NAME,
    [file_ref(p, "sourcecode.swift") for p in test_paths] + [gid["fixtures"]],
)
group(gid["tests"], "Tests", [gid["tests_inner"]])

group(gid["config"], "Config", [config_refs[n] for n in CONFIG_NAMES])
group(gid["assets"], "Assets", [assets_ref])
group(gid["support"], "Support", [gid["assets"], info_plist_ref, build_script_ref])
group(gid["tools"], "Tools", [generator_ref], path="Tools")
group(gid["products"], "Products", [APP_PRODUCT, CORE_PRODUCT, TESTS_PRODUCT])

group(
    gid["main"],
    "",
    [
        gid["sources"],
        gid["tests"],
        gid["config"],
        gid["support"],
        gid["tools"],
        package_ref,
        readme_ref,
        gid["products"],
    ],
)

# ---------------------------------------------------------------------------
# Build phases
# ---------------------------------------------------------------------------

phase_ids = {key: {} for key in ("app", "core", "tests")}
for key in phase_ids:
    for kind in ("sources", "frameworks", "resources"):
        phase_ids[key][kind] = oid()
APP_COPY_PHASE = oid()
TESTS_COPY_PHASE = oid()

# The app and the host-less test bundle load VaultFlowCore at runtime, so the
# framework has to sit next to them in Frameworks/ ("Embed & Sign" in Xcode).
APP_CORE_EMBED = define(
    oid(),
    f"{CORE_FRAMEWORK} in Embed Frameworks",
    {
        "isa": "PBXBuildFile",
        "fileRef": CORE_PRODUCT,
        "settings": {"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]},
    },
)
TESTS_CORE_EMBED = define(
    oid(),
    f"{CORE_FRAMEWORK} in Embed Frameworks",
    {
        "isa": "PBXBuildFile",
        "fileRef": CORE_PRODUCT,
        "settings": {"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]},
    },
)


def phase(obj_id: str, isa: str, files: list[str], name: str | None = None) -> None:
    props = {"isa": isa, "buildActionMask": "2147483647"}
    if name is not None:
        props["name"] = name
    props["files"] = files
    props["runOnlyForDeploymentPostprocessing"] = "0"
    label = name or isa.removeprefix("PBX").removesuffix("BuildPhase")
    define(obj_id, label, props)


phase(phase_ids["core"]["sources"], "PBXSourcesBuildPhase", core_builds)
phase(phase_ids["core"]["frameworks"], "PBXFrameworksBuildPhase", [])
phase(phase_ids["core"]["resources"], "PBXResourcesBuildPhase", [])

phase(phase_ids["app"]["sources"], "PBXSourcesBuildPhase", app_builds)
phase(phase_ids["app"]["frameworks"], "PBXFrameworksBuildPhase", [APP_CORE_LINK])
phase(phase_ids["app"]["resources"], "PBXResourcesBuildPhase", [assets_build])

phase(phase_ids["tests"]["sources"], "PBXSourcesBuildPhase", test_builds)
phase(phase_ids["tests"]["frameworks"], "PBXFrameworksBuildPhase", [TESTS_CORE_LINK])
phase(phase_ids["tests"]["resources"], "PBXResourcesBuildPhase", fixture_builds)

def copy_phase(obj_id: str, files: list[str]) -> None:
    define(
        obj_id,
        "Embed Frameworks",
        {
            "isa": "PBXCopyFilesBuildPhase",
            "buildActionMask": "2147483647",
            "dstPath": "",
            "dstSubfolderSpec": "10",
            "files": files,
            "name": "Embed Frameworks",
            "runOnlyForDeploymentPostprocessing": "0",
        },
    )


copy_phase(APP_COPY_PHASE, [APP_CORE_EMBED])
copy_phase(TESTS_COPY_PHASE, [TESTS_CORE_EMBED])

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

APP_DEP = oid()
APP_PROXY = oid()
TESTS_DEP_CORE = oid()
TESTS_PROXY_CORE = oid()

for proxy_id in (APP_PROXY, TESTS_PROXY_CORE):
    define(
        proxy_id,
        "PBXContainerItemProxy",
        {
            "isa": "PBXContainerItemProxy",
            "containerPortal": PROJECT_ID,
            "proxyType": "1",
            "remoteGlobalIDString": CORE_ID,
            "remoteInfo": CORE_NAME,
        },
    )

for dep_id, proxy_id in ((APP_DEP, APP_PROXY), (TESTS_DEP_CORE, TESTS_PROXY_CORE)):
    define(
        dep_id,
        "PBXTargetDependency",
        {"isa": "PBXTargetDependency", "target": CORE_ID, "targetProxy": proxy_id},
    )

# ---------------------------------------------------------------------------
# Build configurations
# ---------------------------------------------------------------------------

config_ids: dict[tuple[str, str], str] = {}
for key in ("project", "app", "core", "tests"):
    for config in ("Debug", "Release"):
        config_ids[(key, config)] = oid()

list_ids = {key: oid() for key in ("project", "app", "core", "tests")}
TARGET_NAMES = {"app": APP_NAME, "core": CORE_NAME, "tests": TESTS_NAME}

for key, list_id in list_ids.items():
    label = (
        f'Build configuration list for PBXProject "{PROJECT_NAME}"'
        if key == "project"
        else f'Build configuration list for PBXNativeTarget "{TARGET_NAMES[key]}"'
    )
    define(
        list_id,
        label,
        {
            "isa": "XCConfigurationList",
            "buildConfigurations": [config_ids[(key, "Debug")], config_ids[(key, "Release")]],
            "defaultConfigurationIsVisible": "0",
            "defaultConfigurationName": "Release",
        },
    )

PROJECT_SETTINGS = [
    ("ALWAYS_SEARCH_USER_PATHS", "NO"),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING", "YES"),
    ("CLANG_WARN_BOOL_CONVERSION", "YES"),
    ("CLANG_WARN_COMMA", "YES"),
    ("CLANG_WARN_CONSTANT_CONVERSION", "YES"),
    ("CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS", "YES"),
    ("CLANG_WARN_EMPTY_BODY", "YES"),
    ("CLANG_WARN_ENUM_CONVERSION", "YES"),
    ("CLANG_WARN_INFINITE_RECURSION", "YES"),
    ("CLANG_WARN_INT_CONVERSION", "YES"),
    ("CLANG_WARN_NON_LITERAL_NULL_CONVERSION", "YES"),
    ("CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF", "YES"),
    ("CLANG_WARN_OBJC_LITERAL_CONVERSION", "YES"),
    ("CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER", "YES"),
    ("CLANG_WARN_RANGE_LOOP_ANALYSIS", "YES"),
    ("CLANG_WARN_STRICT_PROTOTYPES", "YES"),
    ("CLANG_WARN_SUSPICIOUS_MOVE", "YES"),
    ("CLANG_WARN_UNREACHABLE_CODE", "YES"),
    ("CLANG_WARN__DUPLICATE_METHOD_MATCH", "YES"),
    ("COPY_PHASE_STRIP", "NO"),
    ("DEAD_CODE_STRIPPING", "YES"),
    ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
    ("ENABLE_USER_SCRIPT_SANDBOXING", "YES"),
    ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
    ("GCC_NO_COMMON_BLOCKS", "YES"),
    ("GCC_WARN_64_TO_32_BIT_CONVERSION", "YES"),
    ("GCC_WARN_ABOUT_RETURN_TYPE", "YES_ERROR"),
    ("GCC_WARN_UNDECLARED_SELECTOR", "YES"),
    ("GCC_WARN_UNINITIALIZED_AUTOS", "YES_AGGRESSIVE"),
    ("GCC_WARN_UNUSED_FUNCTION", "YES"),
    ("GCC_WARN_UNUSED_VARIABLE", "YES"),
    ("MACOSX_DEPLOYMENT_TARGET", "26.0"),
    ("SDKROOT", "macosx"),
    ("STRING_CATALOG_GENERATE_SYMBOLS", "NO"),
]

DEBUG_SETTINGS = [
    ("DEBUG_INFORMATION_FORMAT", "dwarf"),
    ("ENABLE_TESTABILITY", "YES"),
    ("GCC_DYNAMIC_NO_PIC", "NO"),
    ("GCC_OPTIMIZATION_LEVEL", "0"),
    ("ONLY_ACTIVE_ARCH", "YES"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG"),
    ("SWIFT_OPTIMIZATION_LEVEL", "-Onone"),
]

RELEASE_SETTINGS = [
    ("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym"),
    ("ENABLE_NS_ASSERTIONS", "NO"),
    ("SWIFT_COMPILATION_MODE", "wholemodule"),
    ("SWIFT_OPTIMIZATION_LEVEL", "-O"),
]

TARGET_SETTINGS = {
    "app": [
        ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
        ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
        ("CODE_SIGN_IDENTITY", "-"),
        ("CODE_SIGN_STYLE", "Manual"),
        ("CURRENT_PROJECT_VERSION", CURRENT_PROJECT_VERSION),
        ("ENABLE_HARDENED_RUNTIME", "YES"),
        ("GENERATE_INFOPLIST_FILE", "NO"),
        ("INFOPLIST_FILE", "Support/Info.plist"),
        ("LD_RUNPATH_SEARCH_PATHS", "$(inherited) @executable_path/../Frameworks"),
        ("MARKETING_VERSION", MARKETING_VERSION),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.vaultflow.macos"),
        ("PRODUCT_NAME", "$(TARGET_NAME)"),
        ("SWIFT_VERSION", "5.0"),
    ],
    "core": [
        ("CODE_SIGN_IDENTITY", "-"),
        ("CODE_SIGN_STYLE", "Manual"),
        ("CURRENT_PROJECT_VERSION", CURRENT_PROJECT_VERSION),
        ("DEFINES_MODULE", "YES"),
        ("GENERATE_INFOPLIST_FILE", "YES"),
        ("MARKETING_VERSION", MARKETING_VERSION),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.vaultflow.macos.VaultFlowCore"),
        ("PRODUCT_NAME", "$(TARGET_NAME)"),
        ("SKIP_INSTALL", "YES"),
        ("SWIFT_VERSION", "5.0"),
    ],
    # Host-less, like `swift test`: no app is launched, and the bundle finds its
    # own copy of VaultFlowCore.framework via @loader_path.
    "tests": [
        ("BUNDLE_LOADER", ""),
        ("CODE_SIGN_IDENTITY", "-"),
        ("CODE_SIGN_STYLE", "Manual"),
        ("CURRENT_PROJECT_VERSION", CURRENT_PROJECT_VERSION),
        ("FRAMEWORK_SEARCH_PATHS", "$(inherited) $(PLATFORM_DIR)/Developer/Library/Frameworks"),
        ("GENERATE_INFOPLIST_FILE", "YES"),
        ("LD_RUNPATH_SEARCH_PATHS", "$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks"),
        ("MARKETING_VERSION", MARKETING_VERSION),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.vaultflow.macos.VaultFlowCoreTests"),
        ("PRODUCT_NAME", "$(TARGET_NAME)"),
        ("SWIFT_VERSION", "5.0"),
        ("TEST_HOST", ""),
    ],
}


for key in ("project", "app", "core", "tests"):
    for config in ("Debug", "Release"):
        base = []
        if key == "project":
            base = PROJECT_SETTINGS + (DEBUG_SETTINGS if config == "Debug" else RELEASE_SETTINGS)
        props = {"isa": "XCBuildConfiguration"}
        if key != "project":
            props["baseConfigurationReference"] = config_refs[f"VaultFlow{'' if key == 'app' else 'Core' if key == 'core' else 'CoreTests'}"]
        props["buildSettings"] = dict(base + TARGET_SETTINGS.get(key, []))
        props["name"] = config
        define(config_ids[(key, config)], config, props)

# ---------------------------------------------------------------------------
# Native targets and project
# ---------------------------------------------------------------------------

TARGET_META = {
    "app": (APP_ID, APP_NAME, APP_PRODUCT, "com.apple.product-type.application", [APP_DEP]),
    "core": (CORE_ID, CORE_NAME, CORE_PRODUCT, "com.apple.product-type.framework", []),
    "tests": (TESTS_ID, TESTS_NAME, TESTS_PRODUCT, "com.apple.product-type.bundle.unit-test", [TESTS_DEP_CORE]),
}

for key, (target_id, name, product_id, product_type, deps) in TARGET_META.items():
    phases = [
        phase_ids[key]["sources"],
        phase_ids[key]["frameworks"],
        phase_ids[key]["resources"],
    ]
    if key == "tests":
        phases.append(TESTS_COPY_PHASE)
    if key == "app":
        phases.append(APP_COPY_PHASE)
    define(
        target_id,
        name,
        {
            "isa": "PBXNativeTarget",
            "buildConfigurationList": list_ids[key],
            "buildPhases": phases,
            "buildRules": [],
            "dependencies": deps,
            "name": name,
            "productName": name,
            "productReference": product_id,
            "productType": product_type,
        },
    )

define(
    PROJECT_ID,
    "Project object",
    {
        "isa": "PBXProject",
        "attributes": {
            "BuildIndependentTargetsInParallel": "1",
            "LastSwiftUpdateCheck": "2720",
            "LastUpgradeCheck": "2720",
            "TargetAttributes": {
                APP_ID: {"CreatedOnToolsVersion": "27.2"},
                CORE_ID: {"CreatedOnToolsVersion": "27.2"},
                TESTS_ID: {"CreatedOnToolsVersion": "27.2", "TestTargetID": APP_ID},
            },
        },
        "buildConfigurationList": list_ids["project"],
        "compatibilityVersion": "Xcode 15.0",
        "developmentRegion": "en",
        "hasScannedForEncodings": "0",
        "knownRegions": ["en", "Base"],
        "mainGroup": gid["main"],
        "productRefGroup": gid["products"],
        "projectDirPath": "",
        "projectRoot": "",
        "targets": [APP_ID, CORE_ID, TESTS_ID],
    },
)

# ---------------------------------------------------------------------------
# Write project.pbxproj
# ---------------------------------------------------------------------------

by_section: dict[str, list[str]] = {}
for obj_id, props in objects.items():
    by_section.setdefault(props["isa"], []).append(obj_id)

lines = [
    "// !$*UTF8*$!",
    "{",
    "\tarchiveVersion = 1;",
    "\tclasses = {",
    "\t};",
    "\tobjectVersion = 56;",
    "\tobjects = {",
    "",
]
for section in section_order:
    ids = by_section.get(section, [])
    if not ids:
        continue
    lines.append(f"/* Begin {section} section */")
    for obj_id in ids:
        lines.append(emit_object(obj_id))
    lines.append(f"/* End {section} section */")
    lines.append("")
lines += [
    "\t};",
    f"\trootObject = {R(PROJECT_ID)};",
    "}",
    "",
]

# Sanity: every referenced id must be defined.
text = "\n".join(lines)
defined = set(objects)
referenced = set(re.findall(r"\b([0-9A-F]{24})\b", text))
missing = sorted(referenced - defined)
assert not missing, f"undefined object ids: {missing}"

os.makedirs(PROJECT_DIR, exist_ok=True)
with open(os.path.join(PROJECT_DIR, "project.pbxproj"), "w", encoding="utf-8") as handle:
    handle.write(text)


# ---------------------------------------------------------------------------
# Workspace + shared schemes
# ---------------------------------------------------------------------------

workspace_dir = os.path.join(PROJECT_DIR, "project.xcworkspace")
os.makedirs(workspace_dir, exist_ok=True)
with open(os.path.join(workspace_dir, "contents.xcworkspacedata"), "w", encoding="utf-8") as handle:
    handle.write(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<Workspace\n   version = \"1.0\">\n"
        '   <FileRef\n      location = "self:">\n   </FileRef>\n'
        "</Workspace>\n"
    )


def buildable_reference(target_id: str, name: str, product: str) -> str:
    return (
        "            <BuildableReference\n"
        '               BuildableIdentifier = "primary"\n'
        f'               BlueprintIdentifier = "{target_id}"\n'
        f'               BuildableName = "{product}"\n'
        f'               BlueprintName = "{name}"\n'
        f'               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">\n'
        "            </BuildableReference>\n"
    )


def build_action_entry(target_id: str, name: str, product: str) -> str:
    return (
        "         <BuildActionEntry\n"
        '            buildForTesting = "YES"\n'
        '            buildForRunning = "YES"\n'
        '            buildForProfiling = "YES"\n'
        '            buildForArchiving = "YES"\n'
        '            buildForAnalyzing = "YES">\n'
        + buildable_reference(target_id, name, product)
        + "         </BuildActionEntry>\n"
    )


TESTABLE = (TESTS_ID, TESTS_NAME, f"{TESTS_NAME}.xctest")
APP_BUILDABLE = (APP_ID, APP_NAME, f"{APP_NAME}.app")
CORE_BUILDABLE = (CORE_ID, CORE_NAME, f"{CORE_NAME}.framework")


def scheme(runnable: tuple[str, str, str] | None) -> str:
    entries = [runnable] if runnable else []
    if TESTABLE not in entries:
        entries.append(TESTABLE)
    if runnable is None:
        entries.insert(0, CORE_BUILDABLE)

    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<Scheme\n   LastUpgradeVersion = "2720"\n   version = "1.7">',
        '   <BuildAction\n      parallelizeBuildables = "YES"\n      buildImplicitDependencies = "YES"\n      buildArchitectures = "Automatic">',
        "      <BuildActionEntries>",
    ]
    parts += [build_action_entry(*entry) for entry in entries]
    parts += [
        "      </BuildActionEntries>",
        "   </BuildAction>",
        '   <TestAction\n      buildConfiguration = "Debug"\n      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"\n      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"\n      shouldUseLaunchSchemeArgsEnv = "YES">',
        "      <Testables>",
        '         <TestableReference\n            skipped = "NO"\n            parallelizable = "YES">',
        buildable_reference(*TESTABLE).rstrip("\n"),
        "         </TestableReference>",
        "      </Testables>",
        "   </TestAction>",
    ]
    if runnable:
        parts += [
            '   <LaunchAction\n      buildConfiguration = "Debug"\n      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"\n      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"\n      launchStyle = "0"\n      useCustomWorkingDirectory = "NO"\n      ignoresPersistentStateOnLaunch = "NO"\n      debugDocumentVersioning = "YES"\n      debugServiceExtension = "internal"\n      allowLocationSimulation = "YES">',
            '      <BuildableProductRunnable\n         runnableDebuggingMode = "0">',
            buildable_reference(*runnable).rstrip("\n"),
            "      </BuildableProductRunnable>",
            "   </LaunchAction>",
            '   <ProfileAction\n      buildConfiguration = "Release"\n      shouldUseLaunchSchemeArgsEnv = "YES"\n      savedToolIdentifier = ""\n      useCustomWorkingDirectory = "NO"\n      debugDocumentVersioning = "YES">',
            '      <BuildableProductRunnable\n         runnableDebuggingMode = "0">',
            buildable_reference(*runnable).rstrip("\n"),
            "      </BuildableProductRunnable>",
            "   </ProfileAction>",
        ]
    parts += [
        '   <AnalyzeAction\n      buildConfiguration = "Debug">\n   </AnalyzeAction>',
        '   <ArchiveAction\n      buildConfiguration = "Release"\n      revealArchiveInOrganizer = "YES">\n   </ArchiveAction>',
        "</Scheme>",
        "",
    ]
    return "\n".join(parts)


schemes_dir = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes")
os.makedirs(schemes_dir, exist_ok=True)
with open(os.path.join(schemes_dir, f"{APP_NAME}.xcscheme"), "w", encoding="utf-8") as handle:
    handle.write(scheme(APP_BUILDABLE))
with open(os.path.join(schemes_dir, f"{CORE_NAME}.xcscheme"), "w", encoding="utf-8") as handle:
    handle.write(scheme(None))

print(f"✓ {PROJECT_NAME}.xcodeproj")
print(
    f"  {len(core_paths)} VaultFlowCore sources, {len(app_paths)} VaultFlow sources, "
    f"{len(test_paths)} test sources, {len(fixture_paths)} fixtures"
)
