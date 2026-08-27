#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd -P)
framework=${1:?XCFramework path is required}
artifact_dir="$project_dir/artifacts"
source_dir="$project_dir/downloads"
notice_dir="$artifact_dir/notices"
mkdir -p "$artifact_dir" "$source_dir" "$notice_dir"
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
cmake_bin=${CMAKE_BIN:-cmake}
if ! command -v "$cmake_bin" >/dev/null 2>&1 && [[ -x /opt/homebrew/bin/cmake ]]; then cmake_bin=/opt/homebrew/bin/cmake; fi
command -v "$cmake_bin" >/dev/null 2>&1 || { echo "CMake is required to record controlled evidence." >&2; exit 1; }

reuse_verified_source() {
  local name=$1 build_name=$2 expected_hash=$3 candidate path
  path="$source_dir/$name"
  if [[ ! -f "$path" ]]; then
    while IFS= read -r candidate; do
      [[ "$(sha256 "$candidate")" == "$expected_hash" ]] && { cp "$candidate" "$path"; break; }
    done < <(find "$project_dir" -maxdepth 4 -path '*/build-*-1.1.0/*' -type f -name "$build_name" | LC_ALL=C sort)
  fi
  [[ -f "$path" && "$(sha256 "$path")" == "$expected_hash" ]] || { echo "Missing verified source: $name" >&2; exit 1; }
}
reuse_verified_source podofo-1.1.0.tar.gz 1.1.0.tar.gz f34b4413b613e33ab9fe83ff5aa7e2827a6425fcbcd343339458d614b7d6a951
reuse_verified_source openssl-1.1.1w.tar.gz openssl-1.1.1w.tar.gz cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
reuse_verified_source freetype-2.13.2.tar.gz VER-2-13-2.tar.gz 427201f5d5151670d05c1f5b45bef5dda1f2e7dd971ef54f0feaaa7ffd2ab90c
reuse_verified_source libxml2-2.12.9.tar.xz libxml2-2.12.9.tar.xz 59912db536ab56a3996489ea0299768c7bcffe57169f0235e7f962a91f483590

rm -rf "$notice_dir"
mkdir -p "$notice_dir"
append_notice() {
  local destination=$1 label=$2 source=$3
  [[ -f "$source" ]] || { echo "Missing required notice source: $source" >&2; exit 1; }
  { printf '%s\n%s\n' "===== $label ====="; cat "$source"; printf '\n'; } >> "$destination"
}
source_root="$project_dir/build-iphoneos-1.1.0/external"
append_notice "$notice_dir/podofo-notices.txt" 'PoDoFo COPYING.LGPL' "$source_root/podofo/COPYING.LGPL"
append_notice "$notice_dir/podofo-notices.txt" 'PoDoFo COPYING.MPL' "$source_root/podofo/COPYING.MPL"
append_notice "$notice_dir/podofo-notices.txt" 'PoDoFo NOTICE' "$source_root/podofo/NOTICE"
append_notice "$notice_dir/podofo-notices.txt" 'PoDoFo AFDKO' "$source_root/podofo/3rdparty/adobe/afdko/LICENSE"
append_notice "$notice_dir/podofo-notices.txt" 'PoDoFo Chromium numerics' "$source_root/podofo/3rdparty/chromium/numerics/LICENSE"
append_notice "$notice_dir/podofo-notices.txt" 'PoDoFo PDFium' "$source_root/podofo/3rdparty/chromium/pdfium/LICENSE"
append_notice "$notice_dir/podofo-notices.txt" 'PoDoFo Foxit standard fonts' "$source_root/podofo/src/podofo/private/FoxitFonts/COPYING.txt"
append_notice "$notice_dir/podofo-notices.txt" 'PoDoFo LiberaLean standard fonts' "$source_root/podofo/src/podofo/private/LiberaLean/LICENSE.txt"
append_notice "$notice_dir/openssl-license.txt" 'OpenSSL 1.1.1w LICENSE' "$source_root/openssl/LICENSE"
append_notice "$notice_dir/freetype-license.txt" 'FreeType 2.13.2 LICENSE.TXT' "$source_root/freetype/LICENSE.TXT"
append_notice "$notice_dir/libxml2-license.txt" 'libxml2 2.12.9 Copyright' "$source_root/libxml2/Copyright"

python3 "$project_dir/scripts/deterministic-tar.py" "$artifact_dir/podofo-ios-1.1.0-corresponding-source.tar.gz" "$project_dir" \
  downloads/podofo-1.1.0.tar.gz downloads/openssl-1.1.1w.tar.gz \
  downloads/freetype-2.13.2.tar.gz downloads/libxml2-2.12.9.tar.xz \
  patches README.md THIRD_PARTY_NOTICES.md CMakeLists.txt ios.toolchain.cmake run-ios-build.sh scripts
python3 "$project_dir/scripts/deterministic-tar.py" "$artifact_dir/podofo-ios-1.1.0-patches.tar.gz" "$project_dir" patches

python3 - "$artifact_dir/podofo-ios-1.1.0-controlled-evidence.json" "$framework" "$artifact_dir/podofo-ios-1.1.0-corresponding-source.tar.gz" "$artifact_dir/podofo-ios-1.1.0-patches.tar.gz" "$project_dir" "$cmake_bin" <<'PY'
import hashlib, json, os, plistlib, subprocess, sys
output, framework, source_bundle, patch_bundle, project, cmake = sys.argv[1:]
def sha(path):
    digest=hashlib.sha256()
    with open(path,'rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''): digest.update(block)
    return digest.hexdigest()
def command(*args): return subprocess.check_output(args,text=True).strip()
def tree(path):
    files=[]
    for base, _, names in os.walk(path):
        for name in names:
            item=os.path.join(base,name)
            files.append((os.path.relpath(item,path),sha(item)))
    return hashlib.sha256(''.join(f'{digest}\t{name}\n' for name,digest in sorted(files)).encode()).hexdigest()
def versions(path):
    platform=minimum=None; values=[]
    for line in command('otool','-l',path).splitlines():
        line=line.strip()
        if line == 'cmd LC_BUILD_VERSION': platform=minimum=None
        elif platform is None and line.startswith('platform '): platform=line.split()[1]
        elif platform is not None and line.startswith('minos '):
            values.append({'platform':platform,'minimumOS':line.split()[1]}); platform=minimum=None
    return sorted({(entry['platform'],entry['minimumOS']) for entry in values})
device=os.path.join(framework,'ios-arm64','libpodofo.a')
simulator=os.path.join(framework,'ios-arm64_x86_64-simulator','libpodofo-ios-simulator-universal.a')
device_headers=os.path.join(framework,'ios-arm64','Headers','podofo')
simulator_headers=os.path.join(framework,'ios-arm64_x86_64-simulator','Headers','podofo')
with open(os.path.join(framework,'Info.plist'),'rb') as stream: plist=plistlib.load(stream)
sources=[
    ('PoDoFo','1.1.0','https://github.com/podofo/podofo/archive/refs/tags/1.1.0.tar.gz','LGPL-2.0-or-later','downloads/podofo-1.1.0.tar.gz'),
    ('OpenSSL','1.1.1w','https://www.openssl.org/source/openssl-1.1.1w.tar.gz','OpenSSL','downloads/openssl-1.1.1w.tar.gz'),
    ('FreeType','2.13.2','https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-2.tar.gz','FTL OR GPL-2.0-or-later','downloads/freetype-2.13.2.tar.gz'),
    ('libxml2','2.12.9','https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.9.tar.xz','MIT','downloads/libxml2-2.12.9.tar.xz'),
]
notices=['freetype-license.txt','libxml2-license.txt','openssl-license.txt','podofo-notices.txt']
patches=[
    ('patches/patch_freetype_ios.cmake','applied'),
    ('patches/patch_podofo_sdk_headers.cmake','applied'),
    ('patches/podofo-ios16-compatibility.patch','historical-not-applied-to-1.1.0'),
]
recipes=[
    'CMakeLists.txt','ios.toolchain.cmake','run-ios-build.sh','README.md','THIRD_PARTY_NOTICES.md',
    'scripts/generate-provenance.sh','scripts/generate-controlled-evidence.sh',
    'scripts/verify-controlled-evidence.sh','scripts/verify-artifacts.sh',
    'scripts/assemble-ios-controlled-fragment.sh','scripts/deterministic-tar.py',
]
result={
    'schemaVersion':2,
    'component':'PoDoFo iOS controlled fragment input',
    'releaseApproval':False,
    'podofo':{'version':'1.1.0','revision':'712fb0e80e0e9404525d8db54fa0baa4ae469963','sourceSha256':'f34b4413b613e33ab9fe83ff5aa7e2827a6425fcbcd343339458d614b7d6a951'},
    'toolchain':{'xcode':command('xcodebuild','-version').splitlines(),'clang':command('xcrun','clang','--version').splitlines()[0],'cmake':command(cmake,'--version').splitlines()[0]},
    'sources':[{'name':name,'version':version,'url':url,'licenseExpression':license_expression,'path':path,'sha256':sha(os.path.join(project,path))} for name,version,url,license_expression,path in sources],
    'notices':[{'path':'artifacts/notices/'+name,'sha256':sha(os.path.join(project,'artifacts','notices',name))} for name in notices],
    'patches':[{'path':path,'sha256':sha(os.path.join(project,path)),'application':application} for path,application in patches],
    'recipes':[{'path':path,'sha256':sha(os.path.join(project,path))} for path in recipes],
    'xcframework':{
        'treeSha256':tree(framework),
        'infoPlistSha256':sha(os.path.join(framework,'Info.plist')),
        'infoPlist':plist,
        'headerTrees':{'ios-arm64':tree(device_headers),'ios-arm64_x86_64-simulator':tree(simulator_headers)},
        'slices':[
            {'id':'ios-arm64','path':'ios-arm64/libpodofo.a','sha256':sha(device),'architectures':sorted(command('lipo','-archs',device).split()),'machoBuildVersions':[{'platform':p,'minimumOS':m} for p,m in versions(device)]},
            {'id':'ios-arm64_x86_64-simulator','path':'ios-arm64_x86_64-simulator/libpodofo-ios-simulator-universal.a','sha256':sha(simulator),'architectures':sorted(command('lipo','-archs',simulator).split()),'machoBuildVersions':[{'platform':p,'minimumOS':m} for p,m in versions(simulator)]},
        ],
    },
    'sourceBundle':{'path':'artifacts/'+os.path.basename(source_bundle),'sha256':sha(source_bundle)},
    'patchBundle':{'path':'artifacts/'+os.path.basename(patch_bundle),'sha256':sha(patch_bundle)},
}
with open(output,'w',encoding='utf-8') as stream: json.dump(result,stream,sort_keys=True,indent=2); stream.write('\n')
PY

# Keep the legacy provenance record linked to the same normalized source bundle
# and expose its exact hash from the schema-2 controlled evidence.
python3 - "$artifact_dir/podofo-ios-1.1.0-provenance.json" "$artifact_dir/podofo-ios-1.1.0-corresponding-source.tar.gz" "$artifact_dir/podofo-ios-1.1.0-controlled-evidence.json" <<'PY'
import hashlib, json, os, sys
provenance_path, source_bundle, evidence_path = sys.argv[1:]
def sha(path):
    digest=hashlib.sha256()
    with open(path,'rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''): digest.update(block)
    return digest.hexdigest()
with open(provenance_path,encoding='utf-8') as stream: provenance=json.load(stream)
provenance['correspondingSourceBundle']={'path':'artifacts/'+os.path.basename(source_bundle),'sha256':sha(source_bundle)}
with open(provenance_path,'w',encoding='utf-8') as stream: json.dump(provenance,stream,sort_keys=True,indent=2); stream.write('\n')
with open(evidence_path,encoding='utf-8') as stream: evidence=json.load(stream)
evidence['legacyProvenance']={'path':'artifacts/'+os.path.basename(provenance_path),'sha256':sha(provenance_path)}
with open(evidence_path,'w',encoding='utf-8') as stream: json.dump(evidence,stream,sort_keys=True,indent=2); stream.write('\n')
PY
