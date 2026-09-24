#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
sources=()
for source in App/*.swift; do
    if [ "$source" != 'App/OpenReaderApp.swift' ]; then sources+=("$source"); fi
done
swiftc -parse-as-library Core/*.swift "${sources[@]}" Validation/SpeechFailureHarness.swift -o build/speech-failure-test
port_file=$(mktemp build/speech-errors-port.XXXXXX)
python3 Validation/speech_error_fixture.py "$port_file" &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true' EXIT
for ((attempt=0; attempt<50; attempt++)); do
    if [ -s "$port_file" ]; then break; fi
    sleep 0.1
done
test -s "$port_file"
build/speech-failure-test "http://127.0.0.1:$(cat "$port_file")/v1"
