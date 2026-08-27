#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd -P)
framework=${1:?XCFramework path is required}
artifact_dir="$project_dir/artifacts"
evidence="$artifact_dir/podofo-ios-1.1.0-controlled-evidence.json"
source_bundle="$artifact_dir/podofo-ios-1.1.0-corresponding-source.tar.gz"
patch_bundle="$artifact_dir/podofo-ios-1.1.0-patches.tar.gz"
provenance="$artifact_dir/podofo-ios-1.1.0-provenance.json"
fail() { echo "iOS controlled-evidence verification failed: $*" >&2; exit 1; }
device="$framework/ios-arm64/libpodofo.a"
simulator="$framework/ios-arm64_x86_64-simulator/libpodofo-ios-simulator-universal.a"
for path in "$device" "$simulator" "$framework/Info.plist" "$evidence" "$provenance" "$source_bundle" "$patch_bundle"; do
  [[ -f "$path" && -s "$path" && ! -L "$path" ]] || fail "missing regular file: $path"
done
for directory in "$framework" "$framework/ios-arm64/Headers/podofo" "$framework/ios-arm64_x86_64-simulator/Headers/podofo"; do
  [[ -d "$directory" && ! -L "$directory" ]] || fail "missing regular directory: $directory"
  special=$(find "$directory" -mindepth 1 ! -type f ! -type d -print -quit)
  [[ -z "$special" ]] || fail "symlink or special file in controlled tree: $special"
done
[[ "$(lipo -archs "$device")" == arm64 ]] || fail 'device library is not arm64 only'
actual_simulator=$(lipo -archs "$simulator")
[[ "$actual_simulator" == 'arm64 x86_64' || "$actual_simulator" == 'x86_64 arm64' ]] || fail "unexpected simulator architectures: $actual_simulator"
verify_macho() {
  local archive=$1 expected_platform=$2 count
  count=$(otool -l "$archive" | awk -v expected_platform="$expected_platform" '
    /cmd LC_BUILD_VERSION/ { active=1; platform=""; next }
    active && /platform / { platform=$2; next }
    active && /minos / { if (platform != expected_platform || $2 != "16.3") exit 2; count++; active=0 }
    END { if (count == 0) exit 3; print count }') || fail "Mach-O build metadata is not platform $expected_platform/minimum iOS 16.3: $archive"
  [[ "$count" -gt 0 ]] || fail "no Mach-O build records: $archive"
}
verify_macho "$device" 2
verify_macho "$simulator" 7
for notice in podofo-notices.txt openssl-license.txt freetype-license.txt libxml2-license.txt; do
  [[ -s "$artifact_dir/notices/$notice" ]] || fail "missing extracted notice: $notice"
done
rg -q 'AFDKO' "$artifact_dir/notices/podofo-notices.txt" || fail 'PoDoFo AFDKO notice was not extracted'
rg -q 'PDFium' "$artifact_dir/notices/podofo-notices.txt" || fail 'PoDoFo PDFium notice was not extracted'
rg -q 'Foxit standard fonts' "$artifact_dir/notices/podofo-notices.txt" || fail 'PoDoFo Foxit font notice was not extracted'
rg -q 'LiberaLean standard fonts' "$artifact_dir/notices/podofo-notices.txt" || fail 'PoDoFo LiberaLean font notice was not extracted'
python3 - "$project_dir" "$framework" "$framework/Info.plist" "$evidence" "$provenance" "$device" "$simulator" "$source_bundle" "$patch_bundle" <<'PY'
import hashlib, json, os, plistlib, sys
project, framework, plist_path, evidence_path, provenance_path, device, simulator, source_bundle, patch_bundle = sys.argv[1:]
def sha(path):
    digest=hashlib.sha256()
    with open(path,'rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''): digest.update(block)
    return digest.hexdigest()
def fail(message): raise SystemExit(message)
def tree(path):
    files=[]
    for base, directories, names in os.walk(path):
        directories.sort()
        for name in sorted(names):
            item=os.path.join(base,name)
            if os.path.islink(item) or not os.path.isfile(item): fail('non-regular tree entry: '+item)
            files.append((os.path.relpath(item,path),sha(item)))
    return hashlib.sha256(''.join(f'{digest}\t{name}\n' for name,digest in sorted(files)).encode()).hexdigest()
with open(plist_path,'rb') as stream: plist=plistlib.load(stream)
actual={entry.get('LibraryIdentifier'):(entry.get('LibraryPath'),entry.get('BinaryPath'),entry.get('HeadersPath'),entry.get('SupportedArchitectures'),entry.get('SupportedPlatform'),entry.get('SupportedPlatformVariant')) for entry in plist.get('AvailableLibraries',[])}
expected={'ios-arm64':('libpodofo.a','libpodofo.a','Headers',['arm64'],'ios',None),'ios-arm64_x86_64-simulator':('libpodofo-ios-simulator-universal.a','libpodofo-ios-simulator-universal.a','Headers',['arm64','x86_64'],'ios','simulator')}
if actual != expected: fail('Info.plist does not exactly describe device and simulator libraries')
with open(evidence_path,encoding='utf-8') as stream: evidence=json.load(stream)
if evidence.get('schemaVersion') != 2 or evidence.get('releaseApproval') is not False: fail('evidence must be schema 2 and explicitly non-approving')
if evidence.get('podofo',{}).get('version') != '1.1.0' or evidence.get('podofo',{}).get('revision') != '712fb0e80e0e9404525d8db54fa0baa4ae469963': fail('PoDoFo version/revision is incomplete')
expected_sources=[
    ('PoDoFo','1.1.0','https://github.com/podofo/podofo/archive/refs/tags/1.1.0.tar.gz','LGPL-2.0-or-later','downloads/podofo-1.1.0.tar.gz','f34b4413b613e33ab9fe83ff5aa7e2827a6425fcbcd343339458d614b7d6a951'),
    ('OpenSSL','1.1.1w','https://www.openssl.org/source/openssl-1.1.1w.tar.gz','OpenSSL','downloads/openssl-1.1.1w.tar.gz','cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8'),
    ('FreeType','2.13.2','https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-2.tar.gz','FTL OR GPL-2.0-or-later','downloads/freetype-2.13.2.tar.gz','427201f5d5151670d05c1f5b45bef5dda1f2e7dd971ef54f0feaaa7ffd2ab90c'),
    ('libxml2','2.12.9','https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.9.tar.xz','MIT','downloads/libxml2-2.12.9.tar.xz','59912db536ab56a3996489ea0299768c7bcffe57169f0235e7f962a91f483590'),
]
expected_source_records=[{'name':name,'version':version,'url':url,'licenseExpression':license_expression,'path':path,'sha256':digest} for name,version,url,license_expression,path,digest in expected_sources]
if evidence.get('sources') != expected_source_records: fail('source records are not exact and complete')
for record in expected_source_records:
    if sha(os.path.join(project,record['path'])) != record['sha256']: fail('source hash mismatch: '+record['path'])
notice_names=['freetype-license.txt','libxml2-license.txt','openssl-license.txt','podofo-notices.txt']
expected_notices=[{'path':'artifacts/notices/'+name,'sha256':sha(os.path.join(project,'artifacts','notices',name))} for name in notice_names]
if evidence.get('notices') != expected_notices: fail('notice records or hashes are incomplete')
expected_patches=[('patches/patch_freetype_ios.cmake','applied'),('patches/patch_podofo_sdk_headers.cmake','applied'),('patches/podofo-ios16-compatibility.patch','historical-not-applied-to-1.1.0')]
expected_patch_records=[{'path':path,'sha256':sha(os.path.join(project,path)),'application':application} for path,application in expected_patches]
if evidence.get('patches') != expected_patch_records: fail('patch records, hashes, or application state are incomplete')
recipe_names=['CMakeLists.txt','ios.toolchain.cmake','run-ios-build.sh','README.md','THIRD_PARTY_NOTICES.md','scripts/generate-provenance.sh','scripts/generate-controlled-evidence.sh','scripts/verify-controlled-evidence.sh','scripts/verify-artifacts.sh','scripts/assemble-ios-controlled-fragment.sh','scripts/deterministic-tar.py']
expected_recipes=[{'path':path,'sha256':sha(os.path.join(project,path))} for path in recipe_names]
if evidence.get('recipes') != expected_recipes: fail('build recipe hashes are incomplete')
if not all(evidence.get('toolchain',{}).get(key) for key in ('xcode','clang','cmake')): fail('toolchain record is incomplete')
xcframework=evidence.get('xcframework',{})
if xcframework.get('treeSha256') != tree(framework) or xcframework.get('infoPlistSha256') != sha(plist_path) or xcframework.get('infoPlist') != plist: fail('XCFramework tree or Info.plist evidence mismatch')
device_header_tree=tree(os.path.join(framework,'ios-arm64','Headers','podofo'))
simulator_header_tree=tree(os.path.join(framework,'ios-arm64_x86_64-simulator','Headers','podofo'))
if device_header_tree != simulator_header_tree: fail('device and simulator header trees differ')
if xcframework.get('headerTrees') != {'ios-arm64':device_header_tree,'ios-arm64_x86_64-simulator':simulator_header_tree}: fail('header tree evidence mismatch')
slices={entry.get('id'):entry for entry in evidence.get('xcframework',{}).get('slices',[])}
for ident,path,relative,architectures,platform in [('ios-arm64',device,'ios-arm64/libpodofo.a',['arm64'],'2'),('ios-arm64_x86_64-simulator',simulator,'ios-arm64_x86_64-simulator/libpodofo-ios-simulator-universal.a',['arm64','x86_64'],'7')]:
    item=slices.get(ident,{})
    if item.get('path') != relative or item.get('sha256') != sha(path) or item.get('architectures') != architectures: fail('slice path, hash, or architecture mismatch: '+ident)
    if item.get('machoBuildVersions') != [{'platform':platform,'minimumOS':'16.3'}]: fail('minimum OS evidence mismatch: '+ident)
if len(slices) != 2: fail('unexpected XCFramework slices in evidence')
if evidence.get('sourceBundle') != {'path':'artifacts/'+os.path.basename(source_bundle),'sha256':sha(source_bundle)}: fail('source bundle hash mismatch')
if evidence.get('patchBundle') != {'path':'artifacts/'+os.path.basename(patch_bundle),'sha256':sha(patch_bundle)}: fail('patch bundle hash mismatch')
if evidence.get('legacyProvenance') != {'path':'artifacts/'+os.path.basename(provenance_path),'sha256':sha(provenance_path)}: fail('legacy provenance hash mismatch')
with open(provenance_path,encoding='utf-8') as stream: provenance=json.load(stream)
if provenance.get('correspondingSourceBundle') != {'path':'artifacts/'+os.path.basename(source_bundle),'sha256':sha(source_bundle)}: fail('legacy provenance points to stale source bundle bytes')
PY
for header in "$framework/ios-arm64/Headers/podofo/auxiliary/podofo_config.h" "$framework/ios-arm64_x86_64-simulator/Headers/podofo/auxiliary/podofo_config.h"; do
  rg -q '^#define PODOFO_VERSION_MAJOR 1$' "$header" || fail "header major version is not 1: $header"
  rg -q '^#define PODOFO_VERSION_MINOR 1$' "$header" || fail "header minor version is not 1: $header"
  rg -q '^#define PODOFO_VERSION_PATCH 0$' "$header" || fail "header patch version is not 0: $header"
done

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT
mkdir -p "$temporary_dir/upstream" "$temporary_dir/notices"
tar -xf "$project_dir/downloads/podofo-1.1.0.tar.gz" -C "$temporary_dir/upstream"
tar -xf "$project_dir/downloads/openssl-1.1.1w.tar.gz" -C "$temporary_dir/upstream"
tar -xf "$project_dir/downloads/freetype-2.13.2.tar.gz" -C "$temporary_dir/upstream"
tar -xf "$project_dir/downloads/libxml2-2.12.9.tar.xz" -C "$temporary_dir/upstream"
append_expected_notice() {
  local destination=$1 label=$2 source=$3
  [[ -f "$source" ]] || fail "pinned source archive is missing notice input: $source"
  { printf '%s\n%s\n' "===== $label ====="; cat "$source"; printf '\n'; } >> "$destination"
}
podofo_root="$temporary_dir/upstream/podofo-1.1.0"
append_expected_notice "$temporary_dir/notices/podofo-notices.txt" 'PoDoFo COPYING.LGPL' "$podofo_root/COPYING.LGPL"
append_expected_notice "$temporary_dir/notices/podofo-notices.txt" 'PoDoFo COPYING.MPL' "$podofo_root/COPYING.MPL"
append_expected_notice "$temporary_dir/notices/podofo-notices.txt" 'PoDoFo NOTICE' "$podofo_root/NOTICE"
append_expected_notice "$temporary_dir/notices/podofo-notices.txt" 'PoDoFo AFDKO' "$podofo_root/3rdparty/adobe/afdko/LICENSE"
append_expected_notice "$temporary_dir/notices/podofo-notices.txt" 'PoDoFo Chromium numerics' "$podofo_root/3rdparty/chromium/numerics/LICENSE"
append_expected_notice "$temporary_dir/notices/podofo-notices.txt" 'PoDoFo PDFium' "$podofo_root/3rdparty/chromium/pdfium/LICENSE"
append_expected_notice "$temporary_dir/notices/podofo-notices.txt" 'PoDoFo Foxit standard fonts' "$podofo_root/src/podofo/private/FoxitFonts/COPYING.txt"
append_expected_notice "$temporary_dir/notices/podofo-notices.txt" 'PoDoFo LiberaLean standard fonts' "$podofo_root/src/podofo/private/LiberaLean/LICENSE.txt"
append_expected_notice "$temporary_dir/notices/openssl-license.txt" 'OpenSSL 1.1.1w LICENSE' "$temporary_dir/upstream/openssl-1.1.1w/LICENSE"
append_expected_notice "$temporary_dir/notices/freetype-license.txt" 'FreeType 2.13.2 LICENSE.TXT' "$temporary_dir/upstream/freetype-VER-2-13-2/LICENSE.TXT"
append_expected_notice "$temporary_dir/notices/libxml2-license.txt" 'libxml2 2.12.9 Copyright' "$temporary_dir/upstream/libxml2-2.12.9/Copyright"
for notice in podofo-notices.txt openssl-license.txt freetype-license.txt libxml2-license.txt; do
  cmp -s "$temporary_dir/notices/$notice" "$artifact_dir/notices/$notice" || fail "notice differs from immutable upstream source: $notice"
done
python3 "$project_dir/scripts/deterministic-tar.py" "$temporary_dir/source.tar.gz" "$project_dir" \
  downloads/podofo-1.1.0.tar.gz downloads/openssl-1.1.1w.tar.gz \
  downloads/freetype-2.13.2.tar.gz downloads/libxml2-2.12.9.tar.xz \
  patches README.md THIRD_PARTY_NOTICES.md CMakeLists.txt ios.toolchain.cmake run-ios-build.sh scripts
python3 "$project_dir/scripts/deterministic-tar.py" "$temporary_dir/patches.tar.gz" "$project_dir" patches
cmp -s "$temporary_dir/source.tar.gz" "$source_bundle" || fail 'corresponding-source archive is not byte-stable for current inputs'
cmp -s "$temporary_dir/patches.tar.gz" "$patch_bundle" || fail 'patch archive is not byte-stable for current inputs'
python3 - "$source_bundle" "$patch_bundle" <<'PY'
import tarfile, sys
for path in sys.argv[1:]:
    with tarfile.open(path,'r:*') as archive: members=archive.getmembers()
    names=[member.name for member in members]
    if names != sorted(names) or len(names) != len(set(names)): raise SystemExit('archive members are not unique and sorted: '+path)
    for member in members:
        if not member.isfile() or member.issym() or member.islnk() or member.uid != 0 or member.gid != 0 or member.uname or member.gname or member.mtime != 0: raise SystemExit('archive metadata is not normalized: '+path+':'+member.name)
        if member.name.startswith('/') or '..' in member.name.split('/'): raise SystemExit('unsafe archive member: '+member.name)
PY
for required in downloads/podofo-1.1.0.tar.gz downloads/openssl-1.1.1w.tar.gz downloads/freetype-2.13.2.tar.gz downloads/libxml2-2.12.9.tar.xz CMakeLists.txt ios.toolchain.cmake run-ios-build.sh README.md THIRD_PARTY_NOTICES.md; do
  tar -tzf "$source_bundle" | rg -qx "$required" || fail "source bundle is missing $required"
done
echo 'Controlled iOS evidence verified: exact source/notice/patch/recipe hashes, deterministic archives, complete matching headers, canonical Info.plist names, architectures, and Mach-O platform/minimum OS.'
