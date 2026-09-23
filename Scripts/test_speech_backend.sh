#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
sources=()
for source in App/*.swift; do
    if [ "$source" != 'App/OpenReaderApp.swift' ]; then sources+=("$source"); fi
done
swiftc -parse-as-library Core/*.swift "${sources[@]}" Validation/SpeechBackendHarness.swift -o build/speech-backend-test
build/speech-backend-test "$@"
