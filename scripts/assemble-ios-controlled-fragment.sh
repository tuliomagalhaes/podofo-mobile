#!/usr/bin/env bash
set -euo pipefail

# This produces the iOS-owned portion of the fixed controlled-builder v2
# layout. The fixed-path files are isolated below payload/, while iOS-only
# evidence that cannot occupy a complete bundle's fixed paths lives in support/.
# It deliberately is not a complete importer bundle.
project_dir=$(cd "$(dirname "$0")/.." && pwd -P)
artifact_dir="$project_dir/artifacts"
framework=${IOS_PODOFO_XCFRAMEWORK:-"$artifact_dir/PoDoFo-1.1.0.xcframework"}
output=${1:-"$artifact_dir/controlled-builder-ios-fragment-v2"}
[[ ! -e "$output" ]] || { echo "Refusing to overwrite existing controlled iOS fragment: $output" >&2; exit 1; }
bash "$project_dir/scripts/verify-artifacts.sh" "$framework"
payload="$output/payload"
support="$output/support"
mkdir -p "$payload/ios" "$payload/source" "$payload/notices" "$support/evidence" "$support/source"
cp -R "$framework" "$payload/ios/PoDoFo.xcframework"
for source in podofo-1.1.0.tar.gz openssl-1.1.1w.tar.gz libxml2-2.12.9.tar.xz; do cp "$project_dir/downloads/$source" "$payload/source/$source"; done
cp "$project_dir/downloads/freetype-2.13.2.tar.gz" "$support/source/freetype-2.13.2.tar.gz"
cp "$artifact_dir/podofo-ios-1.1.0-corresponding-source.tar.gz" "$support/evidence/ios-corresponding-source.tar.gz"
cp "$artifact_dir/podofo-ios-1.1.0-patches.tar.gz" "$support/evidence/ios-patches.tar.gz"
cp "$artifact_dir/podofo-ios-1.1.0-controlled-evidence.json" "$support/evidence/ios-build-manifest.json"
cp "$artifact_dir/podofo-ios-1.1.0-provenance.json" "$support/evidence/ios-provenance.json"
cp "$artifact_dir/notices/"*.txt "$payload/notices/"
python3 - "$output/fragment-manifest.json" "$output" <<'PY'
import hashlib, json, os, sys
output_path, root = sys.argv[1:]
def sha(path):
    digest=hashlib.sha256()
    with open(path,'rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''): digest.update(block)
    return digest.hexdigest()
records=[]
for base, _, names in os.walk(root):
    for name in names:
        path=os.path.join(base,name)
        records.append({'path':os.path.relpath(path,root),'sha256':sha(path)})
with open(output_path,'w',encoding='utf-8') as stream:
    json.dump({'schemaVersion':2,'kind':'ios-controlled-builder-fragment','completeImporterBundle':False,'releaseApproval':False,'payloadRoot':'payload','supportRoot':'support','integrationRule':'Copy reviewed payload contents to a complete bundle root; never copy fragment-manifest.json or support/.','missingPayload':['android/*','ios/PdfTools.xcframework','source/freetype-2.13.2.tar.xz','source/libpng-1.6.43.tar.xz','source/zlib-1.3.1.tar.gz','source/corresponding-source.tar.gz','evidence/podofo-patches.tar.gz','evidence/build-manifest.json','notices/libpng-license.txt','notices/zlib-license.txt','controlled-builder-manifest.env'],'files':sorted(records,key=lambda item:item['path'])},stream,sort_keys=True,indent=2)
    stream.write('\n')
PY
echo "Created controlled-builder v2-compatible iOS fragment (not a complete/release-approved bundle): $output"
