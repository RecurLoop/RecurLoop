cmake_minimum_required(VERSION 3.25)
project(RecurLoop VERSION 0.1.0 DESCRIPTION "An extensible programming language and runtime for source-defined language extensions"
        LANGUAGES C CXX)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

include(GNUInstallDirs)
set(RECURLOOP_INSTALL_LIBRARY_DIR "${CMAKE_INSTALL_DATADIR}/recurloop/libraries" CACHE PATH
    "Install directory for compiled RecurLoop language libraries")

option(ENABLE_TESTS "Build the test suite" OFF)
option(USE_SCCACHE "Use sccache when available" ON)
option(RECURLOOP_ENABLE_LLVM "Use LLVM for optimized runtime code and native output" OFF)
option(RECURLOOP_USE_CORE_CACHE
    "Reuse and populate the shared source-matched core.rli cache" ON)
set(RECURLOOP_PREBUILT_CORE_IMAGE "" CACHE FILEPATH
    "Optional source-matched core.rli to embed without rebuilding bootstrap/core")

# Dependencies are pinned, so repeated configure passes do not need network
# update checks after their first population.
set(FETCHCONTENT_UPDATES_DISCONNECTED ON CACHE BOOL
    "Do not update already populated FetchContent dependencies" FORCE)

set(RECURLOOP_DEPS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.cache/deps" CACHE PATH
    "Shared RecurLoop dependency cache")
# FetchContent source/population state is deliberately shared by every preset.
# GoogleTest and Google Benchmark keep configuration-specific build artifacts.
# The pinned LLVM/zlib/zstd toolchain is prepared separately below .cache/deps
# and imported into RecurLoop, so those third-party builds never become part of
# the main RecurLoop Ninja graph.
set(FETCHCONTENT_BASE_DIR "${RECURLOOP_DEPS_DIR}" CACHE PATH
    "Shared FetchContent population directory" FORCE)
message(STATUS "RecurLoop dependency cache: ${RECURLOOP_DEPS_DIR}")

# If a source tree is already present, tell FetchContent to use it directly.
# This also lets the migration overlay move old per-preset downloads into the
# common cache without forcing a second network download just to recreate the
# FetchContent population stamps.
function(recurloop_reuse_dependency_source content_name)
    string(TOUPPER "${content_name}" _recurloop_content_upper)
    set(_recurloop_source_dir "${RECURLOOP_DEPS_DIR}/${content_name}-src")
    if(IS_DIRECTORY "${_recurloop_source_dir}")
        set("FETCHCONTENT_SOURCE_DIR_${_recurloop_content_upper}"
            "${_recurloop_source_dir}" PARENT_SCOPE)
    endif()
endfunction()

set(RECURLOOP_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include")
set(RECURLOOP_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/source")

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/CoreFingerprint.cmake")
recurloop_core_fingerprint(RECURLOOP_CORE_FINGERPRINT "${CMAKE_CURRENT_SOURCE_DIR}")

# Pick the runtime core source once per build tree.  A freshly built local
# core may be copied into .cache/core after linking Recurloop, but that must not
# make the next configure change this build tree from LOCAL to PREBUILT: doing
# so changes the input of EmbeddedCore.cpp and causes one unnecessary relink.
# A clean build tree can still reuse an already source-matched shared cache.
set(_recurloop_explicit_prebuilt FALSE)
if(RECURLOOP_PREBUILT_CORE_IMAGE)
    get_filename_component(_recurloop_requested_core "${RECURLOOP_PREBUILT_CORE_IMAGE}"
        ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    recurloop_core_image_matches("${_recurloop_requested_core}" "${RECURLOOP_CORE_FINGERPRINT}"
        _recurloop_requested_core_matches)
    if(_recurloop_requested_core_matches)
        set(_recurloop_explicit_prebuilt TRUE)
        set(RECURLOOP_PREBUILT_CORE_IMAGE "${_recurloop_requested_core}")
    else()
        message(STATUS "Ignoring stale or unverified prebuilt core image: ${_recurloop_requested_core}")
        set(RECURLOOP_PREBUILT_CORE_IMAGE "" CACHE FILEPATH
            "Optional source-matched core.rli to embed without rebuilding bootstrap/core" FORCE)
    endif()
endif()

if(_recurloop_explicit_prebuilt)
    set(RECURLOOP_CORE_SOURCE_MODE "PREBUILT" CACHE INTERNAL
        "Runtime core source selected for this build tree" FORCE)
    set(RECURLOOP_SELECTED_CORE_IMAGE "${RECURLOOP_PREBUILT_CORE_IMAGE}" CACHE INTERNAL
        "Automatically selected prebuilt runtime core image" FORCE)
elseif(DEFINED RECURLOOP_CORE_SOURCE_MODE)
    if(RECURLOOP_CORE_SOURCE_MODE STREQUAL "PREBUILT")
        if(RECURLOOP_USE_CORE_CACHE)
            recurloop_core_image_matches("${RECURLOOP_SELECTED_CORE_IMAGE}" "${RECURLOOP_CORE_FINGERPRINT}"
                _recurloop_selected_core_matches)
            if(_recurloop_selected_core_matches)
                set(RECURLOOP_PREBUILT_CORE_IMAGE "${RECURLOOP_SELECTED_CORE_IMAGE}")
            else()
                message(STATUS "Cached core selected by this build tree is stale; switching to local core")
                set(RECURLOOP_CORE_SOURCE_MODE "LOCAL" CACHE INTERNAL
                    "Runtime core source selected for this build tree" FORCE)
                set(RECURLOOP_SELECTED_CORE_IMAGE "" CACHE INTERNAL
                    "Automatically selected prebuilt runtime core image" FORCE)
                set(RECURLOOP_PREBUILT_CORE_IMAGE "")
            endif()
        else()
            set(RECURLOOP_CORE_SOURCE_MODE "LOCAL" CACHE INTERNAL
                "Runtime core source selected for this build tree" FORCE)
            set(RECURLOOP_SELECTED_CORE_IMAGE "" CACHE INTERNAL
                "Automatically selected prebuilt runtime core image" FORCE)
            set(RECURLOOP_PREBUILT_CORE_IMAGE "")
        endif()
    else()
        # LOCAL is sticky for the lifetime of this CMake build tree.  In
        # particular, do not discover the cache that this same tree populated
        # during its previous build.
        set(RECURLOOP_PREBUILT_CORE_IMAGE "")
    endif()
else()
    set(_recurloop_discovered_core "")
    if(RECURLOOP_USE_CORE_CACHE)
        foreach(_recurloop_core_candidate IN ITEMS artifacts .cache/core)
            set(_recurloop_core_image "${CMAKE_CURRENT_SOURCE_DIR}/${_recurloop_core_candidate}/core.rli")
            recurloop_core_image_matches("${_recurloop_core_image}" "${RECURLOOP_CORE_FINGERPRINT}"
                _recurloop_core_matches)
            if(_recurloop_core_matches)
                set(_recurloop_discovered_core "${_recurloop_core_image}")
                break()
            endif()
        endforeach()
    endif()

    if(_recurloop_discovered_core)
        set(RECURLOOP_CORE_SOURCE_MODE "PREBUILT" CACHE INTERNAL
            "Runtime core source selected for this build tree" FORCE)
        set(RECURLOOP_SELECTED_CORE_IMAGE "${_recurloop_discovered_core}" CACHE INTERNAL
            "Automatically selected prebuilt runtime core image" FORCE)
        set(RECURLOOP_PREBUILT_CORE_IMAGE "${_recurloop_discovered_core}")
    else()
        set(RECURLOOP_CORE_SOURCE_MODE "LOCAL" CACHE INTERNAL
            "Runtime core source selected for this build tree" FORCE)
        set(RECURLOOP_SELECTED_CORE_IMAGE "" CACHE INTERNAL
            "Automatically selected prebuilt runtime core image" FORCE)
        set(RECURLOOP_PREBUILT_CORE_IMAGE "")
    endif()
endif()

if(NOT DEFINED CMAKE_ARCHIVE_OUTPUT_DIRECTORY)
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
endif()
if(NOT DEFINED CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
endif()
if(NOT DEFINED CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()

if(USE_SCCACHE)
    find_program(SCCACHE_EXECUTABLE sccache)
    if(SCCACHE_EXECUTABLE)
        set(CMAKE_C_COMPILER_LAUNCHER "${SCCACHE_EXECUTABLE}")
        set(CMAKE_CXX_COMPILER_LAUNCHER "${SCCACHE_EXECUTABLE}")
        message(STATUS "Using sccache: ${SCCACHE_EXECUTABLE}")
    endif()
endif()

if(RECURLOOP_ENABLE_LLVM)
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/RecurLoopLLVM.cmake")
endif()

add_compile_definitions(PROJECT_VERSION="${PROJECT_VERSION}")

# Release-like host builds use glibc/compiler object-size checks where they can
# be proven. Native RecurLoop HTTP code additionally calls the corresponding
# __*_chk entry points directly for dynamically generated code paths.
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang" AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(
        "$<$<NOT:$<CONFIG:Debug>>:-U_FORTIFY_SOURCE>"
        "$<$<NOT:$<CONFIG:Debug>>:-D_FORTIFY_SOURCE=3>"
    )
endif()

function(recurloop_add_library target directory)
    file(GLOB_RECURSE sources CONFIGURE_DEPENDS "${RECURLOOP_SOURCE_DIR}/${directory}/*.cpp")
    add_library(${target} STATIC ${sources})
    target_include_directories(${target} PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
    set_target_properties(${target} PROPERTIES FOLDER "Libraries")
endfunction()

recurloop_add_library(UtilitiesLib utilities)
recurloop_add_library(RadixLib radix)
recurloop_add_library(LexiconLib lexicon)
recurloop_add_library(ContextLib context)
recurloop_add_library(CompilerLib compiler)

file(GLOB_RECURSE recurloop_sources CONFIGURE_DEPENDS "${RECURLOOP_SOURCE_DIR}/recurloop/*.cpp")
list(FILTER recurloop_sources EXCLUDE REGEX ".*/LlvmBackend\\.cpp$")
if(RECURLOOP_ENABLE_LLVM)
    list(APPEND recurloop_sources "${RECURLOOP_SOURCE_DIR}/recurloop/LlvmBackend.cpp")
endif()
add_library(RecurloopLib STATIC ${recurloop_sources})
target_include_directories(RecurloopLib PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
if(IS_ABSOLUTE "${RECURLOOP_INSTALL_LIBRARY_DIR}")
    set(RECURLOOP_DEFAULT_LIBRARY_DIR "${RECURLOOP_INSTALL_LIBRARY_DIR}")
else()
    set(RECURLOOP_DEFAULT_LIBRARY_DIR "${CMAKE_INSTALL_PREFIX}/${RECURLOOP_INSTALL_LIBRARY_DIR}")
endif()
file(TO_CMAKE_PATH "${RECURLOOP_DEFAULT_LIBRARY_DIR}" RECURLOOP_DEFAULT_LIBRARY_DIR)
target_compile_definitions(RecurloopLib PRIVATE
    RECURLOOP_DEFAULT_LIBRARY_DIR="${RECURLOOP_DEFAULT_LIBRARY_DIR}")
set_target_properties(RecurloopLib PROPERTIES FOLDER "Libraries")

# Stage-0 seed code is deliberately isolated from the production runtime.
# It contains only enough grammar to enter `engine define { ... }`; the seed is
# not the standard language and is never embedded in the final executable.
add_library(RecurloopSeedLib STATIC
    "${RECURLOOP_SOURCE_DIR}/bootstrap/SeedLanguage.cpp")
target_include_directories(RecurloopSeedLib PRIVATE
    "${RECURLOOP_INCLUDE_DIR}"
    "${RECURLOOP_SOURCE_DIR}")
target_link_libraries(RecurloopSeedLib PRIVATE RecurloopLib)
set_target_properties(RecurloopSeedLib PROPERTIES FOLDER "Bootstrap")

add_executable(RecurloopSeedBuilder "${RECURLOOP_SOURCE_DIR}/bootstrap/main.cpp")
target_include_directories(RecurloopSeedBuilder PRIVATE
    "${RECURLOOP_INCLUDE_DIR}"
    "${RECURLOOP_SOURCE_DIR}")
target_link_libraries(RecurloopSeedBuilder PRIVATE RecurloopSeedLib RecurloopLib)
set_target_properties(RecurloopSeedBuilder PROPERTIES
    OUTPUT_NAME recurloop-seed-builder
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/tools"
    FOLDER "Build tools")

# The source-core runner has no seed-library dependency. It starts from a
# supplied image and executes the checked-in source definition to produce the
# next image.
add_executable(RecurloopCoreRunner "${RECURLOOP_SOURCE_DIR}/core_runner_main.cpp")
target_include_directories(RecurloopCoreRunner PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
target_link_libraries(RecurloopCoreRunner PRIVATE RecurloopLib)
set_target_properties(RecurloopCoreRunner PROPERTIES
    OUTPUT_NAME recurloop-core-runner
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/tools"
    FOLDER "Build tools")

set(RECURLOOP_CORE_ROOT "${CMAKE_CURRENT_BINARY_DIR}/generated/core")
set(RECURLOOP_SEED_DIR "${RECURLOOP_CORE_ROOT}/seed")
set(RECURLOOP_SOURCE_DIR_1 "${RECURLOOP_CORE_ROOT}/source-1")
set(RECURLOOP_SOURCE_DIR_2 "${RECURLOOP_CORE_ROOT}/source-2")
set(RECURLOOP_SEED_IMAGE "${RECURLOOP_SEED_DIR}/seed.rli")
set(RECURLOOP_SOURCE_IMAGE "${RECURLOOP_SOURCE_DIR_1}/core.rli")
set(RECURLOOP_SOURCE_IMAGE_2 "${RECURLOOP_SOURCE_DIR_2}/core.rli")
# The canonical verification image is always source-built. Runtime builds may
# optionally consume a source-matched prebuilt image (for example from a review
# bundle) without weakening the explicit fixed-point verification target.
set(RECURLOOP_CORE_IMAGE "${RECURLOOP_SOURCE_IMAGE}")
set(RECURLOOP_CORE_FIXED_POINT "${RECURLOOP_CORE_ROOT}/fixed-point.stamp")
set(RECURLOOP_EMBEDDED_CORE_CPP "${CMAKE_CURRENT_BINARY_DIR}/generated/recurloop/EmbeddedCore.cpp")
set(RECURLOOP_CORE_VALIDATE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ValidateCoreSource.cmake")
set(RECURLOOP_SEED_VALIDATE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ValidateSeedImage.cmake")
set(RECURLOOP_SCHEMA_OWNERSHIP_VALIDATE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ValidateCompilerSchemaOwnership.cmake")
set(RECURLOOP_SOURCE_ACTIONS_VALIDATE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ValidateSourceActions.cmake")
set(RECURLOOP_FINAL_HOST_VALIDATE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ValidateFinalHostBoundary.cmake")
file(MAKE_DIRECTORY "${RECURLOOP_SEED_DIR}" "${RECURLOOP_SOURCE_DIR_1}" "${RECURLOOP_SOURCE_DIR_2}")

file(GLOB RECURLOOP_CORE_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core/*.rl")
list(APPEND RECURLOOP_CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core.rl")

add_custom_command(
    OUTPUT "${RECURLOOP_SEED_IMAGE}"
    COMMAND "${CMAKE_COMMAND}" -E rm -f "${RECURLOOP_SEED_IMAGE}"
    COMMAND "$<TARGET_FILE:RecurloopSeedBuilder>" "${RECURLOOP_SEED_IMAGE}"
    DEPENDS RecurloopSeedBuilder
    COMMENT "[core] build stage-0 seed.rli"
    VERBATIM)

add_custom_command(
    OUTPUT "${RECURLOOP_SOURCE_IMAGE}"
    COMMAND "${CMAKE_COMMAND}" -E rm -f "${RECURLOOP_SOURCE_IMAGE}"
    COMMAND "$<TARGET_FILE:RecurloopCoreRunner>"
            "${RECURLOOP_SEED_IMAGE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core.rl"
    WORKING_DIRECTORY "${RECURLOOP_SOURCE_DIR_1}"
    DEPENDS RecurloopCoreRunner "${RECURLOOP_SEED_IMAGE}" ${RECURLOOP_CORE_SOURCES}
    COMMENT "[core] build core.rli from seed + semantic core.rl"
    VERBATIM)

add_custom_command(
    OUTPUT "${RECURLOOP_SOURCE_IMAGE_2}"
    COMMAND "${CMAKE_COMMAND}" -E rm -f "${RECURLOOP_SOURCE_IMAGE_2}"
    COMMAND "$<TARGET_FILE:RecurloopCoreRunner>"
            "${RECURLOOP_SOURCE_IMAGE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core.rl"
    WORKING_DIRECTORY "${RECURLOOP_SOURCE_DIR_2}"
    DEPENDS RecurloopCoreRunner "${RECURLOOP_SOURCE_IMAGE}" ${RECURLOOP_CORE_SOURCES}
    COMMENT "[verify] build second self-hosted core.rli"
    VERBATIM)

add_custom_command(
    OUTPUT "${RECURLOOP_CORE_FIXED_POINT}"
    COMMAND "${CMAKE_COMMAND}"
            "-DROOT=${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop"
            -P "${RECURLOOP_CORE_VALIDATE_SCRIPT}"
    COMMAND "${CMAKE_COMMAND}"
            "-DROOT=${CMAKE_CURRENT_SOURCE_DIR}"
            -P "${RECURLOOP_SCHEMA_OWNERSHIP_VALIDATE_SCRIPT}"
    COMMAND "${CMAKE_COMMAND}"
            "-DSEED=${RECURLOOP_SEED_IMAGE}"
            "-DCORE=${RECURLOOP_SOURCE_IMAGE}"
            -P "${RECURLOOP_SEED_VALIDATE_SCRIPT}"
    COMMAND "${CMAKE_COMMAND}"
            "-DRUNNER=$<TARGET_FILE:RecurloopCoreRunner>"
            "-DCORE=${RECURLOOP_SOURCE_IMAGE}"
            "-DALLOWLIST=${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core/host-actions.allow"
            -P "${RECURLOOP_SOURCE_ACTIONS_VALIDATE_SCRIPT}"
    COMMAND "${CMAKE_COMMAND}"
            "-DROOT=${CMAKE_CURRENT_SOURCE_DIR}"
            -P "${RECURLOOP_FINAL_HOST_VALIDATE_SCRIPT}"
    COMMAND "${CMAKE_COMMAND}" -E compare_files "${RECURLOOP_SOURCE_IMAGE}" "${RECURLOOP_SOURCE_IMAGE_2}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${RECURLOOP_CORE_FIXED_POINT}"
    DEPENDS "${RECURLOOP_SEED_IMAGE}" "${RECURLOOP_SOURCE_IMAGE}" "${RECURLOOP_SOURCE_IMAGE_2}"
            "${RECURLOOP_CORE_VALIDATE_SCRIPT}" "${RECURLOOP_SEED_VALIDATE_SCRIPT}"
            "${RECURLOOP_SCHEMA_OWNERSHIP_VALIDATE_SCRIPT}" "${RECURLOOP_SOURCE_ACTIONS_VALIDATE_SCRIPT}"
            "${RECURLOOP_FINAL_HOST_VALIDATE_SCRIPT}" "${CMAKE_CURRENT_SOURCE_DIR}/docs/host-abi.md"
            "${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core/host-actions.allow"
            "${CMAKE_CURRENT_SOURCE_DIR}/source/compiler/LanguageState.cpp"
            "${CMAKE_CURRENT_SOURCE_DIR}/source/compiler/TypeSystem.cpp"
            ${RECURLOOP_CORE_SOURCES}
    COMMENT "[verify] validate seed separation and core fixed point"
    VERBATIM)

# Normal development builds need one core image. The second self-hosting pass
# is a verification concern and is intentionally kept out of the executable's
# dependency chain. Review bundles may supply a source-matched prebuilt image,
# which also avoids building the seed/core tools when they are not being edited.
if(RECURLOOP_PREBUILT_CORE_IMAGE)
    get_filename_component(RECURLOOP_PREBUILT_CORE_IMAGE
        "${RECURLOOP_PREBUILT_CORE_IMAGE}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    if(NOT EXISTS "${RECURLOOP_PREBUILT_CORE_IMAGE}")
        message(FATAL_ERROR "Prebuilt core image not found: ${RECURLOOP_PREBUILT_CORE_IMAGE}")
    endif()
    set(RECURLOOP_RUNTIME_CORE_IMAGE "${RECURLOOP_PREBUILT_CORE_IMAGE}")
    set(RECURLOOP_CORE_IMAGE "${RECURLOOP_PREBUILT_CORE_IMAGE}")
    add_custom_target(RecurloopRuntimeCoreImage DEPENDS "${RECURLOOP_PREBUILT_CORE_IMAGE}")
    message(STATUS "Using source-matched prebuilt core image: ${RECURLOOP_PREBUILT_CORE_IMAGE}")
else()
    set(RECURLOOP_RUNTIME_CORE_IMAGE "${RECURLOOP_SOURCE_IMAGE}")
    add_custom_target(RecurloopRuntimeCoreImage DEPENDS "${RECURLOOP_SOURCE_IMAGE}")
    message(STATUS "Using local self-hosted core image for this build tree")
endif()

add_custom_command(
    OUTPUT "${RECURLOOP_EMBEDDED_CORE_CPP}"
    COMMAND "${CMAKE_COMMAND}"
            "-DINPUT=${RECURLOOP_RUNTIME_CORE_IMAGE}"
            "-DOUTPUT=${RECURLOOP_EMBEDDED_CORE_CPP}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/EmbedCoreImage.cmake"
    DEPENDS "${RECURLOOP_RUNTIME_CORE_IMAGE}" "${CMAKE_CURRENT_SOURCE_DIR}/cmake/EmbedCoreImage.cmake"
    COMMENT "[core] embed core.rli into recurloop"
    VERBATIM)

add_custom_target(RecurloopCoreImage DEPENDS "${RECURLOOP_SOURCE_IMAGE}")
add_custom_target(RecurloopCoreVerify DEPENDS "${RECURLOOP_CORE_FIXED_POINT}")
set_target_properties(RecurloopRuntimeCoreImage RecurloopCoreImage RecurloopCoreVerify
    PROPERTIES FOLDER "Verification")

# Normal-runtime convenience API (Recurloop::initialize) is deliberately kept
# out of RecurloopLib.  This layer is created only after the source-built core
# exists, so bootstrap/core-runner tools remain independent of embedded core.
add_library(RecurloopRuntimeLib STATIC
    "${RECURLOOP_SOURCE_DIR}/runtime/RecurloopRuntime.cpp"
    "${RECURLOOP_EMBEDDED_CORE_CPP}")
target_include_directories(RecurloopRuntimeLib PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
target_link_libraries(RecurloopRuntimeLib PUBLIC RecurloopLib)
add_dependencies(RecurloopRuntimeLib RecurloopRuntimeCoreImage)
set_target_properties(RecurloopRuntimeLib PROPERTIES FOLDER "Libraries")

add_executable(Recurloop "${RECURLOOP_SOURCE_DIR}/main.cpp")
target_include_directories(Recurloop PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
set_target_properties(Recurloop PROPERTIES OUTPUT_NAME recurloop FOLDER "Executables")
target_link_libraries(Recurloop PRIVATE RecurloopRuntimeLib)

# Source-defined standard libraries are normal build artifacts.  Each library
# receives its output path after `--`; no source file writes to a hard-coded
# /tmp location.  LanguageKit is the base image imported while building the
# dependent shell, inferred and HTTP images.
set(RECURLOOP_LIBRARY_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/libraries")
file(GLOB_RECURSE RECURLOOP_LIBRARY_BUILD_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/libraries/build/*.rl")
file(GLOB_RECURSE RECURLOOP_LANGUAGE_KIT_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/libraries/language-kit/*.rl")
set(RECURLOOP_LANGUAGE_KIT_IMAGE "${RECURLOOP_LIBRARY_OUTPUT_DIR}/language-kit.rli")
set(RECURLOOP_SHELL_IMAGE "${RECURLOOP_LIBRARY_OUTPUT_DIR}/shell.rli")
set(RECURLOOP_INFERRED_IMAGE "${RECURLOOP_LIBRARY_OUTPUT_DIR}/inferred.rli")
set(RECURLOOP_HTTP_IMAGE "${RECURLOOP_LIBRARY_OUTPUT_DIR}/http.rli")

add_custom_command(
    OUTPUT "${RECURLOOP_LANGUAGE_KIT_IMAGE}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${RECURLOOP_LIBRARY_OUTPUT_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E rm -f "${RECURLOOP_LANGUAGE_KIT_IMAGE}"
    COMMAND "$<TARGET_FILE:Recurloop>"
            --file "${CMAKE_CURRENT_SOURCE_DIR}/libraries/language-kit/library.rl"
            -- "${RECURLOOP_LANGUAGE_KIT_IMAGE}"
    DEPENDS Recurloop ${RECURLOOP_LANGUAGE_KIT_SOURCES} ${RECURLOOP_LIBRARY_BUILD_SOURCES}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "[libraries] build language-kit.rli"
    VERBATIM)

function(recurloop_add_language_library name source output)
    get_filename_component(source_directory "${source}" DIRECTORY)
    file(GLOB_RECURSE library_sources CONFIGURE_DEPENDS "${source_directory}/*.rl")
    add_custom_command(
        OUTPUT "${output}"
        COMMAND "${CMAKE_COMMAND}" -E rm -f "${output}"
        COMMAND "$<TARGET_FILE:Recurloop>"
                --library-path "${RECURLOOP_LIBRARY_OUTPUT_DIR}"
                --library language-kit
                --file "${source}"
                -- "${output}"
        DEPENDS Recurloop "${RECURLOOP_LANGUAGE_KIT_IMAGE}"
                ${library_sources} ${RECURLOOP_LIBRARY_BUILD_SOURCES}
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        COMMENT "[libraries] build ${name}.rli"
        VERBATIM)
endfunction()

recurloop_add_language_library(shell
    "${CMAKE_CURRENT_SOURCE_DIR}/libraries/shell/library.rl"
    "${RECURLOOP_SHELL_IMAGE}")
recurloop_add_language_library(inferred
    "${CMAKE_CURRENT_SOURCE_DIR}/libraries/inferred/library.rl"
    "${RECURLOOP_INFERRED_IMAGE}")
recurloop_add_language_library(http
    "${CMAKE_CURRENT_SOURCE_DIR}/libraries/http/library.rl"
    "${RECURLOOP_HTTP_IMAGE}")

add_custom_target(RecurloopLibraries
    DEPENDS
        "${RECURLOOP_LANGUAGE_KIT_IMAGE}"
        "${RECURLOOP_SHELL_IMAGE}"
        "${RECURLOOP_INFERRED_IMAGE}"
        "${RECURLOOP_HTTP_IMAGE}")
set_target_properties(RecurloopLibraries PROPERTIES FOLDER "Libraries")

install(FILES
    "${RECURLOOP_LANGUAGE_KIT_IMAGE}"
    "${RECURLOOP_SHELL_IMAGE}"
    "${RECURLOOP_INFERRED_IMAGE}"
    "${RECURLOOP_HTTP_IMAGE}"
    DESTINATION "${RECURLOOP_INSTALL_LIBRARY_DIR}"
    COMPONENT Libraries)
install(FILES LICENSE README.md TRADEMARKS.md
    DESTINATION "${CMAKE_INSTALL_DOCDIR}"
    COMPONENT Documentation)
if(RECURLOOP_USE_CORE_CACHE)
    add_custom_command(TARGET Recurloop POST_BUILD
        COMMAND "${CMAKE_COMMAND}"
                "-DINPUT=${RECURLOOP_RUNTIME_CORE_IMAGE}"
                "-DFINGERPRINT=${RECURLOOP_CORE_FINGERPRINT}"
                "-DCACHE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.cache/core"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/CacheCore.cmake"
        VERBATIM)
endif()
install(TARGETS Recurloop RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}" COMPONENT Runtime)

target_link_libraries(RadixLib PRIVATE UtilitiesLib)
target_link_libraries(LexiconLib PRIVATE RadixLib)
target_link_libraries(ContextLib PRIVATE LexiconLib)
target_link_libraries(CompilerLib PRIVATE UtilitiesLib LexiconLib)
target_link_libraries(RecurloopLib PRIVATE ContextLib CompilerLib)

if(RECURLOOP_ENABLE_LLVM)
    target_compile_definitions(RecurloopLib PRIVATE
        RECURLOOP_ENABLE_LLVM=1
        RECURLOOP_LLVM_TARGET_TRIPLE="${RECURLOOP_LLVM_TARGET_TRIPLE}"
        RECURLOOP_LLVM_CPU="${RECURLOOP_LLVM_CPU}"
        RECURLOOP_LLVM_FEATURES="${RECURLOOP_LLVM_FEATURES}"
        RECURLOOP_LLVM_SYSROOT="${RECURLOOP_LLVM_SYSROOT}"
        RECURLOOP_LLVM_OPT_LEVEL=${RECURLOOP_LLVM_OPT_LEVEL}
        RECURLOOP_LLVM_INITIALIZE_ALL_TARGETS=${RECURLOOP_LLVM_INITIALIZE_ALL_TARGETS}
        RECURLOOP_LLVM_CLANG="${RECURLOOP_LLVM_CLANG}"
        RECURLOOP_LLVM_LLD="${RECURLOOP_LLVM_LLD}")
    target_include_directories(RecurloopLib SYSTEM PRIVATE ${LLVM_INCLUDE_DIRS})
    target_link_libraries(RecurloopLib PRIVATE ${RECURLOOP_LLVM_LIBRARIES})
endif()

if(ENABLE_TESTS)
    enable_testing()
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/IncrementalChecks.cmake")
    add_subdirectory(tests)
    recurloop_define_incremental_example_checks()
endif()
