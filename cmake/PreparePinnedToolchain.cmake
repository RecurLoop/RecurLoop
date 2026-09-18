cmake_minimum_required(VERSION 3.25)

if(NOT DEFINED RECURLOOP_ROOT OR RECURLOOP_ROOT STREQUAL "")
    get_filename_component(RECURLOOP_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()
if(NOT DEFINED RECURLOOP_DEPS_DIR OR RECURLOOP_DEPS_DIR STREQUAL "")
    set(RECURLOOP_DEPS_DIR "${RECURLOOP_ROOT}/.cache/deps")
endif()

set(helper_build "${RECURLOOP_DEPS_DIR}/pinned-toolchain")
set(configure_command
    "${CMAKE_COMMAND}"
    -S "${RECURLOOP_ROOT}/cmake/pinned-toolchain"
    -B "${helper_build}"
    -G Ninja
    "-DRECURLOOP_ROOT=${RECURLOOP_ROOT}"
    "-DRECURLOOP_DEPS_DIR=${RECURLOOP_DEPS_DIR}"
    -DCMAKE_BUILD_TYPE=Release)

if(DEFINED RECURLOOP_C_COMPILER AND NOT RECURLOOP_C_COMPILER STREQUAL "")
    list(APPEND configure_command "-DCMAKE_C_COMPILER=${RECURLOOP_C_COMPILER}")
endif()
if(DEFINED RECURLOOP_CXX_COMPILER AND NOT RECURLOOP_CXX_COMPILER STREQUAL "")
    list(APPEND configure_command "-DCMAKE_CXX_COMPILER=${RECURLOOP_CXX_COMPILER}")
endif()

message(STATUS "Preparing pinned RecurLoop toolchain cache")
execute_process(
    COMMAND ${configure_command}
    RESULT_VARIABLE configure_result)
if(NOT configure_result EQUAL 0)
    message(FATAL_ERROR "Pinned toolchain configure failed with status ${configure_result}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}" --build "${helper_build}" --target RecurLoopPinnedToolchain --parallel
    RESULT_VARIABLE build_result)
if(NOT build_result EQUAL 0)
    message(FATAL_ERROR "Pinned toolchain build failed with status ${build_result}")
endif()

message(STATUS "Pinned RecurLoop toolchain cache is ready")
