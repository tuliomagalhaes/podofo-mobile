#!/usr/bin/env bash
# Builds the pinned Android native dependency baseline. Generated files stay in
# --output (default: android-out) and are deliberately not removed by this script.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$script_dir/.." && pwd)
lock_file="$script_dir/sources.lock.json"
output_dir="$project_dir/android-out"
abis=(armeabi-v7a arm64-v8a x86 x86_64)
linkage=static
download_connect_timeout=${CURL_CONNECT_TIMEOUT:-15}
download_max_time=${CURL_MAX_TIME:-120}
download_retry_count=${CURL_RETRY_COUNT:-1}
cmake_bin=${CMAKE_BIN:-/opt/homebrew/bin/cmake}
ninja_bin=${NINJA_BIN:-/opt/homebrew/bin/ninja}
make_bin=${MAKE_BIN:-/usr/bin/make}

usage() {
  printf 'Usage: %s [--abi ABI] [--linkage static|sdk-shared] [--output DIR]\n' "$0"
}

while (($#)); do
  case "$1" in
    --abi) abis=("$2"); shift 2 ;;
    --linkage) linkage=$2; shift 2 ;;
    --output) output_dir=$2; shift 2 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[[ "$linkage" == static || "$linkage" == sdk-shared ]] || {
  echo "--linkage must be static or sdk-shared." >&2
  exit 2
}

ndk_dir=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
if [[ -z "$ndk_dir" ]]; then
  default_ndk="$HOME/Library/Android/sdk/ndk/27.0.12077973"
  [[ -d "$default_ndk" ]] && ndk_dir=$default_ndk
fi
[[ -d "$ndk_dir" ]] || { echo 'Set ANDROID_NDK_HOME to NDK 27.0.12077973.' >&2; exit 1; }
ndk_version=$(sed -n 's/^Pkg.Revision = //p' "$ndk_dir/source.properties")
[[ "$ndk_version" == "27.0.12077973" ]] || { echo "Expected NDK 27.0.12077973, found $ndk_version." >&2; exit 1; }

host_tag=darwin-x86_64
[[ $(uname -m) == arm64 ]] && host_tag=darwin-arm64
toolchain="$ndk_dir/toolchains/llvm/prebuilt/$host_tag"
if [[ ! -d "$toolchain" && -d "$ndk_dir/toolchains/llvm/prebuilt/darwin-x86_64" ]]; then
  # Android's macOS NDK distribution can provide only the Rosetta toolchain.
  host_tag=darwin-x86_64
  toolchain="$ndk_dir/toolchains/llvm/prebuilt/$host_tag"
fi
[[ -x "$toolchain/bin/clang" ]] || { echo "Missing NDK LLVM toolchain at $toolchain." >&2; exit 1; }
strip_bin="$toolchain/bin/llvm-strip"
[[ -x "$strip_bin" ]] || { echo "Missing NDK llvm-strip at $strip_bin." >&2; exit 1; }
[[ -x "$cmake_bin" ]] || { echo "CMake not found at $cmake_bin. Set CMAKE_BIN to an executable CMake binary." >&2; exit 1; }
if [[ -x "$ninja_bin" ]]; then
  cmake_generator=Ninja
  cmake_generator_args=(-G Ninja)
  generator_version=$("$ninja_bin" --version | head -1)
else
  [[ -x "$make_bin" ]] || { echo "Ninja not found at $ninja_bin and make not found at $make_bin. Set NINJA_BIN or MAKE_BIN to an executable build tool." >&2; exit 1; }
  cmake_generator='Unix Makefiles'
  cmake_generator_args=(-G 'Unix Makefiles' -DCMAKE_MAKE_PROGRAM="$make_bin")
  generator_version=$("$make_bin" -v 2>&1 | head -1 || true)
fi

mkdir -p "$output_dir/downloads" "$output_dir/sources" "$output_dir/provenance"

component_field() {
  local name=$1 field=$2
  sed -n "/\"name\": \"$name\"/,/^[[:space:]]*}/s/.*\"$field\": \"\([^\"]*\)\".*/\1/p" "$lock_file" | head -1
}

archive_name() { printf '%s-%s.%s\n' "$1" "$(component_field "$1" version)" "${2:-tar.gz}"; }

component_urls() {
  local name=$1
  sed -n "/\"name\": \"$name\"/,/^[[:space:]]*}/p" "$lock_file" | grep -E '^      "url"|^      "fallbackUrls"' | tr '"' '\n' | sed -n '/^https:\/\//p'
}

alternate_source_field() {
  local name=$1 field=$2
  sed -n "/\"name\": \"$name\"/,/^[[:space:]]*}/p" "$lock_file" | sed -n "/\"alternateSource\"/,/^[[:space:]]*}/s/.*\"$field\": \"\([^\"]*\)\".*/\1/p" | head -1
}

fetch_sources() {
  local expected_sha=$1 archive=$2 url actual_sha
  local partial="$archive.partial"
  local curl_args
  while IFS= read -r url; do
    printf 'Downloading %s from %s\n' "$(basename "$archive")" "$url" >&2
    curl_args=(--fail --location --retry "$download_retry_count" --connect-timeout "$download_connect_timeout" --max-time "$download_max_time" --output "$partial")
    [[ ! -s "$partial" ]] || curl_args+=(--continue-at -)
    if curl "${curl_args[@]}" "$url"; then
      actual_sha=$(shasum -a 256 "$partial" | awk '{print $1}')
      if [[ "$actual_sha" == "$expected_sha" ]]; then
        mv "$partial" "$archive"
        return 0
      fi
      echo "Downloaded source SHA-256 mismatch from $url; refusing artifact." >&2
      return 1
    fi
    echo "Download failed from $url; trying the next locked source URL." >&2
  done
  return 1
}

download_source() {
  local name=$1 extension=$2 sha archive alternate_url alternate_sha alternate_extension alternate_archive actual_sha
  sha=$(component_field "$name" sha256)
  archive="$output_dir/downloads/$(archive_name "$name" "$extension")"
  if [[ -f "$archive" ]]; then
    actual_sha=$(shasum -a 256 "$archive" | awk '{print $1}')
    [[ "$actual_sha" == "$sha" ]] || { echo "Cached source SHA-256 mismatch: $archive" >&2; exit 1; }
    printf '%s\n' "$archive"
    return
  fi

  alternate_url=$(alternate_source_field "$name" url)
  alternate_sha=$(alternate_source_field "$name" sha256)
  alternate_extension=$(alternate_source_field "$name" archiveExtension)
  if [[ -n "$alternate_url" && -n "$alternate_sha" && -n "$alternate_extension" ]]; then
    alternate_archive="$output_dir/downloads/$name-$(component_field "$name" version)-alternate.$alternate_extension"
    if [[ -f "$alternate_archive" ]]; then
      actual_sha=$(shasum -a 256 "$alternate_archive" | awk '{print $1}')
      [[ "$actual_sha" == "$alternate_sha" ]] || { echo "Cached alternate source SHA-256 mismatch: $alternate_archive" >&2; exit 1; }
      printf '%s\n' "$alternate_archive"
      return
    fi
  fi

  if fetch_sources "$sha" "$archive" < <(component_urls "$name"); then
    printf '%s\n' "$archive"
    return
  fi

  if [[ -n "$alternate_url" && -n "$alternate_sha" && -n "$alternate_extension" ]]; then
    if printf '%s\n' "$alternate_url" | fetch_sources "$alternate_sha" "$alternate_archive"; then
      printf '%s\n' "$alternate_archive"
      return
    fi
  fi
  echo "All locked source URLs failed for $name; retained partial downloads for resume." >&2
  exit 1
}

extract_source() {
  local name=$1 archive=$2 source_dir="$output_dir/sources/$name-$(component_field "$name" version)"
  if [[ ! -d "$source_dir" ]]; then
    local staging="$output_dir/sources/.${name}-extract-$$"
    mkdir -p "$staging"
    tar -xf "$archive" -C "$staging"
    local extracted
    extracted=$(find "$staging" -mindepth 1 -maxdepth 1 -type d | head -1)
    [[ -n "$extracted" ]] || { echo "Archive does not contain a source directory: $archive" >&2; exit 1; }
    mv "$extracted" "$source_dir"
    rmdir "$staging"
  fi
  printf '%s\n' "$source_dir"
}

source_dir() {
  printf '%s/sources/%s-%s\n' "$output_dir" "$1" "$(component_field "$1" version)"
}

apply_component_patches() {
  local component=$1 source_dir=$2 patch
  shopt -s nullglob
  local patch_paths=("$script_dir"/patches/patch_${component}_*.patch)
  shopt -u nullglob
  ((${#patch_paths[@]} == 0)) && return 0
  for patch in "${patch_paths[@]}"; do
    if git -C "$source_dir" apply --check "$patch"; then
      git -C "$source_dir" apply "$patch"
    elif git -C "$source_dir" apply --reverse --check "$patch"; then
      # The source tree may be reused after a completed or interrupted run.
      # A reverse check proves that this exact patch is already present.
      printf 'Patch already applied to %s: %s\n' "$component" "$(basename "$patch")" >&2
    else
      echo "Patch is neither applicable nor already applied: $patch" >&2
      exit 1
    fi
  done
}

copy_notices() {
  local notice_dir="$output_dir/provenance/notices"
  mkdir -p "$notice_dir"
  cp "$(source_dir podofo)/COPYING.MPL" "$notice_dir/podofo-COPYING.MPL"
  cp "$(source_dir podofo)/COPYING.LGPL" "$notice_dir/podofo-COPYING.LGPL"
  cp "$(source_dir podofo)/NOTICE" "$notice_dir/podofo-NOTICE"
  cp "$(source_dir podofo)/3rdparty/adobe/afdko/LICENSE" "$notice_dir/podofo-afdko-LICENSE"
  cp "$(source_dir podofo)/3rdparty/chromium/numerics/LICENSE" "$notice_dir/podofo-chromium-numerics-LICENSE"
  cp "$(source_dir podofo)/3rdparty/chromium/pdfium/LICENSE" "$notice_dir/podofo-pdfium-LICENSE"
  cp "$(source_dir podofo)/src/podofo/private/FoxitFonts/COPYING.txt" "$notice_dir/podofo-foxit-fonts-COPYING"
  cp "$(source_dir podofo)/src/podofo/private/LiberaLean/LICENSE.txt" "$notice_dir/podofo-liberalean-fonts-LICENSE"
  cp "$(source_dir libpng)/LICENSE" "$notice_dir/libpng-LICENSE"
  cp "$(source_dir libxml2)/Copyright" "$notice_dir/libxml2-Copyright"
  cp "$(source_dir openssl)/LICENSE" "$notice_dir/openssl-LICENSE"
  cp "$(source_dir freetype)/docs/FTL.TXT" "$notice_dir/freetype-FTL.TXT"
  cp "$(source_dir freetype)/docs/GPLv2.TXT" "$notice_dir/freetype-GPLv2.TXT"
  cp "$(source_dir zlib)/LICENSE" "$notice_dir/zlib-LICENSE"
}

write_manifest() {
  local abi=$1 prefix=$2 manifest="$output_dir/provenance/$abi.json"
  local patches_json='[]' patch_hashes='' patch
  shopt -s nullglob
  local patch_paths=("$script_dir"/patches/*.patch)
  shopt -u nullglob
  if ((${#patch_paths[@]})); then
    patches_json='['
    for patch in "${patch_paths[@]}"; do
      patch_hashes+="$(shasum -a 256 "$patch" | awk '{print $1}') $(basename "$patch")\\n"
      patches_json+="{\"file\":\"$(basename "$patch")\",\"sha256\":\"$(shasum -a 256 "$patch" | awk '{print $1}')\"},"
    done
    patches_json="${patches_json%,}]"
  fi
  local files_json='[' library
  local library_extension=a
  [[ "$linkage" == sdk-shared ]] && library_extension=so
  for library in "$prefix"/lib/libpodofo."$library_extension" "$prefix"/lib/libpng16."$library_extension" "$prefix"/lib/libxml2."$library_extension"; do
    [[ -f "$library" ]] || { echo "Expected build output missing: $library" >&2; exit 1; }
    files_json+="{\"file\":\"${library#$output_dir/}\",\"sha256\":\"$(shasum -a 256 "$library" | awk '{print $1}')\"},"
  done
  files_json="${files_json%,}]"
  printf '{\n  "schemaVersion": 1,\n  "platform": "android",\n  "abi": "%s",\n  "ndkVersion": "%s",\n  "compiler": %s,\n  "cmake": %s,\n  "generator": "%s",\n  "generatorVersion": %s,\n  "buildType": "Release",\n  "androidApi": 21,\n  "linkage": "%s",\n  "buildFlags": ["-DCMAKE_POSITION_INDEPENDENT_CODE=ON", "-ffile-prefix-map=<output>=/doccyte-podofo-android", "static OpenSSL/FreeType/zlib"],\n  "sourceLockSha256": "%s",\n  "builderRecipeSha256": "%s",\n  "deterministicTarRecipeSha256": "%s",\n  "patches": %s,\n  "outputs": %s\n}\n' \
    "$abi" "$ndk_version" "$("$toolchain/bin/clang" --version | head -1 | sed 's/.*/"&"/')" "$("$cmake_bin" --version | head -1 | sed 's/.*/"&"/')" "$cmake_generator" "$(printf '%s' "$generator_version" | sed 's/.*/"&"/')" "$linkage" \
    "$(shasum -a 256 "$lock_file" | awk '{print $1}')" \
    "$(shasum -a 256 "$script_dir/build-android.sh" | awk '{print $1}')" \
    "$(shasum -a 256 "$project_dir/scripts/deterministic-tar.py" | awk '{print $1}')" \
    "$patches_json" "$files_json" > "$manifest"
}

source_archives=(
  "podofo:tar.gz" "libpng:tar.xz" "libxml2:tar.xz" "openssl:tar.gz" "freetype:tar.xz" "zlib:tar.gz"
)
verified_archives=()
for item in "${source_archives[@]}"; do
  name=${item%%:*}; extension=${item#*:}
  archive=$(download_source "$name" "$extension")
  verified_archives+=("$archive")
  extract_source "$name" "$archive" >/dev/null
done
apply_component_patches podofo "$(source_dir podofo)"
apply_component_patches openssl "$(source_dir openssl)"
apply_component_patches libxml2 "$(source_dir libxml2)"
copy_notices

for abi in "${abis[@]}"; do
  case "$abi" in
    armeabi-v7a) triple=armv7a-linux-androideabi; openssl_target=android-arm ;;
    arm64-v8a) triple=aarch64-linux-android; openssl_target=android-arm64 ;;
    x86) triple=i686-linux-android; openssl_target=android-x86 ;;
    x86_64) triple=x86_64-linux-android; openssl_target=android-x86_64 ;;
    *) echo "Unsupported ABI: $abi" >&2; exit 2 ;;
  esac
  api=21
  reproducible_root=/doccyte-podofo-android
  abi_root="$output_dir/$abi"
  prefix="$abi_root/install"
  build_root="$abi_root/build"
  mkdir -p "$build_root" "$prefix"
  mode_file="$abi_root/.linkage"
  if [[ -f "$mode_file" && "$(< "$mode_file")" != "$linkage" ]]; then
    echo "Output ABI $abi was previously configured for $(< "$mode_file"); use a separate --output for $linkage." >&2
    exit 1
  fi
  printf '%s\n' "$linkage" > "$mode_file"
  shared_cmake=OFF
  podofo_static=TRUE
  png_shared=OFF
  png_static=ON
  [[ "$linkage" == sdk-shared ]] && {
    shared_cmake=ON
    podofo_static=FALSE
    png_shared=ON
    png_static=OFF
  }
  cmake_args=("${cmake_generator_args[@]}" -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$ndk_dir/build/cmake/android.toolchain.cmake" -DANDROID_ABI="$abi" -DANDROID_PLATFORM="android-$api" -DCMAKE_INSTALL_PREFIX="$prefix" -DBUILD_SHARED_LIBS="$shared_cmake" -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_C_FLAGS="-ffile-prefix-map=$output_dir=$reproducible_root" -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$output_dir=$reproducible_root" -DCMAKE_POLICY_VERSION_MINIMUM=3.5)

  if [[ ! -f "$build_root/zlib/.installed" ]]; then
    "$cmake_bin" -S "$(source_dir zlib)" -B "$build_root/zlib" "${cmake_args[@]}" -DBUILD_SHARED_LIBS=OFF
    "$cmake_bin" --build "$build_root/zlib" --target install --parallel
    touch "$build_root/zlib/.installed"
  fi
  if [[ ! -f "$build_root/libpng/.installed" ]]; then
    "$cmake_bin" -S "$(source_dir libpng)" -B "$build_root/libpng" "${cmake_args[@]}" -DPNG_SHARED="$png_shared" -DPNG_STATIC="$png_static" -DPNG_TESTS=OFF -DZLIB_ROOT="$prefix" -DZLIB_LIBRARY="$prefix/lib/libz.a"
    "$cmake_bin" --build "$build_root/libpng" --target install --parallel
    touch "$build_root/libpng/.installed"
  fi
  if [[ ! -f "$build_root/libxml2/.installed" ]]; then
    "$cmake_bin" -S "$(source_dir libxml2)" -B "$build_root/libxml2" "${cmake_args[@]}" -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_ZLIB=ON -DLIBXML2_WITH_CATALOG=OFF -DLIBXML2_WITH_ICONV=OFF -DLIBXML2_WITH_ICU=OFF -DLIBXML2_WITH_THREADS=OFF -DZLIB_ROOT="$prefix" -DZLIB_LIBRARY="$prefix/lib/libz.a"
    "$cmake_bin" --build "$build_root/libxml2" --target install --parallel
    touch "$build_root/libxml2/.installed"
  fi
  if [[ ! -f "$build_root/freetype/.installed" ]]; then
    "$cmake_bin" -S "$(source_dir freetype)" -B "$build_root/freetype" "${cmake_args[@]}" -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON -DFT_WITH_ZLIB=OFF -DFT_WITH_PNG=OFF
    "$cmake_bin" --build "$build_root/freetype" --target install --parallel
    touch "$build_root/freetype/.installed"
  fi

  openssl_root="$abi_root/openssl-source"
  openssl_install_prefix="$reproducible_root/$abi/openssl"
  openssl_stage="$abi_root/openssl-install-stage"
  if [[ ! -f "$openssl_root/Configure" ]]; then
    [[ ! -e "$openssl_root" ]] || { echo "Incomplete OpenSSL work directory: $openssl_root" >&2; exit 1; }
    ditto "$(source_dir openssl)" "$openssl_root"
  fi
  export ANDROID_NDK_HOME="$ndk_dir"
  export ANDROID_NDK_ROOT="$ndk_dir"
  (
    cd "$openssl_root"
    # OpenSSL 1.1.1 otherwise reads the NDK's maximum API level on r22+
    # (35 for the pinned NDK 27) while every CMake-built dependency uses
    # android-$api. Passing the define makes Configure select the same
    # target triple, headers, and availability macros as the recorded API.
    env PATH="$toolchain/bin:$PATH" \
      CC=clang AR=llvm-ar RANLIB=: \
      CPPFLAGS="-D__ANDROID_API__=$api" \
      CFLAGS="-ffile-prefix-map=$output_dir=$reproducible_root" \
      /usr/bin/perl ./Configure "$openssl_target" no-shared no-tests \
        --prefix="$openssl_install_prefix" \
        --openssldir="$reproducible_root/$abi/ssl"
  )
  PATH="$toolchain/bin:$PATH" "$make_bin" -C "$openssl_root" -j"$(sysctl -n hw.ncpu)"
  rm -rf "$openssl_stage"
  PATH="$toolchain/bin:$PATH" "$make_bin" -C "$openssl_root" install_sw DESTDIR="$openssl_stage"
  cp -R "$openssl_stage$openssl_install_prefix/include/." "$prefix/include/"
  cp -R "$openssl_stage$openssl_install_prefix/lib/." "$prefix/lib/"

  dependency_extension=a
  [[ "$linkage" == sdk-shared ]] && dependency_extension=so
  "$cmake_bin" -S "$(source_dir podofo)" -B "$build_root/podofo" "${cmake_args[@]}" -DPODOFO_BUILD_STATIC="$podofo_static" -DPODOFO_BUILD_LIB_ONLY=TRUE -DPODOFO_WANT_LCMS2=OFF -DCMAKE_PREFIX_PATH="$prefix" -DZLIB_ROOT="$prefix" -DZLIB_LIBRARY="$prefix/lib/libz.a" -DOPENSSL_ROOT_DIR="$prefix" -DOPENSSL_INCLUDE_DIR="$prefix/include" -DOPENSSL_CRYPTO_LIBRARY="$prefix/lib/libcrypto.a" -DOPENSSL_SSL_LIBRARY="$prefix/lib/libssl.a" -DFREETYPE_DIR="$prefix/lib/cmake/freetype" -DFREETYPE_LIBRARY="$prefix/lib/libfreetype.a" -DFREETYPE_INCLUDE_DIRS="$prefix/include/freetype2" -DLIBXML2_ROOT="$prefix" -DLIBXML2_LIBRARY="$prefix/lib/libxml2.$dependency_extension" -DLIBXML2_INCLUDE_DIR="$prefix/include/libxml2" -DPNG_ROOT="$prefix" -DPNG_LIBRARY="$prefix/lib/libpng16.$dependency_extension" -DPNG_PNG_INCLUDE_DIR="$prefix/include"
  "$cmake_bin" --build "$build_root/podofo" --target install --parallel
  if [[ "$linkage" == sdk-shared ]]; then
    "$strip_bin" --strip-debug \
      "$prefix/lib/libpodofo.so" \
      "$prefix/lib/libpng16.so" \
      "$prefix/lib/libxml2.so"
  fi
  write_manifest "$abi" "$prefix"
done

bundle_root="$output_dir/provenance/corresponding-source"
rm -rf "$bundle_root"
mkdir -p "$bundle_root/archives" "$bundle_root/patches" "$bundle_root/notices" "$bundle_root/recipes/android" "$bundle_root/recipes/scripts"
cp "$lock_file" "$bundle_root/"
cp "${verified_archives[@]}" "$bundle_root/archives/"
cp "$output_dir"/provenance/notices/* "$bundle_root/notices/"
cp "$script_dir/build-android.sh" "$bundle_root/recipes/android/"
cp "$project_dir/scripts/deterministic-tar.py" "$bundle_root/recipes/scripts/"
shopt -s nullglob
patches=("$script_dir"/patches/*.patch)
(( ${#patches[@]} == 0 )) || cp "${patches[@]}" "$bundle_root/patches/"
shopt -u nullglob
python3 "$project_dir/scripts/deterministic-tar.py" \
  "$output_dir/provenance/android-corresponding-source.tar.gz" \
  "$output_dir/provenance" corresponding-source
printf 'Android artifacts and provenance written to %s\n' "$output_dir"
