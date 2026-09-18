include("${CMAKE_CURRENT_LIST_DIR}/PinnedToolchainVersions.cmake")

set(RECURLOOP_TOOLCHAIN_MODE "AUTO" CACHE STRING
    "LLVM toolchain policy: AUTO, PINNED, or SYSTEM")
set_property(CACHE RECURLOOP_TOOLCHAIN_MODE PROPERTY STRINGS AUTO PINNED SYSTEM)
string(TOUPPER "${RECURLOOP_TOOLCHAIN_MODE}" _recurloop_toolchain_mode)
if(NOT _recurloop_toolchain_mode MATCHES "^(AUTO|PINNED|SYSTEM)$")
    message(FATAL_ERROR
        "RECURLOOP_TOOLCHAIN_MODE must be AUTO, PINNED, or SYSTEM "
        "(got '${RECURLOOP_TOOLCHAIN_MODE}')")
endif()

set(RECURLOOP_SYSTEM_LLVM_CONFIG "" CACHE FILEPATH
    "Optional llvm-config executable used by SYSTEM/AUTO toolchain discovery")
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

function(recurloop_find_pinned_llvm out_dir out_root out_found)
    file(GLOB configs
        "${RECURLOOP_DEPS_DIR}/recurloop_llvm-src/lib/cmake/llvm/LLVMConfig.cmake"
        "${RECURLOOP_DEPS_DIR}/recurloop_llvm-src/*/lib/cmake/llvm/LLVMConfig.cmake")
    list(LENGTH configs count)
    if(NOT count EQUAL 1)
        set(${out_dir} "" PARENT_SCOPE)
        set(${out_root} "" PARENT_SCOPE)
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()

    list(GET configs 0 config)
    get_filename_component(config_dir "${config}" DIRECTORY)
    get_filename_component(root "${config_dir}/../../.." ABSOLUTE)
    set(llvm_config "${root}/bin/llvm-config")
    if(NOT EXISTS "${llvm_config}" OR
       NOT EXISTS "${root}/bin/clang" OR
       NOT EXISTS "${root}/bin/ld.lld")
        set(${out_dir} "" PARENT_SCOPE)
        set(${out_root} "" PARENT_SCOPE)
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()

    execute_process(
        COMMAND "${llvm_config}" --version
        OUTPUT_VARIABLE version
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE version_result
        ERROR_QUIET)
    if(NOT version_result EQUAL 0 OR NOT version STREQUAL RECURLOOP_LLVM_VERSION)
        set(${out_dir} "" PARENT_SCOPE)
        set(${out_root} "" PARENT_SCOPE)
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()

    set(${out_dir} "${config_dir}" PARENT_SCOPE)
    set(${out_root} "${root}" PARENT_SCOPE)
    set(${out_found} TRUE PARENT_SCOPE)
endfunction()

function(recurloop_probe_system_llvm out_config out_cmake_dir out_bindir out_version out_found)
    if(RECURLOOP_SYSTEM_LLVM_CONFIG)
        set(llvm_config "${RECURLOOP_SYSTEM_LLVM_CONFIG}")
    else()
        find_program(llvm_config
            NAMES llvm-config-22 llvm-config-21 llvm-config-20 llvm-config-19 llvm-config
            NO_CACHE)
    endif()

    if(NOT llvm_config OR NOT EXISTS "${llvm_config}")
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()

    execute_process(
        COMMAND "${llvm_config}" --version
        OUTPUT_VARIABLE version
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE version_result
        ERROR_QUIET)
    if(NOT version_result EQUAL 0 OR
       version VERSION_LESS RECURLOOP_SYSTEM_LLVM_MIN_VERSION OR
       NOT version VERSION_LESS RECURLOOP_SYSTEM_LLVM_MAX_VERSION)
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()

    execute_process(
        COMMAND "${llvm_config}" --cmakedir
        OUTPUT_VARIABLE cmake_dir
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE cmake_result
        ERROR_QUIET)
    execute_process(
        COMMAND "${llvm_config}" --bindir
        OUTPUT_VARIABLE bindir
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE bindir_result
        ERROR_QUIET)
    if(NOT cmake_result EQUAL 0 OR NOT bindir_result EQUAL 0 OR
       NOT EXISTS "${cmake_dir}/LLVMConfig.cmake")
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()

    string(REGEX MATCH "^[0-9]+" llvm_major "${version}")
    set(clang "")
    set(lld "")
    foreach(candidate "clang-${llvm_major}" clang)
        if(EXISTS "${bindir}/${candidate}")
            set(clang "${bindir}/${candidate}")
            break()
        endif()
    endforeach()
    foreach(candidate "ld.lld-${llvm_major}" ld.lld)
        if(EXISTS "${bindir}/${candidate}")
            set(lld "${bindir}/${candidate}")
            break()
        endif()
    endforeach()
    if(clang STREQUAL "" OR lld STREQUAL "")
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()

    set(${out_config} "${llvm_config}" PARENT_SCOPE)
    set(${out_cmake_dir} "${cmake_dir}" PARENT_SCOPE)
    set(${out_bindir} "${bindir}" PARENT_SCOPE)
    set(${out_version} "${version}" PARENT_SCOPE)
    set(${out_found} TRUE PARENT_SCOPE)
endfunction()

function(recurloop_pinned_zlib_available out_found)
    set(source "${RECURLOOP_DEPS_DIR}/recurloop_zlib-src/zlib.h")
    set(generated "${RECURLOOP_DEPS_DIR}/build/llvm-runtime/zlib/zconf.h")
    set(library "${RECURLOOP_DEPS_DIR}/pinned/lib/libz.a")
    if(NOT EXISTS "${source}" OR NOT EXISTS "${generated}" OR NOT EXISTS "${library}")
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()
    file(STRINGS "${source}" version_line REGEX "^#define ZLIB_VERSION ")
    if(NOT version_line MATCHES "\"${RECURLOOP_ZLIB_VERSION}\"")
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()
    set(${out_found} TRUE PARENT_SCOPE)
endfunction()

function(recurloop_pinned_zstd_available out_found)
    set(header "${RECURLOOP_DEPS_DIR}/recurloop_zstd-src/lib/zstd.h")
    set(library "${RECURLOOP_DEPS_DIR}/pinned/lib/libzstd.a")
    if(NOT EXISTS "${header}" OR NOT EXISTS "${library}")
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()
    file(STRINGS "${header}" major_line REGEX "^#define ZSTD_VERSION_MAJOR ")
    file(STRINGS "${header}" minor_line REGEX "^#define ZSTD_VERSION_MINOR ")
    file(STRINGS "${header}" release_line REGEX "^#define ZSTD_VERSION_RELEASE ")
    string(REGEX REPLACE ".* ([0-9]+)$" "\\1" major "${major_line}")
    string(REGEX REPLACE ".* ([0-9]+)$" "\\1" minor "${minor_line}")
    string(REGEX REPLACE ".* ([0-9]+)$" "\\1" release "${release_line}")
    if(NOT "${major}.${minor}.${release}" STREQUAL RECURLOOP_ZSTD_VERSION)
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()
    set(${out_found} TRUE PARENT_SCOPE)
endfunction()

function(recurloop_prepare_pinned_toolchain)
    execute_process(
        COMMAND "${CMAKE_COMMAND}"
            "-DRECURLOOP_ROOT=${CMAKE_SOURCE_DIR}"
            "-DRECURLOOP_DEPS_DIR=${RECURLOOP_DEPS_DIR}"
            "-DRECURLOOP_C_COMPILER=${CMAKE_C_COMPILER}"
            "-DRECURLOOP_CXX_COMPILER=${CMAKE_CXX_COMPILER}"
            -P "${CMAKE_CURRENT_LIST_DIR}/PreparePinnedToolchain.cmake"
        RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "Could not prepare the pinned RecurLoop toolchain")
    endif()
endfunction()

function(recurloop_use_pinned_zlib)
    if(NOT TARGET RecurLoopPinnedZlib)
        add_library(RecurLoopPinnedZlib STATIC IMPORTED GLOBAL)
        set_target_properties(RecurLoopPinnedZlib PROPERTIES
            IMPORTED_LOCATION "${RECURLOOP_DEPS_DIR}/pinned/lib/libz.a"
            INTERFACE_INCLUDE_DIRECTORIES
                "${RECURLOOP_DEPS_DIR}/recurloop_zlib-src;${RECURLOOP_DEPS_DIR}/build/llvm-runtime/zlib")
    endif()
    if(NOT TARGET ZLIB::ZLIB)
        add_library(ZLIB::ZLIB ALIAS RecurLoopPinnedZlib)
    endif()
endfunction()

function(recurloop_use_system_zlib out_found)
    find_package(ZLIB 1.2.11 QUIET)
    if(ZLIB_FOUND AND TARGET ZLIB::ZLIB)
        set(${out_found} TRUE PARENT_SCOPE)
    else()
        set(${out_found} FALSE PARENT_SCOPE)
    endif()
endfunction()

function(recurloop_add_zstd_aliases backing_target)
    if(NOT TARGET zstd::libzstd_static)
        add_library(RecurLoopZstdStaticCompat INTERFACE IMPORTED GLOBAL)
        set_target_properties(RecurLoopZstdStaticCompat PROPERTIES
            INTERFACE_LINK_LIBRARIES "${backing_target}")
        add_library(zstd::libzstd_static ALIAS RecurLoopZstdStaticCompat)
    endif()
    if(NOT TARGET zstd::libzstd_shared)
        add_library(RecurLoopZstdSharedCompat INTERFACE IMPORTED GLOBAL)
        set_target_properties(RecurLoopZstdSharedCompat PROPERTIES
            INTERFACE_LINK_LIBRARIES "${backing_target}")
        add_library(zstd::libzstd_shared ALIAS RecurLoopZstdSharedCompat)
    endif()
endfunction()

function(recurloop_use_pinned_zstd)
    if(NOT TARGET RecurLoopPinnedZstd)
        add_library(RecurLoopPinnedZstd STATIC IMPORTED GLOBAL)
        set_target_properties(RecurLoopPinnedZstd PROPERTIES
            IMPORTED_LOCATION "${RECURLOOP_DEPS_DIR}/pinned/lib/libzstd.a"
            INTERFACE_INCLUDE_DIRECTORIES "${RECURLOOP_DEPS_DIR}/recurloop_zstd-src/lib")
    endif()
    recurloop_add_zstd_aliases(RecurLoopPinnedZstd)
endfunction()

function(recurloop_use_system_zstd out_found)
    find_package(zstd CONFIG QUIET)
    if(TARGET zstd::libzstd_static)
        recurloop_add_zstd_aliases(zstd::libzstd_static)
        set(${out_found} TRUE PARENT_SCOPE)
        return()
    endif()
    if(TARGET zstd::libzstd_shared)
        recurloop_add_zstd_aliases(zstd::libzstd_shared)
        set(${out_found} TRUE PARENT_SCOPE)
        return()
    endif()

    find_path(system_zstd_include zstd.h)
    find_library(system_zstd_library NAMES zstd)
    if(NOT system_zstd_include OR NOT system_zstd_library)
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()
    if(NOT TARGET RecurLoopSystemZstd)
        add_library(RecurLoopSystemZstd UNKNOWN IMPORTED GLOBAL)
        set_target_properties(RecurLoopSystemZstd PROPERTIES
            IMPORTED_LOCATION "${system_zstd_library}"
            INTERFACE_INCLUDE_DIRECTORIES "${system_zstd_include}")
    endif()
    recurloop_add_zstd_aliases(RecurLoopSystemZstd)
    set(${out_found} TRUE PARENT_SCOPE)
endfunction()

# Determine what is already prepared before making any network/build decision.
recurloop_find_pinned_llvm(_recurloop_pinned_llvm_dir _recurloop_pinned_llvm_root _recurloop_pinned_llvm_found)
recurloop_pinned_zlib_available(_recurloop_pinned_zlib_found)
recurloop_pinned_zstd_available(_recurloop_pinned_zstd_found)

set(_recurloop_llvm_source "")
set(_recurloop_system_llvm_config "")
set(_recurloop_system_llvm_dir "")
set(_recurloop_system_llvm_bindir "")
set(_recurloop_system_llvm_version "")

if(_recurloop_toolchain_mode STREQUAL "PINNED")
    if(NOT _recurloop_pinned_llvm_found OR
       NOT _recurloop_pinned_zlib_found OR
       NOT _recurloop_pinned_zstd_found)
        recurloop_prepare_pinned_toolchain()
        recurloop_find_pinned_llvm(_recurloop_pinned_llvm_dir _recurloop_pinned_llvm_root _recurloop_pinned_llvm_found)
        recurloop_pinned_zlib_available(_recurloop_pinned_zlib_found)
        recurloop_pinned_zstd_available(_recurloop_pinned_zstd_found)
    endif()
    if(NOT _recurloop_pinned_llvm_found OR
       NOT _recurloop_pinned_zlib_found OR
       NOT _recurloop_pinned_zstd_found)
        message(FATAL_ERROR "Pinned RecurLoop toolchain preparation did not produce all required artifacts")
    endif()
    set(_recurloop_llvm_source "PINNED")
elseif(_recurloop_toolchain_mode STREQUAL "SYSTEM")
    recurloop_probe_system_llvm(
        _recurloop_system_llvm_config _recurloop_system_llvm_dir
        _recurloop_system_llvm_bindir _recurloop_system_llvm_version
        _recurloop_system_llvm_found)
    if(NOT _recurloop_system_llvm_found)
        message(FATAL_ERROR
            "SYSTEM mode requires LLVM >= ${RECURLOOP_SYSTEM_LLVM_MIN_VERSION} and < ${RECURLOOP_SYSTEM_LLVM_MAX_VERSION}, "
            "with llvm-config, clang and ld.lld from one installation")
    endif()
    set(_recurloop_llvm_source "SYSTEM")
else()
    if(_recurloop_pinned_llvm_found)
        set(_recurloop_llvm_source "PINNED")
    else()
        recurloop_probe_system_llvm(
            _recurloop_system_llvm_config _recurloop_system_llvm_dir
            _recurloop_system_llvm_bindir _recurloop_system_llvm_version
            _recurloop_system_llvm_found)
        if(_recurloop_system_llvm_found)
            set(_recurloop_llvm_source "SYSTEM")
        else()
            message(STATUS "No compatible system LLVM found; preparing pinned LLVM ${RECURLOOP_LLVM_VERSION}")
            recurloop_prepare_pinned_toolchain()
            recurloop_find_pinned_llvm(_recurloop_pinned_llvm_dir _recurloop_pinned_llvm_root _recurloop_pinned_llvm_found)
            recurloop_pinned_zlib_available(_recurloop_pinned_zlib_found)
            recurloop_pinned_zstd_available(_recurloop_pinned_zstd_found)
            if(NOT _recurloop_pinned_llvm_found)
                message(FATAL_ERROR "Pinned LLVM preparation failed")
            endif()
            set(_recurloop_llvm_source "PINNED")
        endif()
    endif()
endif()

# Compression libraries are selected independently. AUTO prefers an already
# built pinned library but falls back to the host package without rebuilding
# anything. PINNED always uses the exact versions prepared above.
set(_recurloop_zlib_source "")
set(_recurloop_zstd_source "")
if(_recurloop_toolchain_mode STREQUAL "PINNED")
    recurloop_use_pinned_zlib()
    recurloop_use_pinned_zstd()
    set(_recurloop_zlib_source "PINNED")
    set(_recurloop_zstd_source "PINNED")
elseif(_recurloop_toolchain_mode STREQUAL "SYSTEM")
    recurloop_use_system_zlib(_recurloop_system_zlib_found)
    recurloop_use_system_zstd(_recurloop_system_zstd_found)
    if(NOT _recurloop_system_zlib_found OR NOT _recurloop_system_zstd_found)
        message(FATAL_ERROR "SYSTEM mode requires compatible host zlib and zstd development packages")
    endif()
    set(_recurloop_zlib_source "SYSTEM")
    set(_recurloop_zstd_source "SYSTEM")
else()
    if(_recurloop_pinned_zlib_found)
        recurloop_use_pinned_zlib()
        set(_recurloop_zlib_source "PINNED")
    else()
        recurloop_use_system_zlib(_recurloop_system_zlib_found)
        if(_recurloop_system_zlib_found)
            set(_recurloop_zlib_source "SYSTEM")
        else()
            recurloop_prepare_pinned_toolchain()
            recurloop_pinned_zlib_available(_recurloop_pinned_zlib_found)
            if(NOT _recurloop_pinned_zlib_found)
                message(FATAL_ERROR "Neither system nor pinned zlib is available")
            endif()
            recurloop_use_pinned_zlib()
            set(_recurloop_zlib_source "PINNED")
        endif()
    endif()

    if(_recurloop_pinned_zstd_found)
        recurloop_use_pinned_zstd()
        set(_recurloop_zstd_source "PINNED")
    else()
        recurloop_use_system_zstd(_recurloop_system_zstd_found)
        if(_recurloop_system_zstd_found)
            set(_recurloop_zstd_source "SYSTEM")
        else()
            recurloop_prepare_pinned_toolchain()
            recurloop_pinned_zstd_available(_recurloop_pinned_zstd_found)
            if(NOT _recurloop_pinned_zstd_found)
                message(FATAL_ERROR "Neither system nor pinned zstd is available")
            endif()
            recurloop_use_pinned_zstd()
            set(_recurloop_zstd_source "PINNED")
        endif()
    endif()
endif()

# Load exactly the LLVM package chosen above. The pinned package is isolated
# from host LLVM discovery; SYSTEM was already version-checked via llvm-config.
if(_recurloop_llvm_source STREQUAL "PINNED")
    set(_recurloop_llvm_dir "${_recurloop_pinned_llvm_dir}")
    set(_recurloop_llvm_bindir "${_recurloop_pinned_llvm_root}/bin")

    # The official binary archive can mention optional host packages. Keep
    # those probes deterministic; zlib/zstd targets were supplied above.
    set(_recurloop_saved_disable_zstd "${CMAKE_DISABLE_FIND_PACKAGE_zstd}")
    set(_recurloop_saved_disable_zlib "${CMAKE_DISABLE_FIND_PACKAGE_ZLIB}")
    set(_recurloop_saved_disable_libedit "${CMAKE_DISABLE_FIND_PACKAGE_LibEdit}")
    set(_recurloop_saved_disable_libxml2 "${CMAKE_DISABLE_FIND_PACKAGE_LibXml2}")
    set(_recurloop_saved_disable_curl "${CMAKE_DISABLE_FIND_PACKAGE_CURL}")
    set(_recurloop_saved_disable_httplib "${CMAKE_DISABLE_FIND_PACKAGE_httplib}")
    if(_recurloop_zstd_source STREQUAL "PINNED")
        set(CMAKE_DISABLE_FIND_PACKAGE_zstd TRUE)
    endif()
    if(_recurloop_zlib_source STREQUAL "PINNED")
        set(CMAKE_DISABLE_FIND_PACKAGE_ZLIB TRUE)
    endif()
    set(CMAKE_DISABLE_FIND_PACKAGE_LibEdit TRUE)
    set(CMAKE_DISABLE_FIND_PACKAGE_LibXml2 TRUE)
    set(CMAKE_DISABLE_FIND_PACKAGE_CURL TRUE)
    set(CMAKE_DISABLE_FIND_PACKAGE_httplib TRUE)

    set(LLVM_DIR "${_recurloop_llvm_dir}" CACHE PATH "Selected LLVM CMake package" FORCE)
    find_package(LLVM CONFIG REQUIRED PATHS "${_recurloop_llvm_dir}" NO_DEFAULT_PATH)

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
            "Pinned LLVM reported version '${LLVM_PACKAGE_VERSION}', expected '${RECURLOOP_LLVM_VERSION}'")
    endif()
else()
    set(_recurloop_llvm_dir "${_recurloop_system_llvm_dir}")
    set(_recurloop_llvm_bindir "${_recurloop_system_llvm_bindir}")
    set(LLVM_DIR "${_recurloop_llvm_dir}" CACHE PATH "Selected LLVM CMake package" FORCE)
    find_package(LLVM CONFIG REQUIRED PATHS "${_recurloop_llvm_dir}" NO_DEFAULT_PATH)
    if(LLVM_PACKAGE_VERSION VERSION_LESS RECURLOOP_SYSTEM_LLVM_MIN_VERSION OR
       NOT LLVM_PACKAGE_VERSION VERSION_LESS RECURLOOP_SYSTEM_LLVM_MAX_VERSION)
        message(FATAL_ERROR "Selected system LLVM ${LLVM_PACKAGE_VERSION} is outside the supported range")
    endif()
endif()

string(REGEX MATCH "^[0-9]+" _recurloop_llvm_major "${LLVM_PACKAGE_VERSION}")
set(RECURLOOP_LLVM_CLANG "")
set(RECURLOOP_LLVM_LLD "")
foreach(candidate "clang-${_recurloop_llvm_major}" clang)
    if(EXISTS "${_recurloop_llvm_bindir}/${candidate}")
        set(RECURLOOP_LLVM_CLANG "${_recurloop_llvm_bindir}/${candidate}")
        break()
    endif()
endforeach()
foreach(candidate "ld.lld-${_recurloop_llvm_major}" ld.lld)
    if(EXISTS "${_recurloop_llvm_bindir}/${candidate}")
        set(RECURLOOP_LLVM_LLD "${_recurloop_llvm_bindir}/${candidate}")
        break()
    endif()
endforeach()
if(RECURLOOP_LLVM_CLANG STREQUAL "" OR RECURLOOP_LLVM_LLD STREQUAL "")
    message(FATAL_ERROR "Selected LLVM ${LLVM_PACKAGE_VERSION} does not provide matching clang and ld.lld")
endif()

if(RECURLOOP_LLVM_TARGET_TRIPLE STREQUAL "")
    set(_recurloop_native_triple "${LLVM_DEFAULT_TARGET_TRIPLE}")
    if(_recurloop_native_triple STREQUAL "" AND EXISTS "${_recurloop_llvm_bindir}/llvm-config")
        execute_process(
            COMMAND "${_recurloop_llvm_bindir}/llvm-config" --host-target
            OUTPUT_VARIABLE _recurloop_native_triple
            OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE _recurloop_triple_result)
        if(NOT _recurloop_triple_result EQUAL 0)
            set(_recurloop_native_triple "")
        endif()
    endif()
    if(_recurloop_native_triple STREQUAL "")
        message(FATAL_ERROR "Selected LLVM ${LLVM_PACKAGE_VERSION} did not provide a default target triple")
    endif()
    set(RECURLOOP_LLVM_TARGET_TRIPLE "${_recurloop_native_triple}" CACHE STRING
        "LLVM output target triple (empty means the build host)" FORCE)
endif()

if(_recurloop_llvm_link_targets STREQUAL "native")
    set(_recurloop_llvm_target_components nativecodegen)
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
    ${_recurloop_llvm_target_components})
llvm_map_components_to_libnames(RECURLOOP_LLVM_LIBRARIES ${_recurloop_llvm_components})

message(STATUS
    "RecurLoop toolchain: policy=${_recurloop_toolchain_mode}, LLVM=${_recurloop_llvm_source} ${LLVM_PACKAGE_VERSION}, zlib=${_recurloop_zlib_source}, zstd=${_recurloop_zstd_source}")
message(STATUS "RecurLoop LLVM backend: ${LLVM_DIR}")
message(STATUS "RecurLoop LLVM clang: '${RECURLOOP_LLVM_CLANG}'")
message(STATUS "RecurLoop LLVM ld.lld: '${RECURLOOP_LLVM_LLD}'")
message(STATUS "RecurLoop LLVM target triple: '${RECURLOOP_LLVM_TARGET_TRIPLE}'")
message(STATUS
    "RecurLoop LLVM linked targets: '${_recurloop_llvm_link_targets}' (native architecture: '${LLVM_NATIVE_ARCH}')")
