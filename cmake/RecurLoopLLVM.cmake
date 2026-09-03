include(FetchContent)

set(RECURLOOP_LLVM_VERSION "22.1.6" CACHE STRING "LLVM release used by the prebuilt fallback")
set(RECURLOOP_LLVM_TARGET_TRIPLE "" CACHE STRING "LLVM output target triple (empty means the build host)")
set(RECURLOOP_LLVM_CPU "generic" CACHE STRING "LLVM output CPU")
set(RECURLOOP_LLVM_FEATURES "" CACHE STRING "Comma-separated LLVM target features")
set(RECURLOOP_LLVM_SYSROOT "" CACHE PATH "Target sysroot passed to clang when linking executables")
set(RECURLOOP_LLVM_OPT_LEVEL "2" CACHE STRING "LLVM optimization level: 0, 1, 2, or 3")
set(RECURLOOP_LLVM_PACKAGE_URL "" CACHE STRING "Override URL for the prebuilt LLVM package")
set(RECURLOOP_LLVM_PACKAGE_SHA256 "" CACHE STRING "Override SHA-256 for the prebuilt LLVM package")
set(RECURLOOP_LLVM_CLANG "" CACHE FILEPATH "clang driver used for LLVM executable output")
set(RECURLOOP_LLVM_LLD "" CACHE FILEPATH "ld.lld used for LLVM object/executable output")

if (NOT RECURLOOP_LLVM_OPT_LEVEL MATCHES "^[0-3]$")
    message(FATAL_ERROR "RECURLOOP_LLVM_OPT_LEVEL must be 0, 1, 2, or 3")
endif()

# Respect an explicit LLVM_DIR first. Otherwise prefer an installed LLVM,
# including versioned distro installations which are commonly absent from
# CMake's default prefix search.
if (DEFINED LLVM_DIR AND NOT LLVM_DIR STREQUAL "")
    find_package(LLVM CONFIG REQUIRED)
else()
    find_program(RECURLOOP_LLVM_CONFIG
        NAMES llvm-config llvm-config-22 llvm-config-21 llvm-config-20 llvm-config-19 llvm-config-18)
    if (RECURLOOP_LLVM_CONFIG)
        execute_process(
            COMMAND "${RECURLOOP_LLVM_CONFIG}" --cmakedir
            OUTPUT_VARIABLE _recurloop_llvm_cmake_dir
            OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE _recurloop_llvm_config_result)
        if (_recurloop_llvm_config_result EQUAL 0)
            find_package(LLVM CONFIG QUIET PATHS "${_recurloop_llvm_cmake_dir}" NO_DEFAULT_PATH)
        endif()
    endif()
    if (NOT LLVM_FOUND)
        find_package(LLVM CONFIG QUIET)
    endif()
endif()

if (NOT LLVM_FOUND)
    if (NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
        message(FATAL_ERROR "Automatic LLVM download currently supports Linux only; set LLVM_DIR for this host")
    endif()

    if (RECURLOOP_LLVM_PACKAGE_URL STREQUAL "")
        if (CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
            set(RECURLOOP_LLVM_PACKAGE_URL
                "https://github.com/llvm/llvm-project/releases/download/llvmorg-${RECURLOOP_LLVM_VERSION}/LLVM-${RECURLOOP_LLVM_VERSION}-Linux-X64.tar.xz")
            if (RECURLOOP_LLVM_VERSION STREQUAL "22.1.6" AND RECURLOOP_LLVM_PACKAGE_SHA256 STREQUAL "")
                set(RECURLOOP_LLVM_PACKAGE_SHA256 "c5ac8ef89ca39d30cb32e9b83772f995dd891c685ebc188d593c943a64d5f8b5")
            endif()
        elseif (CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
            set(RECURLOOP_LLVM_PACKAGE_URL
                "https://github.com/llvm/llvm-project/releases/download/llvmorg-${RECURLOOP_LLVM_VERSION}/LLVM-${RECURLOOP_LLVM_VERSION}-Linux-ARM64.tar.xz")
            if (RECURLOOP_LLVM_VERSION STREQUAL "22.1.6" AND RECURLOOP_LLVM_PACKAGE_SHA256 STREQUAL "")
                set(RECURLOOP_LLVM_PACKAGE_SHA256 "b67817634e8e1c2632dfc056af14d61b94f8e6502f4e557560eea227aa22ce37")
            endif()
        else()
            message(FATAL_ERROR "No prebuilt LLVM package is known for host '${CMAKE_HOST_SYSTEM_PROCESSOR}'; set LLVM_DIR or RECURLOOP_LLVM_PACKAGE_URL")
        endif()
    endif()

    set(_recurloop_llvm_hash)
    if (NOT RECURLOOP_LLVM_PACKAGE_SHA256 STREQUAL "")
        set(_recurloop_llvm_hash URL_HASH "SHA256=${RECURLOOP_LLVM_PACKAGE_SHA256}")
    endif()
    FetchContent_Declare(recurloop_llvm
        URL "${RECURLOOP_LLVM_PACKAGE_URL}"
        ${_recurloop_llvm_hash}
        BINARY_DIR "${CMAKE_BINARY_DIR}/dependencies/recurloop_llvm"
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    FetchContent_MakeAvailable(recurloop_llvm)

    file(GLOB_RECURSE _recurloop_llvm_configs
        "${recurloop_llvm_SOURCE_DIR}/lib/cmake/llvm/LLVMConfig.cmake"
        "${recurloop_llvm_SOURCE_DIR}/*/lib/cmake/llvm/LLVMConfig.cmake")
    list(LENGTH _recurloop_llvm_configs _recurloop_llvm_config_count)
    if (_recurloop_llvm_config_count EQUAL 0)
        message(FATAL_ERROR "The downloaded LLVM package does not contain LLVMConfig.cmake")
    endif()
    list(GET _recurloop_llvm_configs 0 _recurloop_llvm_config)
    get_filename_component(LLVM_DIR "${_recurloop_llvm_config}" DIRECTORY)
    set(LLVM_DIR "${LLVM_DIR}" CACHE PATH "LLVM CMake package directory" FORCE)
    find_package(LLVM CONFIG REQUIRED PATHS "${LLVM_DIR}" NO_DEFAULT_PATH)
endif()

if (NOT RECURLOOP_LLVM_CLANG)
    unset(RECURLOOP_LLVM_CLANG CACHE)
    find_program(RECURLOOP_LLVM_CLANG NAMES clang clang-${LLVM_VERSION_MAJOR}
        HINTS "${LLVM_TOOLS_BINARY_DIR}")
endif()
if (NOT RECURLOOP_LLVM_LLD)
    unset(RECURLOOP_LLVM_LLD CACHE)
    find_program(RECURLOOP_LLVM_LLD NAMES ld.lld ld.lld-${LLVM_VERSION_MAJOR}
        HINTS "${LLVM_TOOLS_BINARY_DIR}")
endif()
if (NOT RECURLOOP_LLVM_CLANG OR NOT RECURLOOP_LLVM_LLD)
    message(FATAL_ERROR "LLVM output needs clang and ld.lld from the selected LLVM installation")
endif()

if (RECURLOOP_LLVM_TARGET_TRIPLE STREQUAL "")
    set(_recurloop_native_triple "${LLVM_DEFAULT_TARGET_TRIPLE}")
    if (_recurloop_native_triple STREQUAL "" AND EXISTS "${LLVM_TOOLS_BINARY_DIR}/llvm-config")
        execute_process(COMMAND "${LLVM_TOOLS_BINARY_DIR}/llvm-config" --host-target
            OUTPUT_VARIABLE _recurloop_native_triple OUTPUT_STRIP_TRAILING_WHITESPACE)
    endif()
    set(RECURLOOP_LLVM_TARGET_TRIPLE "${_recurloop_native_triple}" CACHE STRING
        "LLVM output target triple (empty means the build host)" FORCE)
endif()

# A prebuilt LLVM already contains its targets. Link their code generators in
# the LLVM-enabled build so changing the configured triple never triggers an LLVM
# rebuild or a source download.
set(_recurloop_llvm_components core support target mc codegen passes ${LLVM_TARGETS_TO_BUILD})
llvm_map_components_to_libnames(RECURLOOP_LLVM_LIBRARIES ${_recurloop_llvm_components})

message(STATUS "RecurLoop LLVM backend: LLVM ${LLVM_PACKAGE_VERSION} from ${LLVM_DIR}")
message(STATUS "RecurLoop LLVM target triple: '${RECURLOOP_LLVM_TARGET_TRIPLE}'")
