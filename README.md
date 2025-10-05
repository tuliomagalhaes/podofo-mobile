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
4. **Fontconfig 2.15.0** - Font configuration library
5. **PoDoFo 1.0.2** - PDF manipulation library (with iOS compatibility patches)

## ⚡ Quick Start

### Requirements

- macOS with Xcode 14+ installed
- Xcode Command Line Tools
- CMake 3.20 or later
- Git

### Build Everything

```bash
# Simple one-command build
./build-ios-complete.sh
```

This single script will:
- Download all source code automatically
- Apply necessary iOS compatibility patches
- Configure and build all dependencies
- Compile PoDoFo with proper linking
- Create a ready-to-use static library

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
│   ├── libpodofo.a           # Main static library (ready to use)
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

- **`patches/podofo.patch`**: Comprehensive iOS compatibility fixes for PoDoFo
  - Fixes `chars_format::` namespace issues (ensures `std::chars_format::` is used)
  - Ensures compatibility with iOS 16.3+ standard library

### Adding New Patches

1. Make changes to source in `build/external/podofo/`
2. Create patch: `git diff > patches/podofo.patch`
3. The patch is automatically applied via the `apply-podofo-patches` target in CMakeLists.txt

## 🏗️ Architecture Details

- **Target Platform**: iOS 16.3+
- **Architecture**: ARM64 (iPhone/iPad native)
- **Build Configuration**: Release with optimizations
- **C++ Standard**: C++17 compatible
- **Linking**: Static libraries only (no shared libraries for iOS)

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
├── build-ios-complete.sh       # Simple build script
├── ios.toolchain.cmake         # iOS CMake toolchain
├── patches/                    # Git patches for iOS compatibility
│   └── podofo-tokenizer.patch # PoDoFo iOS compatibility fixes
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
