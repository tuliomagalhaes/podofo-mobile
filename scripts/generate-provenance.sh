#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
output_dir=${1:?XCFramework path is required}
artifact_dir="$project_dir/artifacts"
source_dir="$project_dir/downloads"
mkdir -p "$artifact_dir" "$source_dir"
cmake_bin=${CMAKE_BIN:-cmake}
if ! command -v "$cmake_bin" >/dev/null 2>&1 && [[ -x /opt/homebrew/bin/cmake ]]; then
  cmake_bin=/opt/homebrew/bin/cmake
fi

reuse_verified_source() {
  local name=$1 build_name=$2 expected_hash=$3
  local path="$source_dir/$name"
  if [[ ! -f "$path" ]]; then
    local candidate actual_hash
    while IFS= read -r candidate; do
      actual_hash=$(shasum -a 256 "$candidate" | awk '{print $1}')
      if [[ "$actual_hash" == "$expected_hash" ]]; then
        cp "$candidate" "$path"
        break
      fi
    done < <(find "$project_dir" -maxdepth 4 -path '*/build-*-1.1.0/*' -type f -name "$build_name" | sort)
  fi
  local actual_hash
  [[ -f "$path" ]] || { echo "Missing verified CMake source archive for $name; rerun the affected slice before generating provenance." >&2; exit 1; }
  actual_hash=$(shasum -a 256 "$path" | awk '{print $1}')
  [[ "$actual_hash" == "$expected_hash" ]] || { echo "Checksum mismatch for $name" >&2; exit 1; }
}

reuse_verified_source podofo-1.1.0.tar.gz 1.1.0.tar.gz f34b4413b613e33ab9fe83ff5aa7e2827a6425fcbcd343339458d614b7d6a951
reuse_verified_source openssl-1.1.1w.tar.gz openssl-1.1.1w.tar.gz cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
reuse_verified_source freetype-2.13.2.tar.gz VER-2-13-2.tar.gz 427201f5d5151670d05c1f5b45bef5dda1f2e7dd971ef54f0feaaa7ffd2ab90c
reuse_verified_source libxml2-2.12.9.tar.xz libxml2-2.12.9.tar.xz 59912db536ab56a3996489ea0299768c7bcffe57169f0235e7f962a91f483590

source_bundle="$artifact_dir/podofo-ios-1.1.0-corresponding-source.tar.gz"
python3 "$project_dir/scripts/deterministic-tar.py" "$source_bundle" "$project_dir" \
  downloads/podofo-1.1.0.tar.gz downloads/openssl-1.1.1w.tar.gz \
  downloads/freetype-2.13.2.tar.gz downloads/libxml2-2.12.9.tar.xz \
  patches README.md THIRD_PARTY_NOTICES.md CMakeLists.txt ios.toolchain.cmake run-ios-build.sh scripts

archive_records=()
while IFS= read -r archive; do
  archive_records+=("$(shasum -a 256 "$archive" | awk '{print $1}')|${archive#$project_dir/}")
done < <(find "$output_dir" -type f -name '*.a' | sort)

patch_records=()
while IFS= read -r patch; do
  patch_records+=("$(shasum -a 256 "$patch" | awk '{print $1}')|${patch#$project_dir/}")
done < <(find "$project_dir/patches" -type f | sort)

manifest="$artifact_dir/podofo-ios-1.1.0-provenance.json"
{
  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "component": "PoDoFo iOS XCFramework",\n'
  printf '  "source": {"name": "podofo", "version": "1.1.0", "gitCommit": "712fb0e80e0e9404525d8db54fa0baa4ae469963", "url": "https://github.com/podofo/podofo/archive/refs/tags/1.1.0.tar.gz", "sha256": "f34b4413b613e33ab9fe83ff5aa7e2827a6425fcbcd343339458d614b7d6a951", "license": "LGPL-2.0-or-later"},\n'
  printf '  "dependencies": [{"name":"OpenSSL","version":"1.1.1w","license":"OpenSSL","sha256":"cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"},{"name":"FreeType","version":"2.13.2","license":"FTL OR GPL-2.0-or-later","sha256":"427201f5d5151670d05c1f5b45bef5dda1f2e7dd971ef54f0feaaa7ffd2ab90c"},{"name":"libxml2","version":"2.12.9","license":"MIT","sha256":"59912db536ab56a3996489ea0299768c7bcffe57169f0235e7f962a91f483590"}],\n'
  printf '  "toolchain": {"xcode": "%s", "clang": "%s", "cmake": "%s"},\n' "$(xcodebuild -version | tr '\n' ';' | sed 's/;$/ /')" "$(xcrun --find clang)" "$("$cmake_bin" --version | head -n 1)"
  printf '  "build": {"deploymentTarget":"16.3","cxxStandard":"c++17","flags":"-arch <slice> -isysroot <SDK> -miphoneos-version-min=16.3 or -mios-simulator-version-min=16.3","patchApplication":"verified CMake source transformations; legacy 1.0.2 compatibility patch not applied"},\n'
  printf '  "patches": ['
  for i in "${!patch_records[@]}"; do IFS='|' read -r hash path <<<"${patch_records[$i]}"; (( i )) && printf ','; printf '{"path":"%s","sha256":"%s"}' "$path" "$hash"; done
  printf '],\n  "archives": ['
  for i in "${!archive_records[@]}"; do IFS='|' read -r hash path <<<"${archive_records[$i]}"; (( i )) && printf ','; printf '{"path":"%s","sha256":"%s"}' "$path" "$hash"; done
  printf '],\n  "correspondingSourceBundle": {"path":"artifacts/%s","sha256":"%s"}\n}\n' "$(basename "$source_bundle")" "$(shasum -a 256 "$source_bundle" | awk '{print $1}')"
} > "$manifest"

echo "Wrote $manifest"
