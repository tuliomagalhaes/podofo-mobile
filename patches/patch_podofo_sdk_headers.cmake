if(NOT DEFINED PODOFO_SOURCE_DIR)
    message(FATAL_ERROR "PODOFO_SOURCE_DIR must be provided")
endif()

set(PODOFO_CMAKE "${PODOFO_SOURCE_DIR}/CMakeLists.txt")
file(READ "${PODOFO_CMAKE}" PODOFO_CMAKE_CONTENTS)

set(ZLIB_FIND "find_package(ZLIB REQUIRED)\n")
set(ZLIB_FIX "find_package(ZLIB REQUIRED)\n# The Apple SDK is already selected with -isysroot. Adding its raw usr/include\n# directory as an explicit system include breaks libc++ header ordering.\nset_property(TARGET ZLIB::ZLIB PROPERTY INTERFACE_INCLUDE_DIRECTORIES \"\")\n")

if(NOT PODOFO_CMAKE_CONTENTS MATCHES "INTERFACE_INCLUDE_DIRECTORIES")
    string(REPLACE "${ZLIB_FIND}" "${ZLIB_FIX}" PODOFO_CMAKE_CONTENTS "${PODOFO_CMAKE_CONTENTS}")
    file(WRITE "${PODOFO_CMAKE}" "${PODOFO_CMAKE_CONTENTS}")
endif()

set(OPTIONAL_DEPENDENCIES "
set(JPEG_FOUND FALSE)
set(TIFF_FOUND FALSE)
set(PNG_FOUND FALSE)
set(Fontconfig_FOUND FALSE)
")

if(NOT PODOFO_CMAKE_CONTENTS MATCHES "set\\(JPEG_FOUND FALSE\\)")
    string(REPLACE "find_package(JPEG)" "${OPTIONAL_DEPENDENCIES}" PODOFO_CMAKE_CONTENTS "${PODOFO_CMAKE_CONTENTS}")
    string(REPLACE "find_package(TIFF)\n" "" PODOFO_CMAKE_CONTENTS "${PODOFO_CMAKE_CONTENTS}")
    string(REPLACE "find_package(PNG)\n" "" PODOFO_CMAKE_CONTENTS "${PODOFO_CMAKE_CONTENTS}")
    string(REPLACE "find_package(Fontconfig)\n" "" PODOFO_CMAKE_CONTENTS "${PODOFO_CMAKE_CONTENTS}")
    file(WRITE "${PODOFO_CMAKE}" "${PODOFO_CMAKE_CONTENTS}")
endif()

# Fail the build if either source transformation was not actually present.
# PoDoFo 1.1.0 supplies upstream Apple charconv support, so the legacy
# podofo-ios16-compatibility.patch is intentionally not applied.
file(READ "${PODOFO_CMAKE}" PATCHED_PODOFO_CMAKE_CONTENTS)
if(NOT PATCHED_PODOFO_CMAKE_CONTENTS MATCHES "set_property\\(TARGET ZLIB::ZLIB PROPERTY INTERFACE_INCLUDE_DIRECTORIES" OR NOT PATCHED_PODOFO_CMAKE_CONTENTS MATCHES "set\\(JPEG_FOUND FALSE\\)")
    message(FATAL_ERROR "PoDoFo source patch verification failed")
endif()
