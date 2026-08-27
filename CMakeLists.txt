cmake_minimum_required(VERSION 3.20)

project(PoDoFo-iOS-Complete)

# Every upstream input is an immutable release archive with a checked SHA-256.
# The PoDoFo tag is also recorded so the exact upstream Git revision is auditable.
set(PODOFO_VERSION "1.1.0")
set(PODOFO_GIT_COMMIT "712fb0e80e0e9404525d8db54fa0baa4ae469963")
set(PODOFO_SOURCE_URL "https://github.com/podofo/podofo/archive/refs/tags/1.1.0.tar.gz")
set(PODOFO_SOURCE_SHA256 "f34b4413b613e33ab9fe83ff5aa7e2827a6425fcbcd343339458d614b7d6a951")

# iOS configuration
if(IOS_PLATFORM MATCHES "SIMULATOR")
    set(CMAKE_SYSTEM_NAME Darwin)
else()
    set(CMAKE_SYSTEM_NAME iOS)
endif()
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
if(IOS_PLATFORM MATCHES "SIMULATOR")
    set(OPENSSL_TARGET "iossimulator-xcrun")
    set(OPENSSL_ARCH_FLAGS "-arch ${CMAKE_OSX_ARCHITECTURES}")
    set(OPENSSL_DEPLOYMENT_FLAG "-mios-simulator-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    set(OPENSSL_TARGET "iphoneos-cross")
    set(OPENSSL_ARCH_FLAGS "-arch arm64")
    set(OPENSSL_DEPLOYMENT_FLAG "-miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
    set(OPENSSL_TARGET "iossimulator-xcrun")
    set(OPENSSL_ARCH_FLAGS "-arch x86_64")
    set(OPENSSL_DEPLOYMENT_FLAG "-mios-simulator-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
else()
    set(OPENSSL_TARGET "iphoneos-cross")
    set(OPENSSL_ARCH_FLAGS "-arch arm64")
    set(OPENSSL_DEPLOYMENT_FLAG "-miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()

ExternalProject_Add(
    openssl
    URL "https://www.openssl.org/source/openssl-1.1.1w.tar.gz"
    URL_HASH SHA256=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR "${EXTERNAL_DIR}/openssl"
    CONFIGURE_COMMAND ""
    BUILD_COMMAND bash -c "cd <SOURCE_DIR> && export CROSS_TOP='${CMAKE_OSX_SYSROOT}/..' && export CROSS_SDK='iPhoneSimulator.sdk' && export CC='${CMAKE_C_COMPILER}' && export CFLAGS='${OPENSSL_ARCH_FLAGS} ${OPENSSL_DEPLOYMENT_FLAG} -isysroot ${CMAKE_OSX_SYSROOT}' && /usr/bin/perl ./Configure ${OPENSSL_TARGET} no-shared no-dso no-hw no-engine --prefix=${INSTALL_DIR}/openssl && make clean && make -j4 && make install_sw"
    INSTALL_COMMAND ""
    BUILD_IN_SOURCE 1
)

#==============================================================================
# FreeType
#==============================================================================
ExternalProject_Add(
    freetype
    URL "https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-2.tar.gz"
    URL_HASH SHA256=427201f5d5151670d05c1f5b45bef5dda1f2e7dd971ef54f0feaaa7ffd2ab90c
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR "${EXTERNAL_DIR}/freetype"
    PATCH_COMMAND ${CMAKE_COMMAND} -DFREETYPE_SOURCE_DIR=${EXTERNAL_DIR}/freetype -P ${CMAKE_CURRENT_SOURCE_DIR}/patches/patch_freetype_ios.cmake
    CMAKE_ARGS
        -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
        -DCMAKE_MAKE_PROGRAM=/usr/bin/make
        -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
        -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
        -DCMAKE_AR=/usr/bin/ar
        -DCMAKE_RANLIB=/usr/bin/ranlib
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/freetype
        -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
        -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}
        -DCMAKE_OSX_SYSROOT=${CMAKE_OSX_SYSROOT}
        -DCMAKE_C_FLAGS=${OPENSSL_ARCH_FLAGS}\ ${OPENSSL_DEPLOYMENT_FLAG}\ -isysroot\ ${CMAKE_OSX_SYSROOT}
        -DCMAKE_CXX_FLAGS=${OPENSSL_ARCH_FLAGS}\ ${OPENSSL_DEPLOYMENT_FLAG}\ -isysroot\ ${CMAKE_OSX_SYSROOT}
        -DIOS_PLATFORM=${IOS_PLATFORM}
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_CXX_STANDARD=17
        -DCMAKE_CXX_STANDARD_REQUIRED=ON
        -DCMAKE_POLICY_CMP0025=NEW
        -DCMAKE_POLICY_VERSION=3.20
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        -DCMAKE_POLICY_DEFAULT_CMP0153=OLD
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
ExternalProject_Add(
    libxml2
    URL "https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.9.tar.xz"
    URL_HASH SHA256=59912db536ab56a3996489ea0299768c7bcffe57169f0235e7f962a91f483590
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR "${EXTERNAL_DIR}/libxml2"
    CMAKE_ARGS
        -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/libxml2
        -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
        -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}
        -DCMAKE_OSX_SYSROOT=${CMAKE_OSX_SYSROOT}
        -DCMAKE_C_FLAGS=${OPENSSL_ARCH_FLAGS}\ ${OPENSSL_DEPLOYMENT_FLAG}\ -isysroot\ ${CMAKE_OSX_SYSROOT}
        -DCMAKE_CXX_FLAGS=${OPENSSL_ARCH_FLAGS}\ ${OPENSSL_DEPLOYMENT_FLAG}\ -isysroot\ ${CMAKE_OSX_SYSROOT}
        -DIOS_PLATFORM=${IOS_PLATFORM}
        -DBUILD_SHARED_LIBS=OFF
        -DLIBXML2_WITH_PROGRAMS=OFF
        -DLIBXML2_WITH_TESTS=OFF
        -DLIBXML2_WITH_PYTHON=OFF
        -DLIBXML2_WITH_LZMA=OFF
        -DLIBXML2_WITH_ZLIB=OFF
        -DLIBXML2_WITH_ICONV=OFF
        -DLIBXML2_WITH_ICU=OFF
        -DLIBXML2_WITH_THREADS=OFF
)

#==============================================================================
# PoDoFo
#==============================================================================
ExternalProject_Add(
    podofo-source
    URL "${PODOFO_SOURCE_URL}"
    URL_HASH "SHA256=${PODOFO_SOURCE_SHA256}"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR "${EXTERNAL_DIR}/podofo"
    PATCH_COMMAND ${CMAKE_COMMAND} -DPODOFO_SOURCE_DIR=<SOURCE_DIR> -P ${CMAKE_CURRENT_SOURCE_DIR}/patches/patch_podofo_sdk_headers.cmake
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ""
)

ExternalProject_Add(
    podofo
    DEPENDS openssl freetype libxml2 podofo-source
    SOURCE_DIR "${EXTERNAL_DIR}/podofo"
    CMAKE_ARGS
        -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/podofo
        -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
        -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}
        -DCMAKE_OSX_SYSROOT=${CMAKE_OSX_SYSROOT}
        -DCMAKE_C_FLAGS=${OPENSSL_ARCH_FLAGS}\ ${OPENSSL_DEPLOYMENT_FLAG}\ -isysroot\ ${CMAKE_OSX_SYSROOT}
        -DCMAKE_CXX_FLAGS=${OPENSSL_ARCH_FLAGS}\ ${OPENSSL_DEPLOYMENT_FLAG}\ -isysroot\ ${CMAKE_OSX_SYSROOT}
        -DIOS_PLATFORM=${IOS_PLATFORM}
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_CXX_STANDARD=17
        -DCMAKE_CXX_STANDARD_REQUIRED=ON
        -DPODOFO_BUILD_STATIC=TRUE
        -DPODOFO_BUILD_LIB_ONLY=TRUE
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
        -DFREETYPE_INCLUDE_DIR_freetype2=${INSTALL_DIR}/freetype/include/freetype2
        -DFREETYPE_INCLUDE_DIR_ft2build=${INSTALL_DIR}/freetype/include/freetype2
        -DFREETYPE_LIBRARY=${INSTALL_DIR}/freetype/lib/libfreetype.a
        -DFREETYPE_LIBRARY_RELEASE=${INSTALL_DIR}/freetype/lib/libfreetype.a
        -DLIBXML2_INCLUDE_DIR=${INSTALL_DIR}/libxml2/include/libxml2
        -DLIBXML2_INCLUDE_DIRS=${INSTALL_DIR}/libxml2/include/libxml2
        -DLIBXML2_LIBRARIES=${INSTALL_DIR}/libxml2/lib/libxml2.a
        -DPKG_CONFIG_EXECUTABLE=PKG_CONFIG_EXECUTABLE-NOTFOUND
        -DCMAKE_IGNORE_PATH=/opt/homebrew;/usr/local
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
