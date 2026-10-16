#!/usr/bin/env python3
"""Generate the dependency-free Xcode app project from the actual source tree."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
project = root / 'Mindora.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def put(name, text):
    key = uid(name); objects[key] = text; return key
def quoted(text): return '"' + str(text).replace('\\', '\\\\').replace('"', '\\"') + '"'
def array(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
source_files = sorted((root / 'Sources/Mindora').rglob('*.swift'))
file_ids = {}

def group(directory):
    children = []
    for path in sorted(directory.iterdir()):
        if path.is_dir(): children.append(group(path))
        elif path.suffix in ('.swift', '.plist', '.entitlements', '.icns'):
            filetype = {'.swift': 'sourcecode.swift', '.plist': 'text.plist.xml', '.entitlements': 'text.plist.entitlements', '.icns': 'image.icns'}[path.suffix]
            key = put('file:' + str(path.relative_to(root)), '{isa = PBXFileReference; lastKnownFileType = ' + filetype + '; path = ' + quoted(path.name) + '; sourceTree = "<group>"; }')
            file_ids[path] = key; children.append(key)
    return put('group:' + str(directory.relative_to(root)), '{isa = PBXGroup; children = ' + array(children) + '; path = ' + quoted(directory.name) + '; sourceTree = "<group>"; }')
source_group = group(root / 'Sources')
resource_group = group(root / 'Resources')
test_group = group(root / 'Tests')
product = put('product', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = Mindora.app; sourceTree = BUILT_PRODUCTS_DIR; }')
products = put('products', '{isa = PBXGroup; children = (' + product + ',); name = Products; sourceTree = "<group>"; }')
main = put('main', '{isa = PBXGroup; children = ' + array([source_group, resource_group, test_group, products]) + '; sourceTree = "<group>"; }')
source_build_ids = [put('build:' + str(p.relative_to(root)), '{isa = PBXBuildFile; fileRef = ' + file_ids[p] + '; }') for p in source_files]
resource_build_ids = [put('build:icon', '{isa = PBXBuildFile; fileRef = ' + file_ids[root/'Resources/AppIcon.icns'] + '; }')] if (root/'Resources/AppIcon.icns').exists() else []
sources = put('sources', '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ' + array(source_build_ids) + '; runOnlyForDeploymentPostprocessing = 0; }')
resources = put('resources', '{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ' + array(resource_build_ids) + '; runOnlyForDeploymentPostprocessing = 0; }')
frameworks = put('frameworks', '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }')

def config(name, settings):
    values = ' '.join(k + ' = ' + quoted(v) + ';' for k,v in settings.items())
    return put(name, '{isa = XCBuildConfiguration; buildSettings = {' + values + '}; name = ' + name.split(':')[-1] + '; }')
common = {'MACOSX_DEPLOYMENT_TARGET':'14.0', 'SDKROOT':'macosx', 'SWIFT_VERSION':'5.0', 'CLANG_ENABLE_MODULES':'YES', 'CLANG_ENABLE_OBJC_ARC':'YES'}
project_debug = config('project:Debug', common | {'SWIFT_OPTIMIZATION_LEVEL':'-Onone', 'DEBUG_INFORMATION_FORMAT':'dwarf', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG', 'ENABLE_TESTABILITY':'YES'})
project_release = config('project:Release', common | {'SWIFT_OPTIMIZATION_LEVEL':'-Osize', 'SWIFT_COMPILATION_MODE':'wholemodule', 'DEAD_CODE_STRIPPING':'YES', 'DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym'})
target_common = {'PRODUCT_BUNDLE_IDENTIFIER':'app.mindora.mac', 'PRODUCT_NAME':'Mindora', 'INFOPLIST_FILE':'Resources/Info.plist', 'GENERATE_INFOPLIST_FILE':'NO', 'CODE_SIGN_STYLE':'Automatic', 'CODE_SIGN_ENTITLEMENTS':'Resources/Mindora.entitlements', 'ENABLE_APP_SANDBOX':'YES', 'ENABLE_HARDENED_RUNTIME':'YES', 'ENABLE_DEBUG_DYLIB':'NO', 'SWIFT_EMIT_LOC_STRINGS':'YES', 'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks'}
target_debug = config('target:Debug', target_common)
target_release = config('target:Release', target_common | {'STRIP_INSTALLED_PRODUCT':'YES', 'COPY_PHASE_STRIP':'YES', 'STRIP_SWIFT_SYMBOLS':'YES', 'DEAD_CODE_STRIPPING':'YES'})
project_configs = put('project-configs', '{isa = XCConfigurationList; buildConfigurations = ' + array([project_debug,project_release]) + '; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
target_configs = put('target-configs', '{isa = XCConfigurationList; buildConfigurations = ' + array([target_debug,target_release]) + '; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
target = put('target', '{isa = PBXNativeTarget; buildConfigurationList = ' + target_configs + '; buildPhases = ' + array([sources,frameworks,resources]) + '; buildRules = (); dependencies = (); name = Mindora; productName = Mindora; productReference = ' + product + '; productType = "com.apple.product-type.application"; }')
project_id = put('project', '{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1500; }; buildConfigurationList = ' + project_configs + '; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", Base); mainGroup = ' + main + '; productRefGroup = ' + products + '; projectDirPath = ""; projectRoot = ""; targets = (' + target + ',); }')
content = '// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
content += '\n'.join(k + ' = ' + v + ';' for k,v in sorted(objects.items()))
content += '\n}; rootObject = ' + project_id + '; }\n'
(project/'project.pbxproj').write_text(content)
schemes = project/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
(schemes/'Mindora.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Mindora.app" BlueprintName="Mindora" ReferencedContainer="container:Mindora.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Mindora.app" BlueprintName="Mindora" ReferencedContainer="container:Mindora.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Mindora.app" BlueprintName="Mindora" ReferencedContainer="container:Mindora.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated Mindora.xcodeproj with', len(source_files), 'Swift source files')
