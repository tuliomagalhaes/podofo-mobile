# iOS CMake Toolchain File
# This file configures CMake for iOS cross-compilation

# CMake's built-in iOS platform module assumes a physical device.  Treat the
# simulator as Darwin with an explicit simulator SDK so ARM64 simulators do
# not accidentally receive device object files.
if(IOS_PLATFORM MATCHES "SIMULATOR")
    set(CMAKE_SYSTEM_NAME Darwin)
else()
    set(CMAKE_SYSTEM_NAME iOS)
endif()
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

if(IOS_PLATFORM MATCHES "SIMULATOR" OR CMAKE_OSX_ARCHITECTURES MATCHES "x86_64")
    execute_process(COMMAND xcrun --sdk iphonesimulator --show-sdk-path OUTPUT_VARIABLE CMAKE_OSX_SYSROOT OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(IOS_PLATFORM "SIMULATOR")
else()
    execute_process(COMMAND xcrun --sdk iphoneos --show-sdk-path OUTPUT_VARIABLE CMAKE_OSX_SYSROOT OUTPUT_STRIP_TRAILING_WHITESPACE)
    # Keep FreeType's documented device selector. The parent build uses OS
    # for device slices and SIMULATOR/SIMULATOR64 for simulator slices.
    set(IOS_PLATFORM "OS")
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
if(IOS_PLATFORM MATCHES "SIMULATOR")
    set(IOS_DEPLOYMENT_FLAG "-mios-simulator-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
else()
    set(IOS_DEPLOYMENT_FLAG "-miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${IOS_DEPLOYMENT_FLAG}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${IOS_DEPLOYMENT_FLAG} -std=c++17")

# Set the find root path mode
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Prevent CMake from trying to run executables during configuration
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
