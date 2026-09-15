cmake_minimum_required(VERSION 3.28)
project(RecurLoop VERSION 0.1.0 DESCRIPTION "An extensible programming language and runtime for source-defined language extensions"
        LANGUAGES C CXX)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

option(ENABLE_TESTS "Build the test suite" OFF)
option(USE_SCCACHE "Use sccache when available" ON)
option(RECURLOOP_ENABLE_LLVM "Use LLVM for optimized runtime code and native output" OFF)

if(DEFINED FETCHCONTENT_BASE_DIR)
    set(FETCHCONTENT_BASE_DIR "${FETCHCONTENT_BASE_DIR}" CACHE PATH
        "Shared FetchContent population directory" FORCE)
else()
    set(FETCHCONTENT_BASE_DIR "${CMAKE_BINARY_DIR}/dependencies" CACHE PATH
        "Per-configuration FetchContent working directory")
endif()

set(RECURLOOP_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include")
set(RECURLOOP_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/source")

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
set_target_properties(RecurloopLib PROPERTIES FOLDER "Libraries")

# Stage-0 seed code is deliberately isolated from the production runtime.
# It contains only enough grammar to enter `engine define { ... }`; the seed is
# not the standard language and is never embedded in the final executable.
add_library(RecurloopSeedLib STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/bootstrap/source/SeedLanguage.cpp")
target_include_directories(RecurloopSeedLib PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/bootstrap/include"
    "${RECURLOOP_INCLUDE_DIR}"
    "${RECURLOOP_SOURCE_DIR}")
target_link_libraries(RecurloopSeedLib PRIVATE RecurloopLib)
set_target_properties(RecurloopSeedLib PROPERTIES FOLDER "Bootstrap")

add_executable(RecurloopSeedBuilder "${CMAKE_CURRENT_SOURCE_DIR}/bootstrap/source/main.cpp")
target_include_directories(RecurloopSeedBuilder PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/bootstrap/include"
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
# Public tests and tooling always point at the self-hosted source-built image.
set(RECURLOOP_CORE_IMAGE "${RECURLOOP_SOURCE_IMAGE}")
set(RECURLOOP_CORE_FIXED_POINT "${RECURLOOP_CORE_ROOT}/fixed-point.stamp")
set(RECURLOOP_EMBEDDED_CORE_CPP "${CMAKE_CURRENT_BINARY_DIR}/generated/recurloop/EmbeddedCore.cpp")
set(RECURLOOP_CORE_VALIDATE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ValidateCoreSource.cmake")
set(RECURLOOP_SEED_VALIDATE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ValidateSeedImage.cmake")
set(RECURLOOP_SCHEMA_OWNERSHIP_VALIDATE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ValidateCompilerSchemaOwnership.cmake")
file(MAKE_DIRECTORY "${RECURLOOP_SEED_DIR}" "${RECURLOOP_SOURCE_DIR_1}" "${RECURLOOP_SOURCE_DIR_2}")

file(GLOB RECURLOOP_CORE_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core/*.rl")
list(APPEND RECURLOOP_CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core.rl")

add_custom_command(
    OUTPUT "${RECURLOOP_SEED_IMAGE}"
    COMMAND "${CMAKE_COMMAND}" -E rm -f "${RECURLOOP_SEED_IMAGE}"
    COMMAND "$<TARGET_FILE:RecurloopSeedBuilder>" "${RECURLOOP_SEED_IMAGE}"
    DEPENDS RecurloopSeedBuilder
    COMMENT "Building minimal seed.rli from isolated C++ stage-0 seed"
    VERBATIM)

add_custom_command(
    OUTPUT "${RECURLOOP_SOURCE_IMAGE}"
    COMMAND "${CMAKE_COMMAND}" -E rm -f "${RECURLOOP_SOURCE_IMAGE}"
    COMMAND "$<TARGET_FILE:RecurloopCoreRunner>"
            "${RECURLOOP_SEED_IMAGE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core.rl"
    WORKING_DIRECTORY "${RECURLOOP_SOURCE_DIR_1}"
    DEPENDS RecurloopCoreRunner "${RECURLOOP_SEED_IMAGE}" ${RECURLOOP_CORE_SOURCES}
    COMMENT "Building core.rli from minimal seed + semantic core.rl"
    VERBATIM)

add_custom_command(
    OUTPUT "${RECURLOOP_SOURCE_IMAGE_2}"
    COMMAND "${CMAKE_COMMAND}" -E rm -f "${RECURLOOP_SOURCE_IMAGE_2}"
    COMMAND "$<TARGET_FILE:RecurloopCoreRunner>"
            "${RECURLOOP_SOURCE_IMAGE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/libraries/recurloop/core.rl"
    WORKING_DIRECTORY "${RECURLOOP_SOURCE_DIR_2}"
    DEPENDS RecurloopCoreRunner "${RECURLOOP_SOURCE_IMAGE}" ${RECURLOOP_CORE_SOURCES}
    COMMENT "Building second self-hosted core.rli fixed point"
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
    COMMAND "${CMAKE_COMMAND}" -E compare_files "${RECURLOOP_SOURCE_IMAGE}" "${RECURLOOP_SOURCE_IMAGE_2}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${RECURLOOP_CORE_FIXED_POINT}"
    DEPENDS "${RECURLOOP_SEED_IMAGE}" "${RECURLOOP_SOURCE_IMAGE}" "${RECURLOOP_SOURCE_IMAGE_2}"
            "${RECURLOOP_CORE_VALIDATE_SCRIPT}" "${RECURLOOP_SEED_VALIDATE_SCRIPT}"
            "${RECURLOOP_SCHEMA_OWNERSHIP_VALIDATE_SCRIPT}"
            "${CMAKE_CURRENT_SOURCE_DIR}/source/compiler/LanguageState.cpp"
            "${CMAKE_CURRENT_SOURCE_DIR}/source/compiler/TypeSystem.cpp"
            ${RECURLOOP_CORE_SOURCES}
    COMMENT "Checking seed separation and byte-for-byte core/core self-hosting fixed point"
    VERBATIM)

add_custom_command(
    OUTPUT "${RECURLOOP_EMBEDDED_CORE_CPP}"
    COMMAND "${CMAKE_COMMAND}"
            "-DINPUT=${RECURLOOP_SOURCE_IMAGE}"
            "-DOUTPUT=${RECURLOOP_EMBEDDED_CORE_CPP}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/EmbedCoreImage.cmake"
    DEPENDS "${RECURLOOP_CORE_FIXED_POINT}" "${RECURLOOP_SOURCE_IMAGE}" "${CMAKE_CURRENT_SOURCE_DIR}/cmake/EmbedCoreImage.cmake"
    COMMENT "Embedding self-hosted core.rli"
    VERBATIM)

add_custom_target(RecurloopCoreImage DEPENDS "${RECURLOOP_CORE_FIXED_POINT}" "${RECURLOOP_SOURCE_IMAGE}")

# Normal-runtime convenience API (Recurloop::initialize) is deliberately kept
# out of RecurloopLib.  This layer is created only after the source-built core
# exists, so bootstrap/core-runner tools remain independent of embedded core.
add_library(RecurloopRuntimeLib STATIC
    "${RECURLOOP_SOURCE_DIR}/runtime/RecurloopRuntime.cpp"
    "${RECURLOOP_EMBEDDED_CORE_CPP}")
target_include_directories(RecurloopRuntimeLib PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
target_link_libraries(RecurloopRuntimeLib PUBLIC RecurloopLib)
add_dependencies(RecurloopRuntimeLib RecurloopCoreImage)
set_target_properties(RecurloopRuntimeLib PROPERTIES FOLDER "Libraries")

add_executable(Recurloop "${RECURLOOP_SOURCE_DIR}/main.cpp")
target_include_directories(Recurloop PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
set_target_properties(Recurloop PROPERTIES OUTPUT_NAME recurloop FOLDER "Executables")
target_link_libraries(Recurloop PRIVATE RecurloopRuntimeLib)
install(TARGETS Recurloop RUNTIME DESTINATION bin)

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
    add_subdirectory(tests)
endif()
