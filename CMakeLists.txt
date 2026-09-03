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

add_executable(Recurloop "${RECURLOOP_SOURCE_DIR}/main.cpp")
target_include_directories(Recurloop PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
set_target_properties(Recurloop PROPERTIES OUTPUT_NAME recurloop)
set_target_properties(Recurloop PROPERTIES FOLDER "Executables")
install(TARGETS Recurloop RUNTIME DESTINATION bin)

target_link_libraries(RadixLib PRIVATE UtilitiesLib)
target_link_libraries(LexiconLib PRIVATE RadixLib)
target_link_libraries(ContextLib PRIVATE LexiconLib)
target_link_libraries(CompilerLib PRIVATE UtilitiesLib LexiconLib)
target_link_libraries(RecurloopLib PRIVATE ContextLib CompilerLib)
target_link_libraries(Recurloop PRIVATE RecurloopLib)

if(RECURLOOP_ENABLE_LLVM)
    target_compile_definitions(RecurloopLib PRIVATE
        RECURLOOP_ENABLE_LLVM=1
        RECURLOOP_LLVM_TARGET_TRIPLE="${RECURLOOP_LLVM_TARGET_TRIPLE}"
        RECURLOOP_LLVM_CPU="${RECURLOOP_LLVM_CPU}"
        RECURLOOP_LLVM_FEATURES="${RECURLOOP_LLVM_FEATURES}"
        RECURLOOP_LLVM_SYSROOT="${RECURLOOP_LLVM_SYSROOT}"
        RECURLOOP_LLVM_OPT_LEVEL=${RECURLOOP_LLVM_OPT_LEVEL}
        RECURLOOP_LLVM_CLANG="${RECURLOOP_LLVM_CLANG}"
        RECURLOOP_LLVM_LLD="${RECURLOOP_LLVM_LLD}")
    target_include_directories(RecurloopLib SYSTEM PRIVATE ${LLVM_INCLUDE_DIRS})
    target_link_libraries(RecurloopLib PRIVATE ${RECURLOOP_LLVM_LIBRARIES})
endif()

if(ENABLE_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
