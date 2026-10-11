#!/usr/bin/env python3
"""Generate the dependency-free iOS project; rerun after adding Swift UI files."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "MyongjiMeals.xcodeproj"
PROJECT.mkdir(exist_ok=True)
FEED_URL = json.loads((ROOT / "App/MealFeedConfiguration.json").read_text())["feedURL"]


def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def quote(value):
    return json.dumps(str(value), ensure_ascii=False)


objects = []


def obj(key, value):
    objects.append(f"\t\t{uid(key)} = {{ {value} }};")


files = sorted((ROOT / "Sources/MyongjiMealsApp").glob("*.swift"))
assert files, "Create the SwiftUI source files first."
source_refs = []
source_builds = []
for path in files:
    key = f"source:{path.name}"
    obj(key, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(path.name)}; sourceTree = \"<group>\";")
    obj(f"build:{path.name}", f"isa = PBXBuildFile; fileRef = {uid(key)};")
    source_refs.append(uid(key))
    source_builds.append(uid(f"build:{path.name}"))

obj("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = "<group>";')
obj("info-plist", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = App/Info.plist; sourceTree = "<group>";')
obj("assets-build", f"isa = PBXBuildFile; fileRef = {uid('assets')};")
obj("app-product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MyongjiMeals.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj("sources-group", f'isa = PBXGroup; children = ({",".join(source_refs)},); path = Sources/MyongjiMealsApp; sourceTree = "<group>";')
obj("products-group", f'isa = PBXGroup; children = ({uid("app-product")},); name = Products; sourceTree = "<group>";')
obj("root-group", f'isa = PBXGroup; children = ({uid("sources-group")}, {uid("assets")}, {uid("info-plist")}, {uid("products-group")},); sourceTree = "<group>";')
obj("local-package", 'isa = XCLocalSwiftPackageReference; relativePath = .;')
obj("mealcore-product", f'isa = XCSwiftPackageProductDependency; package = {uid("local-package")}; productName = MealCore;')
obj("mealcore-build", f'isa = PBXBuildFile; productRef = {uid("mealcore-product")};')
obj("sources-phase", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(source_builds)},); runOnlyForDeploymentPostprocessing = 0;')
obj("frameworks-phase", f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({uid("mealcore-build")},); runOnlyForDeploymentPostprocessing = 0;')
obj("resources-phase", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("assets-build")},); runOnlyForDeploymentPostprocessing = 0;')

for config in ("Debug", "Release"):
    project_settings = {
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "SWIFT_VERSION": "5.0", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if config == "Debug" else "",
        "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO"
    }
    target_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "0.1.0", "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": "App/Info.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": "명지밥",
        "MJU_MEAL_FEED_URL": FEED_URL,
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
        "PRODUCT_BUNDLE_IDENTIFIER": "kr.mjubap.app",
        "PRODUCT_NAME": "$(TARGET_NAME)", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO", "TARGETED_DEVICE_FAMILY": "1",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "SWIFT_EMIT_LOC_STRINGS": "YES"
    }
    for kind, settings in (("project", project_settings), ("target", target_settings)):
        body = " ".join(f"{k} = {quote(v)};" for k, v in settings.items())
        obj(f"{kind}-{config}", f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {config};')
for kind in ("project", "target"):
    obj(f"{kind}-configs", f'isa = XCConfigurationList; buildConfigurations = ({uid(kind+"-Debug")}, {uid(kind+"-Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

obj("target", f'isa = PBXNativeTarget; buildConfigurationList = {uid("target-configs")}; buildPhases = ({uid("sources-phase")}, {uid("frameworks-phase")}, {uid("resources-phase")},); buildRules = (); dependencies = (); name = MyongjiMeals; packageProductDependencies = ({uid("mealcore-product")},); productName = MyongjiMeals; productReference = {uid("app-product")}; productType = "com.apple.product-type.application";')
obj("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {uid("target")} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ko; hasScannedForEncodings = 0; knownRegions = (ko, en, Base); mainGroup = {uid("root-group")}; packageReferences = ({uid("local-package")},); productRefGroup = {uid("products-group")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
(PROJECT / "project.pbxproj").write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {uid("project")};\n}}\n')
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="MyongjiMeals.app" BlueprintName="MyongjiMeals" ReferencedContainer="container:MyongjiMeals.xcodeproj"/>'
(scheme_dir / "MyongjiMeals.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f"Generated {PROJECT.name} with {len(files)} SwiftUI files.")
