#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -parse-as-library App/ClipboardCopyReader.swift Validation/ClipboardHarness.swift -o build/clipboard-test
build/clipboard-test
