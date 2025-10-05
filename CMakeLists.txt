cmake_minimum_required(VERSION 3.20)

project(PoDoFo-iOS-Complete)

# iOS configuration
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_DEPLOYMENT_TARGET "16.3" CACHE STRING "Minimum iOS deployment version")

# Set architecture based on platform
if(NOT CMAKE_OSX_ARCHITECTURES)
    if(IOS_PLATFORM STREQUAL "OS")
        set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Build architectures for iOS")
    elseif(IOS_PLATFORM STREQUAL "SIMULATOR64")
        set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "Build architectures for iOS Simulator")
    else()
        set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Build architectures for iOS")
    endif()
endif()

set(CMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "" CACHE STRING "Development team")

# Use the iOS toolchain
set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/ios.toolchain.cmake" CACHE PATH "iOS toolchain file")

# Build configuration
set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Ensure C++17 is used throughout
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Common paths
set(EXTERNAL_DIR "${CMAKE_CURRENT_BINARY_DIR}/external")
set(INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/install")

# External project include
include(ExternalProject)

#==============================================================================
# OpenSSL
#==============================================================================
# Set OpenSSL target based on architecture
if(CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    set(OPENSSL_TARGET "iphoneos-cross")
    set(OPENSSL_ARCH_FLAGS "-arch arm64")
elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
    set(OPENSSL_TARGET "iossimulator-xcrun")
    set(OPENSSL_ARCH_FLAGS "-arch x86_64")
else()
    set(OPENSSL_TARGET "iphoneos-cross")
    set(OPENSSL_ARCH_FLAGS "-arch arm64")
endif()

ExternalProject_Add(
    openssl
    URL "https://www.openssl.org/source/openssl-1.1.1w.tar.gz"
    URL_HASH SHA256=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR "${EXTERNAL_DIR}/openssl"
    CONFIGURE_COMMAND ""
    BUILD_COMMAND bash -c "cd <SOURCE_DIR> && export CROSS_TOP='${CMAKE_OSX_SYSROOT}/..' && export CROSS_SDK='$(basename ${CMAKE_OSX_SYSROOT})' && export CC='${CMAKE_C_COMPILER}' && export CFLAGS='${OPENSSL_ARCH_FLAGS} -mios-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET} -isysroot ${CMAKE_OSX_SYSROOT}' && ./Configure ${OPENSSL_TARGET} no-shared no-dso no-hw no-engine --prefix=${INSTALL_DIR}/openssl && make clean && make -j4 && make install_sw"
    INSTALL_COMMAND ""
    BUILD_IN_SOURCE 1
)

#==============================================================================
# FreeType
#==============================================================================
ExternalProject_Add(
    freetype
    URL "https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.xz"
    URL_HASH SHA256=12991c4e55c506dd7f9b765933e62fd2be2e06d421505d7950a132e4f1bb484d
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR "${EXTERNAL_DIR}/freetype"
    CMAKE_ARGS
        -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/freetype
        -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
        -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_CXX_STANDARD=17
        -DCMAKE_CXX_STANDARD_REQUIRED=ON
        -DCMAKE_POLICY_CMP0025=NEW
        -DCMAKE_POLICY_VERSION=3.20
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        -DFT_DISABLE_HARFBUZZ=ON
        -DFT_DISABLE_BROTLI=ON
        -DFT_DISABLE_BZIP2=ON
        -DFT_DISABLE_PNG=ON
        -DFT_DISABLE_ZLIB=ON
        -DFT_WITH_ZLIB=OFF
        -DFT_WITH_BZIP2=OFF
        -DFT_WITH_PNG=OFF
        -DFT_WITH_HARFBUZZ=OFF
        -DFT_WITH_BROTLI=OFF
        -DBUILD_SHARED_LIBS=OFF
        -DDISABLE_FORCE_DEBUG_POSTFIX=ON
)

#==============================================================================
# LibXML2 
#==============================================================================
# Set LibXML2 host target based on architecture
if(CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    set(LIBXML2_HOST "arm-apple-darwin")
    set(LIBXML2_ARCH_FLAGS "-arch arm64")
elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
    set(LIBXML2_HOST "x86_64-apple-darwin")
    set(LIBXML2_ARCH_FLAGS "-arch x86_64")
else()
    set(LIBXML2_HOST "arm-apple-darwin")
    set(LIBXML2_ARCH_FLAGS "-arch arm64")
endif()

ExternalProject_Add(
    libxml2
    URL "https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.9.tar.xz"
    URL_HASH SHA256=59912db536ab56a3996489ea0299768c7bcffe57169f0235e7f962a91f483590
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR "${EXTERNAL_DIR}/libxml2"
    CONFIGURE_COMMAND bash -c "cd <SOURCE_DIR> && export CC='${CMAKE_C_COMPILER}' && export CFLAGS='${LIBXML2_ARCH_FLAGS} -mios-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET} -isysroot ${CMAKE_OSX_SYSROOT}' && export LDFLAGS='${LIBXML2_ARCH_FLAGS}' && ./configure --host=${LIBXML2_HOST} --prefix=${INSTALL_DIR}/libxml2 --enable-static --disable-shared --without-python --without-lzma --without-zlib --without-icu --without-readline --without-threads --disable-rebuild-docs --without-coverage --without-debug --without-mem-debug --without-run-debug --without-docbook"
    BUILD_COMMAND bash -c "cd <SOURCE_DIR> && make -j4"
    INSTALL_COMMAND bash -c "cd <SOURCE_DIR> && make install"
    BUILD_IN_SOURCE 1
)

#==============================================================================
# PoDoFo
#==============================================================================
ExternalProject_Add(
    podofo-source
    GIT_REPOSITORY "https://github.com/podofo/podofo.git"
    GIT_TAG "1.0.2"
    SOURCE_DIR "${EXTERNAL_DIR}/podofo"
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ""
)

add_custom_target(
    apply-ios16-patch
    DEPENDS podofo-source
    COMMENT "Applying iOS 16 std::from_chars compatibility patch to PoDoFo"
    COMMAND git -C "${EXTERNAL_DIR}/podofo" apply --ignore-space-change --ignore-whitespace "${CMAKE_CURRENT_SOURCE_DIR}/patches/podofo-ios16-compatibility.patch" || true
)

ExternalProject_Add(
    podofo
    DEPENDS openssl freetype libxml2 apply-ios16-patch
    SOURCE_DIR "${EXTERNAL_DIR}/podofo"
    CMAKE_ARGS
        -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/podofo
        -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
        -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_CXX_STANDARD=17
        -DCMAKE_CXX_STANDARD_REQUIRED=ON
        -DPODOFO_BUILD_STATIC=TRUE
        -DPODOFO_BUILD_TOOLS=OFF
        -DPODOFO_BUILD_EXAMPLES=OFF
        -DPODOFO_BUILD_TEST=OFF
        -DPODOFO_REQUIRE_OPENSSL=ON
        -DPODOFO_REQUIRE_LIBIDN=OFF
        -DPODOFO_REQUIRE_JPEG=OFF
        -DPODOFO_REQUIRE_TIFF=OFF
        -DPODOFO_REQUIRE_PNG=OFF
        -DPODOFO_REQUIRE_FONTCONFIG=OFF
        -DOPENSSL_ROOT_DIR=${INSTALL_DIR}/openssl
        -DOPENSSL_INCLUDE_DIR=${INSTALL_DIR}/openssl/include
        -DOPENSSL_CRYPTO_LIBRARY=${INSTALL_DIR}/openssl/lib/libcrypto.a
        -DOPENSSL_SSL_LIBRARY=${INSTALL_DIR}/openssl/lib/libssl.a
        -DFREETYPE_INCLUDE_DIRS=${INSTALL_DIR}/freetype/include/freetype2
        -DFREETYPE_LIBRARY=${INSTALL_DIR}/freetype/lib/libfreetype.a
        -DLIBXML2_INCLUDE_DIR=${INSTALL_DIR}/libxml2/include/libxml2
        -DLIBXML2_LIBRARIES=${INSTALL_DIR}/libxml2/lib/libxml2.a
    DOWNLOAD_COMMAND ""
    UPDATE_COMMAND ""
)

add_custom_target(
    create-xcframework-target
    DEPENDS podofo
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/target"
    COMMAND ${CMAKE_COMMAND} -E remove -f "${CMAKE_CURRENT_BINARY_DIR}/target/libpodofo.a"
    COMMAND libtool -static -o "${CMAKE_CURRENT_BINARY_DIR}/target/libpodofo.a"
        "${INSTALL_DIR}/podofo/lib/libpodofo.a"
        "${INSTALL_DIR}/podofo/lib/libpodofo_private.a"
        "${INSTALL_DIR}/podofo/lib/libpodofo_3rdparty.a"
        "${INSTALL_DIR}/openssl/lib/libcrypto.a"
        "${INSTALL_DIR}/openssl/lib/libssl.a"
        "${INSTALL_DIR}/freetype/lib/libfreetype.a"
        "${INSTALL_DIR}/libxml2/lib/libxml2.a"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${INSTALL_DIR}/podofo/include"
        "${CMAKE_CURRENT_BINARY_DIR}/target/include"
    COMMENT "Preparing PoDoFo library and headers for XCFramework creation"
)

# Maintain backward compatibility
add_custom_target(create-universal-target DEPENDS create-xcframework-target)

add_custom_target(all-ios DEPENDS create-xcframework-target)
