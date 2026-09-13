include(FetchContent)

# RecurLoop's LLVM backend is intentionally hermetic with respect to its
# third-party compiler dependencies. Do not prefer system installations here:
# a normal RecurLoop build must keep using the exact versions and archives
# pinned below until this file is intentionally updated.
#
# Host runtime facilities such as libc/pthreads are still provided by the OS.

set(RECURLOOP_ZSTD_VERSION "1.5.7")
set(RECURLOOP_ZSTD_URL
    "https://github.com/facebook/zstd/releases/download/v${RECURLOOP_ZSTD_VERSION}/zstd-${RECURLOOP_ZSTD_VERSION}.tar.gz")
set(RECURLOOP_ZSTD_SHA256
    "eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3")

set(RECURLOOP_ZLIB_VERSION "1.3.1")
set(RECURLOOP_ZLIB_URL
    "https://github.com/madler/zlib/releases/download/v${RECURLOOP_ZLIB_VERSION}/zlib-${RECURLOOP_ZLIB_VERSION}.tar.gz")
set(RECURLOOP_ZLIB_SHA256
    "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23")

set(RECURLOOP_LLVM_VERSION "22.1.6")
set(RECURLOOP_LLVM_TARGET_TRIPLE "" CACHE STRING "LLVM output target triple (empty means the build host)")
set(RECURLOOP_LLVM_CPU "generic" CACHE STRING "LLVM output CPU")
set(RECURLOOP_LLVM_FEATURES "" CACHE STRING "Comma-separated LLVM target features")
set(RECURLOOP_LLVM_SYSROOT "" CACHE PATH "Target sysroot passed to clang when linking executables")
set(RECURLOOP_LLVM_OPT_LEVEL "2" CACHE STRING "LLVM optimization level: 0, 1, 2, or 3")
set(RECURLOOP_LLVM_LINK_TARGETS "native" CACHE STRING
    "LLVM target backends linked into RecurLoop: native or all")
set_property(CACHE RECURLOOP_LLVM_LINK_TARGETS PROPERTY STRINGS native all)

string(TOLOWER "${RECURLOOP_LLVM_LINK_TARGETS}" _recurloop_llvm_link_targets)
if(NOT _recurloop_llvm_link_targets STREQUAL "native" AND
   NOT _recurloop_llvm_link_targets STREQUAL "all")
    message(FATAL_ERROR
        "RECURLOOP_LLVM_LINK_TARGETS must be 'native' or 'all' (got '${RECURLOOP_LLVM_LINK_TARGETS}')")
endif()

if(NOT RECURLOOP_LLVM_OPT_LEVEL MATCHES "^[0-3]$")
    message(FATAL_ERROR "RECURLOOP_LLVM_OPT_LEVEL must be 0, 1, 2, or 3")
endif()

# ---------------------------------------------------------------------------
# zstd 1.5.7
# ---------------------------------------------------------------------------

set(ZSTD_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_CONTRIB OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    recurloop_zstd
    URL "${RECURLOOP_ZSTD_URL}"
    URL_HASH "SHA256=${RECURLOOP_ZSTD_SHA256}"
    SOURCE_SUBDIR build/cmake
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(recurloop_zstd)

if(NOT TARGET libzstd_static)
    message(FATAL_ERROR
        "Pinned zstd ${RECURLOOP_ZSTD_VERSION} did not provide libzstd_static")
endif()

if(NOT TARGET zstd::libzstd_static)
    add_library(zstd::libzstd_static ALIAS libzstd_static)
endif()

# ---------------------------------------------------------------------------
# zlib 1.3.1
# ---------------------------------------------------------------------------
#
# LLVM 22.1.6 has zlib enabled. Build a fixed zlib and expose the canonical
# ZLIB::ZLIB target so LLVM cannot silently bind LLVMSupport to /usr/lib/libz.

set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)

FetchContent_Declare(
    recurloop_zlib
    URL "${RECURLOOP_ZLIB_URL}"
    URL_HASH "SHA256=${RECURLOOP_ZLIB_SHA256}"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(recurloop_zlib)

if(NOT TARGET zlibstatic)
    message(FATAL_ERROR
        "Pinned zlib ${RECURLOOP_ZLIB_VERSION} did not provide zlibstatic")
endif()

if(NOT TARGET ZLIB::ZLIB)
    add_library(ZLIB::ZLIB ALIAS zlibstatic)
endif()

# ---------------------------------------------------------------------------
# LLVM 22.1.6
# ---------------------------------------------------------------------------
#
# Never probe llvm-config, LLVM_DIR, CMAKE_PREFIX_PATH, /usr, or PATH for LLVM.
# Always download the exact official prebuilt archive pinned by SHA-256.

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(FATAL_ERROR
        "Pinned prebuilt LLVM ${RECURLOOP_LLVM_VERSION} currently supports Linux only")
endif()

if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
    set(_recurloop_llvm_url
        "https://github.com/llvm/llvm-project/releases/download/llvmorg-${RECURLOOP_LLVM_VERSION}/LLVM-${RECURLOOP_LLVM_VERSION}-Linux-X64.tar.xz")
    set(_recurloop_llvm_sha256
        "c5ac8ef89ca39d30cb32e9b83772f995dd891c685ebc188d593c943a64d5f8b5")
elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
    set(_recurloop_llvm_url
        "https://github.com/llvm/llvm-project/releases/download/llvmorg-${RECURLOOP_LLVM_VERSION}/LLVM-${RECURLOOP_LLVM_VERSION}-Linux-ARM64.tar.xz")
    set(_recurloop_llvm_sha256
        "b67817634e8e1c2632dfc056af14d61b94f8e6502f4e557560eea227aa22ce37")
else()
    message(FATAL_ERROR
        "No pinned LLVM ${RECURLOOP_LLVM_VERSION} package is available for host '${CMAKE_HOST_SYSTEM_PROCESSOR}'")
endif()

FetchContent_Declare(
    recurloop_llvm
    URL "${_recurloop_llvm_url}"
    URL_HASH "SHA256=${_recurloop_llvm_sha256}"
    BINARY_DIR "${CMAKE_BINARY_DIR}/dependencies/recurloop_llvm"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(recurloop_llvm)

file(GLOB_RECURSE _recurloop_llvm_configs
    "${recurloop_llvm_SOURCE_DIR}/lib/cmake/llvm/LLVMConfig.cmake"
    "${recurloop_llvm_SOURCE_DIR}/*/lib/cmake/llvm/LLVMConfig.cmake")
list(LENGTH _recurloop_llvm_configs _recurloop_llvm_config_count)

if(_recurloop_llvm_config_count EQUAL 0)
    message(FATAL_ERROR
        "Pinned LLVM ${RECURLOOP_LLVM_VERSION} package does not contain LLVMConfig.cmake")
endif()

if(NOT _recurloop_llvm_config_count EQUAL 1)
    message(FATAL_ERROR
        "Pinned LLVM ${RECURLOOP_LLVM_VERSION} package unexpectedly contains ${_recurloop_llvm_config_count} LLVMConfig.cmake files")
endif()

list(GET _recurloop_llvm_configs 0 _recurloop_llvm_config)
get_filename_component(_recurloop_llvm_dir "${_recurloop_llvm_config}" DIRECTORY)

# LLVMConfig.cmake probes optional packages. Prevent those probes from changing
# the dependency graph according to whatever happens to be installed on the
# host. zstd::libzstd_static and ZLIB::ZLIB were provided above explicitly.
set(_recurloop_saved_disable_zstd "${CMAKE_DISABLE_FIND_PACKAGE_zstd}")
set(_recurloop_saved_disable_zlib "${CMAKE_DISABLE_FIND_PACKAGE_ZLIB}")
set(_recurloop_saved_disable_libedit "${CMAKE_DISABLE_FIND_PACKAGE_LibEdit}")
set(_recurloop_saved_disable_libxml2 "${CMAKE_DISABLE_FIND_PACKAGE_LibXml2}")
set(_recurloop_saved_disable_curl "${CMAKE_DISABLE_FIND_PACKAGE_CURL}")
set(_recurloop_saved_disable_httplib "${CMAKE_DISABLE_FIND_PACKAGE_httplib}")

set(CMAKE_DISABLE_FIND_PACKAGE_zstd TRUE)
set(CMAKE_DISABLE_FIND_PACKAGE_ZLIB TRUE)
set(CMAKE_DISABLE_FIND_PACKAGE_LibEdit TRUE)
set(CMAKE_DISABLE_FIND_PACKAGE_LibXml2 TRUE)
set(CMAKE_DISABLE_FIND_PACKAGE_CURL TRUE)
set(CMAKE_DISABLE_FIND_PACKAGE_httplib TRUE)

# Ignore any stale or user-provided LLVM_DIR and use only the pinned archive.
unset(LLVM_DIR CACHE)
set(LLVM_DIR "${_recurloop_llvm_dir}")

find_package(
    LLVM
    CONFIG
    REQUIRED
    PATHS "${_recurloop_llvm_dir}"
    NO_DEFAULT_PATH
)

# Restore package-discovery flags for the rest of the parent project.
if(_recurloop_saved_disable_zstd STREQUAL "")
    unset(CMAKE_DISABLE_FIND_PACKAGE_zstd)
else()
    set(CMAKE_DISABLE_FIND_PACKAGE_zstd "${_recurloop_saved_disable_zstd}")
endif()

if(_recurloop_saved_disable_zlib STREQUAL "")
    unset(CMAKE_DISABLE_FIND_PACKAGE_ZLIB)
else()
    set(CMAKE_DISABLE_FIND_PACKAGE_ZLIB "${_recurloop_saved_disable_zlib}")
endif()

if(_recurloop_saved_disable_libedit STREQUAL "")
    unset(CMAKE_DISABLE_FIND_PACKAGE_LibEdit)
else()
    set(CMAKE_DISABLE_FIND_PACKAGE_LibEdit "${_recurloop_saved_disable_libedit}")
endif()

if(_recurloop_saved_disable_libxml2 STREQUAL "")
    unset(CMAKE_DISABLE_FIND_PACKAGE_LibXml2)
else()
    set(CMAKE_DISABLE_FIND_PACKAGE_LibXml2 "${_recurloop_saved_disable_libxml2}")
endif()

if(_recurloop_saved_disable_curl STREQUAL "")
    unset(CMAKE_DISABLE_FIND_PACKAGE_CURL)
else()
    set(CMAKE_DISABLE_FIND_PACKAGE_CURL "${_recurloop_saved_disable_curl}")
endif()

if(_recurloop_saved_disable_httplib STREQUAL "")
    unset(CMAKE_DISABLE_FIND_PACKAGE_httplib)
else()
    set(CMAKE_DISABLE_FIND_PACKAGE_httplib "${_recurloop_saved_disable_httplib}")
endif()

if(NOT LLVM_PACKAGE_VERSION STREQUAL RECURLOOP_LLVM_VERSION)
    message(FATAL_ERROR
        "Pinned LLVM archive reported version '${LLVM_PACKAGE_VERSION}', expected '${RECURLOOP_LLVM_VERSION}'")
endif()

# clang and ld.lld must come from this exact LLVM package. Do not use
# find_program(), because that can fall back to PATH/system installations.
set(RECURLOOP_LLVM_CLANG "${LLVM_TOOLS_BINARY_DIR}/clang")
set(RECURLOOP_LLVM_LLD "${LLVM_TOOLS_BINARY_DIR}/ld.lld")

if(NOT EXISTS "${RECURLOOP_LLVM_CLANG}")
    message(FATAL_ERROR
        "Pinned LLVM ${RECURLOOP_LLVM_VERSION} package does not contain clang at '${RECURLOOP_LLVM_CLANG}'")
endif()

if(NOT EXISTS "${RECURLOOP_LLVM_LLD}")
    message(FATAL_ERROR
        "Pinned LLVM ${RECURLOOP_LLVM_VERSION} package does not contain ld.lld at '${RECURLOOP_LLVM_LLD}'")
endif()

if(RECURLOOP_LLVM_TARGET_TRIPLE STREQUAL "")
    set(_recurloop_native_triple "${LLVM_DEFAULT_TARGET_TRIPLE}")

    if(_recurloop_native_triple STREQUAL "" AND EXISTS "${LLVM_TOOLS_BINARY_DIR}/llvm-config")
        execute_process(
            COMMAND "${LLVM_TOOLS_BINARY_DIR}/llvm-config" --host-target
            OUTPUT_VARIABLE _recurloop_native_triple
            OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE _recurloop_triple_result
        )
        if(NOT _recurloop_triple_result EQUAL 0)
            message(FATAL_ERROR
                "Pinned LLVM ${RECURLOOP_LLVM_VERSION} llvm-config could not report the host target")
        endif()
    endif()

    if(_recurloop_native_triple STREQUAL "")
        message(FATAL_ERROR
            "Pinned LLVM ${RECURLOOP_LLVM_VERSION} did not provide a default target triple")
    endif()

    set(RECURLOOP_LLVM_TARGET_TRIPLE "${_recurloop_native_triple}" CACHE STRING
        "LLVM output target triple (empty means the build host)" FORCE)
endif()

# Keep target backends selectable independently from the pinned LLVM archive.
# The archive still contains every backend, but the normal RecurLoop executable
# links only the host backend. Cross-compilation can opt back into all backends
# without changing source code:
#
#   -DRECURLOOP_LLVM_LINK_TARGETS=all
#   -DRECURLOOP_LLVM_TARGET_TRIPLE=<target-triple>
#
# Keep this as a cache STRING rather than an ON/OFF option so it can later grow
# into a selected-target list without replacing the public CMake setting.
if(_recurloop_llvm_link_targets STREQUAL "native")
    # Only the host code generator + object-file printer are required by
    # LlvmBackend.cpp. Do not pull the native asm parser/disassembler into the
    # executable just because they exist in the pinned LLVM distribution.
    # LLVM's nativecodegen pseudo-component expands to the native target's
    # actual code-generation libraries (for example LLVMX86CodeGen,
    # LLVMX86Desc and LLVMX86Info). AsmPrinter is part of that backend; there
    # is no standalone LLVMX86AsmPrinter library in the official LLVM 22
    # package.
    set(_recurloop_llvm_target_components
        nativecodegen
    )
    set(RECURLOOP_LLVM_INITIALIZE_ALL_TARGETS 0)
else()
    set(_recurloop_llvm_target_components ${LLVM_TARGETS_TO_BUILD})
    set(RECURLOOP_LLVM_INITIALIZE_ALL_TARGETS 1)
endif()

set(_recurloop_llvm_components
    core
    support
    target
    mc
    codegen
    passes
    ${_recurloop_llvm_target_components}
)
llvm_map_components_to_libnames(RECURLOOP_LLVM_LIBRARIES ${_recurloop_llvm_components})

message(STATUS
    "RecurLoop pinned dependencies: LLVM ${RECURLOOP_LLVM_VERSION}, zstd ${RECURLOOP_ZSTD_VERSION}, zlib ${RECURLOOP_ZLIB_VERSION}")
message(STATUS
    "RecurLoop LLVM backend: LLVM ${LLVM_PACKAGE_VERSION} from ${LLVM_DIR}")
message(STATUS
    "RecurLoop LLVM clang: '${RECURLOOP_LLVM_CLANG}'")
message(STATUS
    "RecurLoop LLVM ld.lld: '${RECURLOOP_LLVM_LLD}'")
message(STATUS
    "RecurLoop LLVM target triple: '${RECURLOOP_LLVM_TARGET_TRIPLE}'")
message(STATUS
    "RecurLoop LLVM linked targets: '${_recurloop_llvm_link_targets}' (native architecture: '${LLVM_NATIVE_ARCH}')")