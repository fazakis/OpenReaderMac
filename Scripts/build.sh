#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project OpenReaderMac.xcodeproj -scheme OpenReaderMac -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
mkdir -p dist
if [ -d 'dist/OpenReader Mac.app' ]; then
    mv 'dist/OpenReader Mac.app' "build/previous-app-$(date +%s).app"
fi
ditto 'build/Build/Products/Release/OpenReader Mac.app' 'dist/OpenReader Mac.app'
codesign --verify --deep --strict 'dist/OpenReader Mac.app'
