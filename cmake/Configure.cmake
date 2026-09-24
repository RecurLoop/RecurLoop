cmake_minimum_required(VERSION 3.25)

get_filename_component(ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
if(NOT DEFINED PRESET OR PRESET STREQUAL "")
    set(PRESET release)
endif()

set(configure_command "${CMAKE_COMMAND}" --preset "${PRESET}")
if(DEFINED LLVM_PROVIDER AND NOT LLVM_PROVIDER STREQUAL "")
    list(APPEND configure_command "-DRECURLOOP_LLVM_PROVIDER=${LLVM_PROVIDER}")
endif()
if(DEFINED INSTALL_PREFIX AND NOT INSTALL_PREFIX STREQUAL "")
    list(APPEND configure_command "-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}")
else()
    # A previous packaging install may have configured build/Release with a
    # custom prefix. Normal Makefile builds should return to CMake's native
    # platform default instead of inheriting that cached packaging path.
    list(APPEND configure_command -U CMAKE_INSTALL_PREFIX)
endif()
# Keep configure output attached to the terminal. First-time ARCHIVE discovery
# may download LLVM, so buffering stdout here makes a healthy configure look
# like a hung build.
execute_process(
    COMMAND ${configure_command}
    WORKING_DIRECTORY "${ROOT}"
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "configure preset '${PRESET}' failed with status ${result}")
endif()
