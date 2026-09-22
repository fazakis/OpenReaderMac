#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Validation
python3 Scripts/error_server.py > /tmp/openreader-error-fixture.log 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
OPENREADER_ERROR_FIXTURE=1 'dist/OpenReader Mac.app/Contents/MacOS/OpenReader Mac' --diagnostics "$PWD/Validation/live-diagnostics.json"
cat Validation/live-diagnostics.json
