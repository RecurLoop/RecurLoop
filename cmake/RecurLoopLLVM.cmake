include("${CMAKE_CURRENT_LIST_DIR}/LLVMDistribution.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/LLVMArchive.cmake")

set(RECURLOOP_LLVM_PROVIDER "AUTO" CACHE STRING
    "LLVM provider: AUTO, SYSTEM, or ARCHIVE")
set_property(CACHE RECURLOOP_LLVM_PROVIDER PROPERTY STRINGS AUTO SYSTEM ARCHIVE)
string(TOUPPER "${RECURLOOP_LLVM_PROVIDER}" _recurloop_llvm_provider)
if(NOT _recurloop_llvm_provider MATCHES "^(AUTO|SYSTEM|ARCHIVE)$")
    message(FATAL_ERROR
        "RECURLOOP_LLVM_PROVIDER must be AUTO, SYSTEM, or ARCHIVE (got '${RECURLOOP_LLVM_PROVIDER}')")
endif()

set(RECURLOOP_SYSTEM_LLVM_CONFIG "" CACHE FILEPATH
    "Optional llvm-config executable used by SYSTEM/AUTO discovery")
set(RECURLOOP_LLVM_TARGET_TRIPLE "" CACHE STRING "LLVM output target triple (empty means the LLVM host target)")
set(RECURLOOP_LLVM_CPU "generic" CACHE STRING "LLVM output CPU")
set(RECURLOOP_LLVM_FEATURES "" CACHE STRING "Comma-separated LLVM target features")
set(RECURLOOP_LLVM_SYSROOT "" CACHE PATH "Optional target sysroot passed to clang when linking executables")
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

function(recurloop_llvm_query llvm_config out_value)
    execute_process(
        COMMAND "${llvm_config}" ${ARGN}
        OUTPUT_VARIABLE value OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE error RESULT_VARIABLE result TIMEOUT 30)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "${llvm_config} ${ARGN} failed:\n${error}")
    endif()
    set(${out_value} "${value}" PARENT_SCOPE)
endfunction()

function(recurloop_probe_system_llvm out_config out_found)
    if(RECURLOOP_SYSTEM_LLVM_CONFIG)
        set(llvm_config "${RECURLOOP_SYSTEM_LLVM_CONFIG}")
    else()
        find_program(llvm_config NAMES llvm-config-22 llvm-config NO_CACHE)
    endif()
    if(NOT llvm_config OR NOT EXISTS "${llvm_config}")
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()
    execute_process(COMMAND "${llvm_config}" --version
        OUTPUT_VARIABLE version OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE result ERROR_QUIET TIMEOUT 30)
    if(NOT result EQUAL 0 OR
       version VERSION_LESS RECURLOOP_SYSTEM_LLVM_MIN_VERSION OR
       NOT version VERSION_LESS RECURLOOP_SYSTEM_LLVM_MAX_VERSION)
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()
    set(${out_config} "${llvm_config}" PARENT_SCOPE)
    set(${out_found} TRUE PARENT_SCOPE)
endfunction()

set(_recurloop_llvm_selected_provider "")
set(_recurloop_llvm_config "")
set(_recurloop_archive_url "")
set(_recurloop_archive_sha "")

# AUTO deliberately avoids network access when possible:
#   1. exact pinned archive already present in the dependency cache,
#   2. compatible system LLVM 22.x,
#   3. download and cache the exact pinned archive.
# This makes repeated builds deterministic once the pinned SDK has been fetched,
# while keeping a fresh developer checkout fast when the distro already provides LLVM.
if(_recurloop_llvm_provider STREQUAL "AUTO")
    recurloop_find_cached_llvm_archive(_recurloop_cached_llvm_root _recurloop_cached_llvm_found)
    if(_recurloop_cached_llvm_found)
        set(_recurloop_llvm_root "${_recurloop_cached_llvm_root}")
        set(_recurloop_llvm_selected_provider "ARCHIVE")
        message(STATUS "RecurLoop LLVM AUTO: using cached pinned LLVM ${RECURLOOP_LLVM_VERSION}")
    else()
        recurloop_probe_system_llvm(_recurloop_system_llvm_config _recurloop_system_llvm_found)
        if(_recurloop_system_llvm_found)
            set(_recurloop_llvm_config "${_recurloop_system_llvm_config}")
            set(_recurloop_llvm_selected_provider "SYSTEM")
            message(STATUS "RecurLoop LLVM AUTO: pinned archive is not cached; using system LLVM 22.x")
        else()
            recurloop_prepare_llvm_archive(_recurloop_llvm_root)
            set(_recurloop_llvm_selected_provider "ARCHIVE")
            message(STATUS "RecurLoop LLVM AUTO: no compatible system LLVM; using downloaded pinned LLVM ${RECURLOOP_LLVM_VERSION}")
        endif()
    endif()
elseif(_recurloop_llvm_provider STREQUAL "SYSTEM")
    recurloop_probe_system_llvm(_recurloop_system_llvm_config _recurloop_system_llvm_found)
    if(NOT _recurloop_system_llvm_found)
        message(FATAL_ERROR
            "SYSTEM provider requires LLVM 22.x. Debian/Ubuntu: "
            "apt install llvm-22 llvm-22-dev clang-22 lld-22, or set RECURLOOP_SYSTEM_LLVM_CONFIG.")
    endif()
    set(_recurloop_llvm_config "${_recurloop_system_llvm_config}")
    set(_recurloop_llvm_selected_provider "SYSTEM")
else()
    recurloop_prepare_llvm_archive(_recurloop_llvm_root)
    set(_recurloop_llvm_selected_provider "ARCHIVE")
endif()

if(_recurloop_llvm_selected_provider STREQUAL "ARCHIVE")
    recurloop_llvm_archive_metadata(_recurloop_archive_url _recurloop_archive_sha
        _recurloop_archive_id _recurloop_archive_filename)
    if(WIN32)
        set(_recurloop_llvm_config "${_recurloop_llvm_root}/bin/llvm-config.exe")
    else()
        set(_recurloop_llvm_config "${_recurloop_llvm_root}/bin/llvm-config")
    endif()
endif()

recurloop_llvm_query("${_recurloop_llvm_config}" LLVM_PACKAGE_VERSION --version)
if(_recurloop_llvm_selected_provider STREQUAL "ARCHIVE")
    if(NOT LLVM_PACKAGE_VERSION STREQUAL RECURLOOP_LLVM_VERSION)
        message(FATAL_ERROR "Official LLVM archive reported ${LLVM_PACKAGE_VERSION}, expected ${RECURLOOP_LLVM_VERSION}")
    endif()
elseif(LLVM_PACKAGE_VERSION VERSION_LESS RECURLOOP_SYSTEM_LLVM_MIN_VERSION OR
       NOT LLVM_PACKAGE_VERSION VERSION_LESS RECURLOOP_SYSTEM_LLVM_MAX_VERSION)
    message(FATAL_ERROR "Selected system LLVM ${LLVM_PACKAGE_VERSION} is outside the supported 22.x range")
endif()

recurloop_llvm_query("${_recurloop_llvm_config}" RECURLOOP_LLVM_ROOT --prefix)
recurloop_llvm_query("${_recurloop_llvm_config}" _recurloop_llvm_includedir --includedir)
recurloop_llvm_query("${_recurloop_llvm_config}" _recurloop_llvm_host_target --host-target)
recurloop_llvm_query("${_recurloop_llvm_config}" RECURLOOP_LLVM_TARGETS_BUILT --targets-built)
recurloop_llvm_query("${_recurloop_llvm_config}" _recurloop_llvm_cppflags --cppflags)

if(RECURLOOP_LLVM_TARGET_TRIPLE STREQUAL "")
    set(RECURLOOP_LLVM_TARGET_TRIPLE "${_recurloop_llvm_host_target}" CACHE STRING
        "LLVM output target triple (empty means the LLVM host target)" FORCE)
endif()

if(_recurloop_llvm_link_targets STREQUAL "native")
    set(_recurloop_llvm_components core support target mc codegen passes nativecodegen)
    set(RECURLOOP_LLVM_INITIALIZE_ALL_TARGETS 0)
else()
    set(_recurloop_llvm_components all)
    set(RECURLOOP_LLVM_INITIALIZE_ALL_TARGETS 1)
endif()

# llvm-config from the selected distribution resolves the exact static component
# closure and its required host libraries. There is no local LLVM build graph.
recurloop_llvm_query("${_recurloop_llvm_config}" _recurloop_llvm_libfiles
    --link-static --libfiles ${_recurloop_llvm_components})
recurloop_llvm_query("${_recurloop_llvm_config}" _recurloop_llvm_system_libs
    --link-static --system-libs ${_recurloop_llvm_components})
if(_recurloop_llvm_libfiles STREQUAL "")
    message(FATAL_ERROR
        "LLVM ${LLVM_PACKAGE_VERSION} does not provide the static component libraries required by RecurLoop")
endif()
separate_arguments(RECURLOOP_LLVM_LIBRARIES NATIVE_COMMAND "${_recurloop_llvm_libfiles}")
if(NOT _recurloop_llvm_system_libs STREQUAL "")
    separate_arguments(_recurloop_llvm_system_libraries NATIVE_COMMAND "${_recurloop_llvm_system_libs}")
    if(_recurloop_llvm_selected_provider STREQUAL "ARCHIVE" AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
        # LLVM's object reader uses zlib even with only the native backend.
        # Embed it so clean runtime images need only their glibc installation.
        find_library(_recurloop_zlib_static NAMES libz.a REQUIRED)
        list(TRANSFORM _recurloop_llvm_system_libraries REPLACE "^-lz$" "${_recurloop_zlib_static}")
    endif()
    list(APPEND RECURLOOP_LLVM_LIBRARIES ${_recurloop_llvm_system_libraries})
endif()

set(RECURLOOP_LLVM_INCLUDE_DIRS "${_recurloop_llvm_includedir}")
separate_arguments(_recurloop_llvm_cppflags_list NATIVE_COMMAND "${_recurloop_llvm_cppflags}")
set(RECURLOOP_LLVM_COMPILE_OPTIONS "")
foreach(flag IN LISTS _recurloop_llvm_cppflags_list)
    if(flag MATCHES "^-I(.+)$")
        list(APPEND RECURLOOP_LLVM_INCLUDE_DIRS "${CMAKE_MATCH_1}")
    else()
        list(APPEND RECURLOOP_LLVM_COMPILE_OPTIONS "${flag}")
    endif()
endforeach()
list(REMOVE_DUPLICATES RECURLOOP_LLVM_INCLUDE_DIRS)

set(RECURLOOP_LLVM_SELECTED_PROVIDER "${_recurloop_llvm_selected_provider}" CACHE INTERNAL
    "Resolved RecurLoop LLVM provider" FORCE)
set(RECURLOOP_LLVM_SELECTED_VERSION "${LLVM_PACKAGE_VERSION}" CACHE INTERNAL
    "Resolved RecurLoop LLVM version" FORCE)
set(RECURLOOP_LLVM_SELECTED_ROOT "${RECURLOOP_LLVM_ROOT}" CACHE INTERNAL
    "Resolved RecurLoop LLVM root" FORCE)
set(RECURLOOP_LLVM_SELECTED_ARCHIVE_URL "${_recurloop_archive_url}" CACHE INTERNAL
    "Resolved official LLVM archive URL" FORCE)
set(RECURLOOP_LLVM_SELECTED_ARCHIVE_SHA256 "${_recurloop_archive_sha}" CACHE INTERNAL
    "Resolved official LLVM archive SHA256" FORCE)

message(STATUS
    "RecurLoop LLVM: provider=${RECURLOOP_LLVM_SELECTED_PROVIDER}, version=${LLVM_PACKAGE_VERSION}, link=${_recurloop_llvm_link_targets}")
message(STATUS "RecurLoop LLVM root: ${RECURLOOP_LLVM_ROOT}")
message(STATUS "RecurLoop LLVM targets available: ${RECURLOOP_LLVM_TARGETS_BUILT}")
message(STATUS "RecurLoop LLVM target triple: '${RECURLOOP_LLVM_TARGET_TRIPLE}'")
