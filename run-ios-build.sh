#!/bin/bash

# PoDoFo iOS XCFramework Build Script
# Builds PoDoFo and all its dependencies for iOS as an XCFramework

set -e  # Exit on any error

echo "🚀 Starting PoDoFo iOS XCFramework Build"
echo "========================================"

# Check if we're in the right directory
if [ ! -f "CMakeLists.txt" ]; then
    echo "❌ Error: CMakeLists.txt not found. Please run this script from the project root."
    exit 1
fi

# Check if iOS toolchain exists
if [ ! -f "ios.toolchain.cmake" ]; then
    echo "❌ Error: ios.toolchain.cmake not found. Please ensure the iOS toolchain file is present."
    exit 1
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf build-*
rm -rf PoDoFo.xcframework

# Build for iOS device (arm64)
echo "⚙️  Building for iOS Device (arm64)..."
mkdir -p build-iphoneos
cd build-iphoneos

cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=../ios.toolchain.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.3 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DIOS_PLATFORM=OS

echo "🔨 Building PoDoFo for iOS Device..."
cmake --build . --target create-xcframework-target || {
    echo "❌ iOS Device build failed"
    exit 1
}

cd ..

# Build for iOS Simulator (x86_64)
echo "⚙️  Building for iOS Simulator (x86_64)..."
mkdir -p build-iphonesimulator
cd build-iphonesimulator

cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=../ios.toolchain.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.3 \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DIOS_PLATFORM=SIMULATOR64

echo "🔨 Building PoDoFo for iOS Simulator..."
cmake --build . --target create-xcframework-target || {
    echo "❌ iOS Simulator build failed"
    exit 1
}

cd ..

# Create XCFramework
echo "📦 Creating XCFramework..."
xcodebuild -create-xcframework \
    -library build-iphoneos/target/libpodofo.a -headers build-iphoneos/target/include \
    -library build-iphonesimulator/target/libpodofo.a -headers build-iphonesimulator/target/include \
    -output PoDoFo.xcframework

echo ""
echo "✅ XCFramework build completed successfully!"

# Show results
if [ -d "PoDoFo.xcframework" ]; then
    echo "� XCFramework: $(pwd)/PoDoFo.xcframework"
    echo "🎉 PoDoFo XCFramework is ready to use!"
    echo ""
    echo "Supported architectures:"
    find PoDoFo.xcframework -name "*.a" -exec echo "  - {}" \; -exec lipo -info {} \;
else
    echo "❌ XCFramework creation failed"
    exit 1
fi
