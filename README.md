# PoDoFo iOS Compilation

This project provides a comprehensive, automated build system to compile PoDoFo and all its dependencies for iOS development using a single CMake configuration.

## 🎯 Overview

PoDoFo is a free, portable C++ library for parsing and generating PDF files. This unified build system simplifies the compilation process for iOS by:

- **Single Command Build**: Everything builds with one command
- **Automatic Dependency Management**: All dependencies are downloaded and built automatically
- **Patch Management**: Git patches are automatically applied to fix iOS compatibility issues
- **Clean Architecture**: ARM64 targeting iOS 16.3+

## 📦 Dependencies Built

The build process automatically compiles these libraries for iOS:

1. **OpenSSL 1.1.1w** - Cryptographic library
2. **FreeType 2.13.2** - Font rendering library  
3. **LibXML2 2.12.9** - XML parsing library
4. **PoDoFo 1.1.0** - PDF manipulation library, pinned to upstream commit `712fb0e80e0e9404525d8db54fa0baa4ae469963`

## ⚡ Quick Start

### Requirements

- macOS with Xcode 14+ installed
- Xcode Command Line Tools
- CMake 3.20 or later
- Git

### Build Everything

```bash
# Simple one-command build
./run-ios-build.sh
```

This single script will:
- Download all source code automatically
- Apply necessary iOS compatibility patches
- Configure and build all dependencies
- Compile PoDoFo with proper linking
- Create a device arm64 and universal simulator (arm64 + x86_64) XCFramework
- Verify source, patch, architecture, header, and archive provenance

## 🔧 Manual CMake Build

If you prefer to use CMake directly:

```bash
# Create build directory
mkdir build && cd build

# Configure with iOS toolchain
cmake .. -DCMAKE_TOOLCHAIN_FILE=../ios.toolchain.cmake

# Build everything
cmake --build . --target all-ios --parallel
```

## Reproducibility and release evidence

All upstream packages are downloaded from fixed release archives with SHA-256
verification. PoDoFo 1.1.0 is fetched from its official archive and records
both its checksum and immutable upstream Git commit in the output manifest.
The old 1.0.2 `podofo-ios16-compatibility.patch` is retained for history but is
not applied: 1.1.0 includes upstream Apple `charconv` compatibility.

Each build writes the following ignored release artifacts:

- `artifacts/PoDoFo-1.1.0.xcframework`
- `artifacts/podofo-ios-1.1.0-provenance.json`
- `artifacts/podofo-ios-1.1.0-controlled-evidence.json`
- `artifacts/podofo-ios-1.1.0-corresponding-source.tar.gz`
- `artifacts/podofo-ios-1.1.0-patches.tar.gz`
- `artifacts/notices/*.txt`

The controlled evidence record (schema version 2) records the immutable PoDoFo
revision, final archive and complete XCFramework-tree hashes, exact
`Info.plist` slice metadata, architectures, and the observed Mach-O platform
and minimum OS records. Verification fails unless device objects are iOS
platform 2 at 16.3 and simulator objects are platform 7 at 16.3. The source
and patch bundles use sorted paths with normalized archive metadata. Builds
intentionally refuse to overwrite an existing release XCFramework so a
recorded artifact is never silently replaced.

To stage the iOS-owned portion of the fixed controlled-builder v2 layout after
a build, run:

```bash
./scripts/assemble-ios-controlled-fragment.sh
```

For isolated validation, `IOS_PODOFO_XCFRAMEWORK=/absolute/path` may select an
already-built XCFramework without replacing the ignored default artifact.

It creates `artifacts/controlled-builder-ios-fragment-v2` with fixed-path
bundle candidates below `payload/` and iOS-only source, patch, build, and
legacy-provenance records below `support/`.
Only reviewed contents below `payload/` may be copied into a complete bundle;
the fragment manifest and support records are inputs to the release owner, not
importer payload. The fragment intentionally has no root
`controlled-builder-manifest.env`: Android's four ABI libraries/headers,
libpng/zlib records, and the independently built `PdfTools.xcframework` are
required before a complete importer bundle can truthfully be assembled.
The iOS build uses FreeType's immutable GitHub tag archive (`.tar.gz`), while
the importer contract currently requires the Savannah `.tar.xz`; therefore
the fragment keeps the exact iOS FreeType input below `support/source/` and
explicitly leaves the contract's `source/freetype-2.13.2.tar.xz` unresolved.
This fragment supplies build evidence and never grants project-license or
release approval.

## 📋 Advanced Configuration

You can customize the build by modifying `CMakeLists.txt`:

```cmake
# Change iOS deployment target
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0")

# Add different architectures (if needed)
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")

# Modify dependency versions
# Update URLs in the ExternalProject_Add sections
```

## 🎯 Output Structure

After successful compilation:

```
build/
├── target/
│   ├── libpodofo.a           # PoDoFo and its static third-party dependencies
│   └── include/              # All headers organized
├── install/                  # Individual dependency libraries
│   ├── openssl/
│   ├── freetype/
│   ├── libxml2/
│   ├── fontconfig/
│   └── podofo/
└── external/                 # Downloaded source code
```

## 📱 iOS Integration

### Xcode Project Setup

1. **Add Library**: 
   - Drag `build/target/libpodofo.a` to your Xcode project

2. **Configure Headers**:
   - Build Settings → Header Search Paths → Add:
   ```
   $(PROJECT_DIR)/path/to/build/target/include
   ```

3. **Link Frameworks**:
   - Build Phases → Link Binary → Add:
     - Foundation.framework
     - CoreGraphics.framework
     - UIKit.framework

4. **C++ Configuration**:
   - Build Settings → C++ Language Dialect → "C++17" or later
   - Build Settings → C++ Standard Library → "libc++"

### Sample Usage

```cpp
#include <podofo/podofo.h>

// Create a new PDF document
PoDoFo::PdfMemDocument document;
PoDoFo::PdfPage& page = document.GetPages().CreatePage(PoDoFo::PdfPage::CreateStandardPageSize(PoDoFo::PdfPageSize::A4));

// Add content to the page
PoDoFo::PdfPainter painter;
painter.SetCanvas(page);
painter.GetTextState().SetFont(document.GetFonts().GetStandard14Font(PoDoFo::PdfStandard14FontType::Helvetica), 12);
painter.DrawText("Hello, iOS PDF!", 50, 800);
painter.FinishDrawing();

// Save the document
document.Save("output.pdf");
```

## 🛠️ Patch Management

The build system automatically applies patches to fix iOS compatibility:

### Current Patches

- **`patches/patch_freetype_ios.cmake`**: verified simulator-arm64 FreeType CMake fixes
- **`patches/patch_podofo_sdk_headers.cmake`**: verified SDK include ordering and optional dependency fixes
- **`patches/podofo-ios16-compatibility.patch`**: historical 1.0.2 patch; intentionally not applied to PoDoFo 1.1.0

### Adding New Patches

1. Make changes to source in `build/external/podofo/`
2. Create a patch or CMake patch script under `patches/`.
3. Make its preconditions and post-application verification fail hard, add its
   SHA-256 to the generated manifest, and document whether it applies to 1.1.0.

## 🏗️ Architecture Details

- **Target Platform**: iOS 16.3+
- **Architecture**: ARM64 (iPhone/iPad native)
- **Build Configuration**: Release with optimizations
- **C++ Standard**: C++17 compatible
- **Linking**: Static libraries only (no shared libraries for iOS)

The generated `libpodofo.a` includes PoDoFo, OpenSSL, FreeType, and libxml2.
Consumers must also link Apple's SDK `z` and `iconv` libraries, which provide
the platform implementations used by the PDF Flate filter and libxml2.

## 🔍 Troubleshooting

### Build Fails on Patch Application

If patches fail to apply:
```bash
# Check if source was modified
cd build/external/podofo
git status

# Reset and try again
git checkout .
cd ../../..
rm -rf build
./build-ios-complete.sh
```

### CMake Configuration Issues

```bash
# Clear CMake cache
rm -rf build/CMakeCache.txt build/CMakeFiles

# Reconfigure
cmake --build build --target clean
cmake build
```

### Xcode Integration Issues

- Ensure iOS Deployment Target matches (16.3+)
- Verify C++ Language Dialect is set to C++17 or later
- Check that all required frameworks are linked

## 📁 Project Structure

```
├── CMakeLists.txt              # Main unified build configuration
├── run-ios-build.sh            # Reproducible release build script
├── ios.toolchain.cmake         # iOS CMake toolchain
├── patches/                    # Git patches for iOS compatibility
│   └── patch_*.cmake           # Verified source transformations
├── scripts/                    # Provenance generation and artifact verification
└── README.md                   # This documentation
```

## 📄 License

This build system is provided under MIT license.

## 🤝 Contributing

To contribute improvements:
1. Test your changes with the unified build system
2. Update patches in the `patches/` directory if needed
3. Document any new configuration options
4. Ensure iOS 16.3+ compatibility
