cmake_minimum_required(VERSION 3.25)
project(RecurLoopPinnedToolchain LANGUAGES C CXX)

include(FetchContent)

if(NOT DEFINED RECURLOOP_ROOT OR RECURLOOP_ROOT STREQUAL "")
    get_filename_component(RECURLOOP_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
endif()
if(NOT DEFINED RECURLOOP_DEPS_DIR OR RECURLOOP_DEPS_DIR STREQUAL "")
    set(RECURLOOP_DEPS_DIR "${RECURLOOP_ROOT}/.cache/deps")
endif()

include("${RECURLOOP_ROOT}/cmake/PinnedToolchainVersions.cmake")

set(FETCHCONTENT_UPDATES_DISCONNECTED ON CACHE BOOL "" FORCE)
set(FETCHCONTENT_BASE_DIR "${RECURLOOP_DEPS_DIR}" CACHE PATH "" FORCE)

function(recurloop_reuse_dependency_source content_name)
    string(TOUPPER "${content_name}" content_upper)
    set(source_dir "${RECURLOOP_DEPS_DIR}/${content_name}-src")
    if(IS_DIRECTORY "${source_dir}")
        set("FETCHCONTENT_SOURCE_DIR_${content_upper}" "${source_dir}" PARENT_SCOPE)
    endif()
endfunction()

function(recurloop_reuse_pinned_llvm_source)
    set(source_dir "${RECURLOOP_DEPS_DIR}/recurloop_llvm-src")
    if(NOT IS_DIRECTORY "${source_dir}")
        return()
    endif()

    file(GLOB llvm_configs
        "${source_dir}/bin/llvm-config"
        "${source_dir}/*/bin/llvm-config")
    list(LENGTH llvm_configs llvm_config_count)
    if(NOT llvm_config_count EQUAL 1)
        message(STATUS "Discarding unrecognized pinned LLVM cache: ${source_dir}")
        file(REMOVE_RECURSE "${source_dir}")
        return()
    endif()

    list(GET llvm_configs 0 llvm_config)
    execute_process(
        COMMAND "${llvm_config}" --version
        OUTPUT_VARIABLE cached_version
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE version_result
        ERROR_QUIET)
    if(NOT version_result EQUAL 0 OR NOT cached_version STREQUAL RECURLOOP_LLVM_VERSION)
        message(STATUS
            "Discarding cached LLVM ${cached_version}; pinned release requires ${RECURLOOP_LLVM_VERSION}")
        file(REMOVE_RECURSE "${source_dir}")
        return()
    endif()

    set(FETCHCONTENT_SOURCE_DIR_RECURLOOP_LLVM "${source_dir}" PARENT_SCOPE)
endfunction()

# zstd is configured in this separate helper build so it never becomes part of
# RecurLoop's own Ninja graph. The output directory intentionally matches the
# historical cache path so already-built libraries can be reused unchanged.
set(ZSTD_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_CONTRIB OFF CACHE BOOL "" FORCE)
recurloop_reuse_dependency_source(recurloop_zstd)
FetchContent_Declare(
    recurloop_zstd
    URL "${RECURLOOP_ZSTD_URL}"
    URL_HASH "SHA256=${RECURLOOP_ZSTD_SHA256}"
    SOURCE_SUBDIR build/cmake
    BINARY_DIR "${RECURLOOP_DEPS_DIR}/build/llvm-runtime/zstd"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(recurloop_zstd)

# zlib is likewise built once outside the main project graph.
set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)
recurloop_reuse_dependency_source(recurloop_zlib)
FetchContent_Declare(
    recurloop_zlib
    URL "${RECURLOOP_ZLIB_URL}"
    URL_HASH "SHA256=${RECURLOOP_ZLIB_SHA256}"
    BINARY_DIR "${RECURLOOP_DEPS_DIR}/build/llvm-runtime/zlib"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(recurloop_zlib)

if(NOT DEFINED RECURLOOP_LLVM_URL OR RECURLOOP_LLVM_URL STREQUAL "")
    message(FATAL_ERROR
        "Pinned LLVM ${RECURLOOP_LLVM_VERSION} has no package for "
        "${CMAKE_HOST_SYSTEM_NAME}/${CMAKE_HOST_SYSTEM_PROCESSOR}")
endif()

# The LLVM archive is already built by upstream. FetchContent is used only as a
# verified downloader/extractor; there is no LLVM source compilation here.
# Unlike source dependencies, an LLVM cache is reusable only when its exact
# version matches the release pin. This keeps version bumps from silently
# forcing an older extracted toolchain through FETCHCONTENT_SOURCE_DIR.
recurloop_reuse_pinned_llvm_source()
FetchContent_Declare(
    recurloop_llvm
    URL "${RECURLOOP_LLVM_URL}"
    URL_HASH "SHA256=${RECURLOOP_LLVM_SHA256}"
    BINARY_DIR "${RECURLOOP_DEPS_DIR}/build/pinned-llvm-unused"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(recurloop_llvm)

if(NOT TARGET zlibstatic)
    message(FATAL_ERROR "Pinned zlib ${RECURLOOP_ZLIB_VERSION} did not provide zlibstatic")
endif()
if(NOT TARGET libzstd_static)
    message(FATAL_ERROR "Pinned zstd ${RECURLOOP_ZSTD_VERSION} did not provide libzstd_static")
endif()

# Keep final static archives outside every RecurLoop build tree. Existing
# Release-built copies are migrated there by the overlay when available.
set(_recurloop_pinned_lib_dir "${RECURLOOP_DEPS_DIR}/pinned/lib")
file(MAKE_DIRECTORY "${_recurloop_pinned_lib_dir}")
set_target_properties(zlibstatic PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${_recurloop_pinned_lib_dir}")
set_target_properties(libzstd_static PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${_recurloop_pinned_lib_dir}")

add_custom_target(RecurLoopPinnedToolchain
    DEPENDS zlibstatic libzstd_static)
