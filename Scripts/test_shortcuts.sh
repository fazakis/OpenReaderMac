#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -parse-as-library App/Shortcuts.swift Validation/ShortcutHarness.swift -o build/shortcut-test
build/shortcut-test
