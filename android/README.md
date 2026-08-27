# Reproducible Android native build

`build-android.sh` builds PoDoFo 1.1.0, libpng 1.6.43, and libxml2 2.12.9 for
`armeabi-v7a`, `arm64-v8a`, `x86`, and `x86_64` with Android NDK 27.0.12077973.
It also builds PoDoFo's required OpenSSL, FreeType, and zlib dependencies from
the source archives pinned in `sources.lock.json`.

```bash
ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/27.0.12077973" \
  ./android/build-android.sh
```

Use `--abi arm64-v8a` for a focused validation build, or `--output DIR` to
keep generated files outside the checkout. The default `static` linkage mode
is for general native consumers. Use `--linkage sdk-shared` when preparing the
Android portion of the Doccyte controlled-builder bundle: it builds exported
`libpodofo.so`, `libpng16.so`, and `libxml2.so`, while retaining OpenSSL,
FreeType, and zlib as static inputs. Absolute build paths are normalized in
compiled sources, and the corresponding-source archive has normalized ordering,
ownership, and timestamps. An output ABI cannot be reused across the
two linkage modes; use a separate `--output` directory. Every archive is downloaded only
after its SHA-256 is checked. When a locked official fallback URL is present,
the builder tries it after a failed primary download and retains partial files
for a subsequent resumed download. FreeType also has a separately hash-locked
official GitHub tag archive fallback because its tarball bytes differ from the
Savannah release archive. The build emits:

- `android-out/<abi>/install/lib/libpodofo.a`, `libpng16.a`, and `libxml2.a`
  in `static` mode, or the corresponding shared libraries in `sdk-shared`
  mode;
- `android-out/provenance/<abi>.json`, with toolchain, flags, patches, input,
  notice, and output hashes; and
- `android-out/provenance/android-corresponding-source.tar.gz`, containing only
  the exact verified source archives (never partial downloads), lockfile,
  applied patch set, complete dependency notices, and the hashed build/archive
  recipes needed to reproduce the artifacts.

The output is a dependency staging area, not an Android AAR. In `sdk-shared`
mode, link the repository-owned bridge in a separate isolated output using
`pdf-tools-core/scripts/build-android-bridge-from-controlled-deps.sh`; that
step records the final bridge bytes without overwriting SDK artifacts.
