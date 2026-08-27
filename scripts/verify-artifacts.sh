#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
framework=${1:-"$project_dir/artifacts/PoDoFo-1.1.0.xcframework"}
[[ -f "$framework/ios-arm64/libpodofo.a" ]]
[[ -f "$framework/ios-arm64_x86_64-simulator/libpodofo-ios-simulator-universal.a" ]]
[[ -f "$framework/ios-arm64/Headers/podofo/podofo.h" ]]
[[ -f "$framework/ios-arm64/Headers/podofo/auxiliary/Version.h" ]]
rg -q 'PODOFO_VERSION_MINOR 1' "$framework/ios-arm64/Headers/podofo/auxiliary/podofo_config.h"
lipo -info "$framework/ios-arm64/libpodofo.a" | rg -q 'arm64'
lipo -info "$framework/ios-arm64_x86_64-simulator/libpodofo-ios-simulator-universal.a" | rg -q 'arm64.*x86_64|x86_64.*arm64'
[[ -s "$project_dir/artifacts/podofo-ios-1.1.0-provenance.json" ]]
[[ -s "$project_dir/artifacts/podofo-ios-1.1.0-corresponding-source.tar.gz" ]]
bash "$project_dir/scripts/verify-controlled-evidence.sh" "$framework"
echo "iOS XCFramework provenance and architecture checks passed"
