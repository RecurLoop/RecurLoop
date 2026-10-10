cmake_minimum_required(VERSION 3.25)
if(NOT DEFINED PREFIX OR NOT EXISTS "${PREFIX}/bin/recurloop")
    message(FATAL_ERROR "PREFIX must identify an installed package")
endif()
get_filename_component(PREFIX "${PREFIX}" ABSOLUTE)
include("${CMAKE_CURRENT_LIST_DIR}/PackageIntegrity.cmake")
recurloop_require_package_layout("${PREFIX}")
recurloop_verify_package_manifest("${PREFIX}")

set(program "${PREFIX}/bin/recurloop")
set(work "${PREFIX}/.smoke")
file(REMOVE_RECURSE "${work}")
file(MAKE_DIRECTORY "${work}")
function(run)
    execute_process(COMMAND ${ARGV} WORKING_DIRECTORY "${work}"
        RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error TIMEOUT 120)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "Package smoke test failed (${result}): ${ARGV}\n${output}${error}")
    endif()
endfunction()

function(run_with_llvm_tools)
    if(NOT DEFINED LLVM_TOOL_DIR OR LLVM_TOOL_DIR STREQUAL "")
        message(FATAL_ERROR "LLVM_TOOL_DIR is required for native package-output verification")
    endif()
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env "PATH=${LLVM_TOOL_DIR}:$ENV{PATH}" ${ARGV}
        WORKING_DIRECTORY "${work}"
        RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error TIMEOUT 120)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "Package native-output test failed (${result}): ${ARGV}\n${output}${error}")
    endif()
endfunction()

run("${program}" --version)
run("${program}" --library shell --library inferred --string "assert 6 * 7 == 42")
run("${program}" --string "import window\nimport vulkan\nimport window\nassert 6 * 7 == 42")

# LLVM code generation is linked into RecurLoop. Native file output still uses
# host LLD (and Clang for executables); the release builder supplies those tools
# from the same pinned LLVM archive, while the installed package does not bundle them.
file(WRITE "${work}/native.rl" [=[
fn add(a:i64, b:i64) -> i64 { return a + b }
assert add(20, 22) == 42
emit object "answer.o" answer = fn () -> i64 { return 42 }
]=])
run_with_llvm_tools("${program}" --file "${work}/native.rl")
if(NOT EXISTS "${work}/answer.o")
    message(FATAL_ERROR "Installed compiler did not emit answer.o")
endif()

# Resolution is based on the actual executable and installed library paths, not
# argv[0] or the source/build tree.
set(alias "${work}/recurloop-via-symlink")
execute_process(COMMAND "${CMAKE_COMMAND}" -E create_symlink "${program}" "${alias}"
    COMMAND_ERROR_IS_FATAL ANY)
run("${alias}" --library shell --string "assert 21 + 21 == 42")

# An installed release must never fall back to an absolute Clang path from the
# build machine. With an empty PATH, executable emission must fail cleanly and
# explain how to install the optional host linker tools.
file(WRITE "${work}/executable.rl" [=[
emit executable "answer" main = fn () -> i64 { return 42 }
]=])
file(MAKE_DIRECTORY "${work}/empty-path")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "PATH=${work}/empty-path" "${program}" --file "${work}/executable.rl"
    WORKING_DIRECTORY "${work}"
    RESULT_VARIABLE missing_result OUTPUT_QUIET ERROR_VARIABLE missing_error TIMEOUT 120)
if(missing_result EQUAL 0 OR NOT missing_error MATCHES "Install Clang/LLD 22")
    message(FATAL_ERROR "Installed compiler did not diagnose missing host linker tools: ${missing_error}")
endif()

file(REMOVE_RECURSE "${work}")
recurloop_verify_package_manifest("${PREFIX}")
message(STATUS "Installed package passed layout, integrity, relocation, runtime, LLVM object output and missing-tool checks")
