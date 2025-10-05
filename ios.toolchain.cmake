# iOS CMake Toolchain File
# This file configures CMake for iOS cross-compilation

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_VERSION 16.3)
set(CMAKE_CROSSCOMPILING TRUE)

# Set the target architecture (will be overridden by command line)
if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64")
endif()

# Set minimum iOS version
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0")
endif()

# Find the iOS SDK
execute_process(
    COMMAND xcode-select -print-path
    OUTPUT_VARIABLE XCODE_DEVELOPER_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(CMAKE_OSX_ARCHITECTURES MATCHES "x86_64")
    set(CMAKE_OSX_SYSROOT "${XCODE_DEVELOPER_DIR}/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk")
    set(IOS_PLATFORM "SIMULATOR")
else()
    set(CMAKE_OSX_SYSROOT "${XCODE_DEVELOPER_DIR}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk")
    set(IOS_PLATFORM "DEVICE")
endif()

# Set compiler and linker
set(CMAKE_C_COMPILER "${XCODE_DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang")
set(CMAKE_CXX_COMPILER "${XCODE_DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++")

# Set compiler flags
set(CMAKE_C_FLAGS_INIT "-arch ${CMAKE_OSX_ARCHITECTURES}")
set(CMAKE_CXX_FLAGS_INIT "-arch ${CMAKE_OSX_ARCHITECTURES}")

# Set C++ standard to C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Disable bitcode for simplicity
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mios-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mios-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET} -std=c++17")

# Set the find root path mode
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Prevent CMake from trying to run executables during configuration
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
