#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture='build/OpenReader Copy Fixture.app'
mkdir -p "$fixture/Contents/MacOS"
swiftc -parse-as-library Validation/CopySelectionFixture.swift -o "$fixture/Contents/MacOS/CopyFixture"
python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('build/OpenReader Copy Fixture.app/Contents/Info.plist')
p.write_bytes(plistlib.dumps({'CFBundleExecutable':'CopyFixture','CFBundleIdentifier':'org.openreader.CopyFixture','CFBundleName':'OpenReader Copy Fixture','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0'}))
PY
codesign --force --sign - "$fixture"
