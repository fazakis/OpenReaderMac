#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -parse-as-library Core/*.swift App/Extraction.swift App/SourceSelection.swift App/SelectionCopyTarget.swift App/ClipboardCopyReader.swift App/WordHighlighter.swift Validation/SourceHighlightHarness.swift -o build/source-highlight-test
build/source-highlight-test "${1:-com.google.Chrome}"
