#!/usr/bin/env bash
set -euo pipefail

# Builds a self-contained PoDoFo archive per iOS slice. PoDoFo's third-party
# static dependencies are flattened into libpodofo.a by create-xcframework-target.
# zlib and iconv intentionally remain Apple SDK linker dependencies.

project_dir=$(cd "$(dirname "$0")" && pwd)
output_dir="$project_dir/artifacts/PoDoFo-1.1.0.xcframework"
deployment_target=16.3

cmake_bin=${CMAKE_BIN:-cmake}
if ! command -v "$cmake_bin" >/dev/null 2>&1; then
  if [[ -x /opt/homebrew/bin/cmake ]]; then
    cmake_bin=/opt/homebrew/bin/cmake
  else
    echo "CMake 3.20 or newer is required (set CMAKE_BIN if it is not on PATH)." >&2
    exit 1
  fi
fi

if [[ -e "$output_dir" ]]; then
  echo "Refusing to overwrite existing release artifact: $output_dir" >&2
  echo "Move it aside after recording its provenance, then rerun this build." >&2
  exit 1
fi

build_slice() {
  local build_dir=$1
  local platform=$2
  local architecture=$3

  "$cmake_bin" -S "$project_dir" -B "$project_dir/$build_dir" \
    -DCMAKE_TOOLCHAIN_FILE="$project_dir/ios.toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
    -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DIOS_PLATFORM="$platform"
  "$cmake_bin" --build "$project_dir/$build_dir" --target create-xcframework-target --parallel
}

build_slice build-iphoneos-1.1.0 OS arm64
build_slice build-iphonesimulator-arm64-1.1.0 SIMULATOR64 arm64
build_slice build-iphonesimulator-x86_64-1.1.0 SIMULATOR64 x86_64

simulator_library="$project_dir/build-iphonesimulator-universal-1.1.0/libpodofo-ios-simulator-universal.a"
mkdir -p "$(dirname "$simulator_library")"
lipo -create \
  "$project_dir/build-iphonesimulator-arm64-1.1.0/target/libpodofo.a" \
  "$project_dir/build-iphonesimulator-x86_64-1.1.0/target/libpodofo.a" \
  -output "$simulator_library"

xcodebuild -create-xcframework \
  -library "$project_dir/build-iphoneos-1.1.0/target/libpodofo.a" \
  -headers "$project_dir/build-iphoneos-1.1.0/target/include" \
  -library "$simulator_library" \
  -headers "$project_dir/build-iphonesimulator-arm64-1.1.0/target/include" \
  -output "$output_dir"

bash "$project_dir/scripts/generate-provenance.sh" "$output_dir"
bash "$project_dir/scripts/generate-controlled-evidence.sh" "$output_dir"
bash "$project_dir/scripts/verify-artifacts.sh" "$output_dir"

echo "Created $output_dir"
find "$output_dir" -name '*.a' -exec lipo -info {} \;
