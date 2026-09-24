cmake_minimum_required(VERSION 3.25)

get_filename_component(ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
if(NOT DEFINED BUILD_DIR)
    set(BUILD_DIR "${ROOT}/build/Release")
endif()
get_filename_component(BUILD_DIR "${BUILD_DIR}" ABSOLUTE)
set(cache "${BUILD_DIR}/CMakeCache.txt")
if(NOT EXISTS "${cache}")
    message(FATAL_ERROR "Package build directory is not configured: ${BUILD_DIR}")
endif()

function(recurloop_cache_value key out_value)
    file(STRINGS "${cache}" lines REGEX "^${key}:[^=]*=")
    list(LENGTH lines count)
    if(NOT count EQUAL 1)
        set(${out_value} "" PARENT_SCOPE)
        return()
    endif()
    list(GET lines 0 line)
    string(REGEX REPLACE "^[^=]*=" "" value "${line}")
    set(${out_value} "${value}" PARENT_SCOPE)
endfunction()

foreach(pair IN ITEMS
        "RECURLOOP_ENABLE_LLVM|ON"
        "RECURLOOP_LLVM_PROVIDER|ARCHIVE"
        "RECURLOOP_LLVM_SELECTED_PROVIDER|ARCHIVE"
        "RECURLOOP_LLVM_LINK_TARGETS|native"
        "RECURLOOP_STATIC_CXX_RUNTIME|ON")
    string(REPLACE "|" ";" pair "${pair}")
    list(GET pair 0 key)
    list(GET pair 1 expected)
    recurloop_cache_value("${key}" actual)
    if(NOT actual STREQUAL expected)
        message(FATAL_ERROR
            "Production packaging requires ${key}=${expected}; ${BUILD_DIR} has '${actual}'. "
            "Configure through make release/make verify or the CI preset.")
    endif()
endforeach()

include("${CMAKE_CURRENT_LIST_DIR}/ReleasePlatform.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/LLVMDistribution.cmake")
recurloop_cache_value("RECURLOOP_LLVM_SELECTED_VERSION" llvm_version)
recurloop_cache_value("RECURLOOP_LLVM_SELECTED_ROOT" llvm_root)
recurloop_cache_value("RECURLOOP_LLVM_SELECTED_ARCHIVE_URL" llvm_archive_url)
recurloop_cache_value("RECURLOOP_LLVM_SELECTED_ARCHIVE_SHA256" llvm_archive_sha)
if(NOT llvm_version STREQUAL RECURLOOP_LLVM_VERSION OR llvm_archive_url STREQUAL "" OR llvm_archive_sha STREQUAL "")
    message(FATAL_ERROR "Configured release does not identify the pinned official LLVM archive")
endif()

recurloop_cache_value("RECURLOOP_RELEASE_PLATFORM" platform)
recurloop_cache_value("RECURLOOP_RELEASE_PLATFORM_DESCRIPTION" platform_description)
if(platform STREQUAL "" OR platform_description STREQUAL "")
    message(FATAL_ERROR "Configured build has no release platform contract")
endif()
if(NOT platform STREQUAL "linux-x86_64")
    message(FATAL_ERROR "Package.cmake currently implements only linux-x86_64; got '${platform}'")
endif()

file(READ "${ROOT}/CMakeLists.txt" project_file)
string(REGEX MATCH
    "project\\(RecurLoop[ \t\r\n]+VERSION[ \t\r\n]+([0-9]+\\.[0-9]+\\.[0-9]+)"
    version_match "${project_file}")
if(NOT version_match)
    message(FATAL_ERROR "Cannot determine RecurLoop version from CMakeLists.txt")
endif()
set(version "${CMAKE_MATCH_1}")

set(source_date_epoch "$ENV{SOURCE_DATE_EPOCH}")
find_program(GIT_EXECUTABLE git)
if(source_date_epoch STREQUAL "" AND GIT_EXECUTABLE)
    execute_process(COMMAND "${GIT_EXECUTABLE}" show -s --format=%ct HEAD
        WORKING_DIRECTORY "${ROOT}" OUTPUT_VARIABLE source_date_epoch
        OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE git_epoch_result ERROR_QUIET)
    if(NOT git_epoch_result EQUAL 0)
        set(source_date_epoch "")
    endif()
endif()
if(source_date_epoch STREQUAL "")
    set(source_date_epoch "0")
endif()
if(NOT source_date_epoch MATCHES "^[0-9]+$")
    message(FATAL_ERROR "SOURCE_DATE_EPOCH must be an integer, got '${source_date_epoch}'")
endif()

set(revision "unknown")
if(GIT_EXECUTABLE)
    execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --short=12 HEAD
        WORKING_DIRECTORY "${ROOT}" OUTPUT_VARIABLE revision
        OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE git_revision_result ERROR_QUIET)
    if(NOT git_revision_result EQUAL 0 OR revision STREQUAL "")
        set(revision "unknown")
    else()
        execute_process(COMMAND "${GIT_EXECUTABLE}" diff --quiet
            WORKING_DIRECTORY "${ROOT}" RESULT_VARIABLE worktree_dirty ERROR_QUIET)
        execute_process(COMMAND "${GIT_EXECUTABLE}" diff --cached --quiet
            WORKING_DIRECTORY "${ROOT}" RESULT_VARIABLE index_dirty ERROR_QUIET)
        if(NOT worktree_dirty EQUAL 0 OR NOT index_dirty EQUAL 0)
            string(APPEND revision "-dirty")
        endif()
    endif()
endif()

set(package_name "recurloop-${version}-${platform}")
set(stage_parent "${BUILD_DIR}/package-stage")
set(stage "${stage_parent}/${package_name}")
file(REMOVE_RECURSE "${stage}")
file(MAKE_DIRECTORY "${stage_parent}")
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BUILD_DIR}" --prefix "${stage}"
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "Package install failed")
endif()

set(PREFIX "${stage}")
set(RELEASE_PLATFORM "${platform}")
set(RELEASE_DESCRIPTION "${platform_description}")
include("${CMAKE_CURRENT_LIST_DIR}/AuditLinuxPackage.cmake")
file(MAKE_DIRECTORY "${stage}/share/recurloop")
string(CONCAT release_metadata
    "Format-Version: ${RECURLOOP_RELEASE_FORMAT_VERSION}\n"
    "RecurLoop-Version: ${version}\n"
    "Git-Revision: ${revision}\n"
    "Platform: ${platform}\n"
    "Runtime-ABI: ${platform_description}\n"
    "LLVM-Provider: ARCHIVE\n"
    "LLVM-Version: ${llvm_version}\n"
    "LLVM-Link-Targets: native\n"
    "LLVM-Archive: ${llvm_archive_url}\n"
    "LLVM-Archive-SHA256: ${llvm_archive_sha}\n"
    "Source-Date-Epoch: ${source_date_epoch}\n")
if(DEFINED MAX_GLIBC AND NOT MAX_GLIBC STREQUAL "")
    string(APPEND release_metadata "Verified-Glibc-Ceiling: ${MAX_GLIBC}\n")
else()
    string(APPEND release_metadata "Verified-Glibc-Ceiling: local-build-only\n")
endif()
file(WRITE "${stage}/share/recurloop/RELEASE-METADATA.txt" "${release_metadata}")

include("${CMAKE_CURRENT_LIST_DIR}/PackageIntegrity.cmake")
recurloop_require_package_layout("${stage}")
recurloop_write_package_manifest("${stage}")
set(LLVM_TOOL_DIR "${llvm_root}/bin")
include("${CMAKE_CURRENT_LIST_DIR}/VerifyPackage.cmake")

set(archive "${BUILD_DIR}/${package_name}.tar.gz")
execute_process(COMMAND "${CMAKE_COMMAND}"
    "-DROOT_DIR=${stage}" "-DARCHIVE=${archive}" "-DSOURCE_DATE_EPOCH=${source_date_epoch}"
    -P "${CMAKE_CURRENT_LIST_DIR}/CreateDeterministicArchive.cmake"
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "Package archive failed")
endif()
file(SHA256 "${archive}" digest)
get_filename_component(archive_name "${archive}" NAME)
file(WRITE "${archive}.sha256" "${digest}  ${archive_name}\n")
message(STATUS "Verified deterministic archive: ${archive}")
