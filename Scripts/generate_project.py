#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generation."""
import pathlib, hashlib
root=pathlib.Path(__file__).resolve().parent.parent
project=root/'OpenReaderMac.xcodeproj'; project.mkdir(exist_ok=True)
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objects=[]
def add(name,body):
 ident=uid(name);objects.append(f'{ident} = {{ {body} }};');return ident
files=sorted(list(root.glob('App/*.swift'))+list(root.glob('Core/*.swift')))
refs=[];builds=[]
for file in files:
 path=str(file.relative_to(root))
 ref=add(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = "<group>";')
 refs.append(ref);builds.append(add(path+'build',f'isa = PBXBuildFile; fileRef = {ref};'))
icon=add('icon', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/OpenReader.icns; sourceTree = "<group>";')
refs.append(icon)
iconbuild=add('iconbuild', f'isa = PBXBuildFile; fileRef = {icon};')
license=add('license', 'isa = PBXFileReference; lastKnownFileType = text; path = LICENSE; sourceTree = "<group>";')
refs.append(license)
licensebuild=add('licensebuild', f'isa = PBXBuildFile; fileRef = {license};')
product=add('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = "OpenReader Mac.app"; sourceTree = BUILT_PRODUCTS_DIR;')
group=add('main',f'isa = PBXGroup; children = ({",".join(refs)},{uid("products")}); sourceTree = "<group>";')
add('products',f'isa = PBXGroup; children = ({product}); name = Products; sourceTree = "<group>";')
sources=add('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;')
frameworks=add('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
resources=add('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({iconbuild},{licensebuild}); runOnlyForDeploymentPostprocessing = 0;')
for scope in ['project','target']:
 configs=[]
 for config in ['Debug','Release']:
  settings='MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;'
  if scope=='target': settings+=' PRODUCT_NAME = "OpenReader Mac"; PRODUCT_BUNDLE_IDENTIFIER = gr.fazakis.OpenReaderMac; INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = NO; SWIFT_EMIT_LOC_STRINGS = YES; COMBINE_HIDPI_IMAGES = YES;'
  settings+= ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;' if config=='Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; DEPLOYMENT_POSTPROCESSING = YES; STRIP_INSTALLED_PRODUCT = YES; STRIP_STYLE = all;'
  configs.append(add(scope+config,f'isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = {config};'))
 add(scope+'configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=add('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({sources},{frameworks},{resources}); buildRules = (); dependencies = (); name = OpenReaderMac; productName = "OpenReader Mac"; productReference = {product}; productType = "com.apple.product-type.application";')
proj=add('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2620; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {group}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({target});')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {proj}; }}\n')
scheme=project/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'OpenReaderMac.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2620" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="OpenReader Mac.app" BlueprintName="OpenReaderMac" ReferencedContainer="container:OpenReaderMac.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="OpenReader Mac.app" BlueprintName="OpenReaderMac" ReferencedContainer="container:OpenReaderMac.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(project)
