#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project OpenReaderMac.xcodeproj -scheme OpenReaderMac -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build build
mkdir -p dist
if [ -d 'dist/OpenReader Mac.app' ]; then
    mv 'dist/OpenReader Mac.app' "build/previous-app-$(date +%s).app"
fi
ditto 'build/Build/Products/Release/OpenReader Mac.app' 'dist/OpenReader Mac.app'
codesign --verify --deep --strict 'dist/OpenReader Mac.app'
