get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
set(CORE "${REPOSITORY_ROOT}/libraries/recurloop/core.rl")
set(TEST_SOURCE "${REPOSITORY_ROOT}/libraries/recurloop/tests/functions-control.rl")
set(EXPECTED_FILE "${REPOSITORY_ROOT}/libraries/recurloop/tests/functions-control.expected")
set(IMAGE "/tmp/recurloop-core.rli")

file(REMOVE "${IMAGE}")
execute_process(
    COMMAND "${PROGRAM}" --bootstrap --file "${CORE}"
    WORKING_DIRECTORY "${REPOSITORY_ROOT}"
    RESULT_VARIABLE build_rc
    OUTPUT_VARIABLE build_out
    ERROR_VARIABLE build_err)
if (NOT build_rc EQUAL 0)
    message(FATAL_ERROR "minimal bootstrap core build failed (${build_rc})\nstdout:\n${build_out}\nstderr:\n${build_err}")
endif()
if (NOT EXISTS "${IMAGE}")
    message(FATAL_ERROR "minimal bootstrap did not create ${IMAGE}")
endif()

execute_process(
    COMMAND "${PROGRAM}" --language-image "${IMAGE}" --file "${TEST_SOURCE}"
    WORKING_DIRECTORY "${REPOSITORY_ROOT}"
    RESULT_VARIABLE run_rc
    OUTPUT_VARIABLE actual
    ERROR_VARIABLE run_err)
if (NOT run_rc EQUAL 0)
    message(FATAL_ERROR "source-defined core execution failed (${run_rc})\nstdout:\n${actual}\nstderr:\n${run_err}")
endif()
file(READ "${EXPECTED_FILE}" expected)
if (NOT actual STREQUAL expected)
    message(FATAL_ERROR "source-defined core output mismatch\nexpected:\n${expected}\nactual:\n${actual}")
endif()

# The language image path must not install the legacy language.  A phrase that
# exists only in compatibility startup must still be unavailable after restore.
execute_process(
    COMMAND "${PROGRAM}" --language-image "${IMAGE}" --string "print 1"
    WORKING_DIRECTORY "${REPOSITORY_ROOT}"
    RESULT_VARIABLE legacy_rc
    OUTPUT_QUIET
    ERROR_VARIABLE legacy_err)
if (legacy_rc EQUAL 0)
    message(FATAL_ERROR "language-image startup unexpectedly installed legacy 'print'")
endif()
if (NOT legacy_err MATCHES "unknown source form|undefined phrase")
    message(FATAL_ERROR "language-image rejected legacy 'print' for an unexpected reason: ${legacy_err}")
endif()

# Keep the bootstrap surface intentionally small: these ordinary-language
# top-level forms must come from libraries/default compatibility mode, not from
# the bootstrap host.
foreach(forbidden IN ITEMS "print 1" "record X { value:i64 }" "if true { }")
    execute_process(
        COMMAND "${PROGRAM}" --bootstrap --string "${forbidden}"
        WORKING_DIRECTORY "${REPOSITORY_ROOT}"
        RESULT_VARIABLE forbidden_rc
        OUTPUT_QUIET
        ERROR_VARIABLE forbidden_err)
    if (forbidden_rc EQUAL 0)
        message(FATAL_ERROR "bootstrap unexpectedly accepted top-level source: ${forbidden}")
    endif()
    if (NOT forbidden_err MATCHES "undefined phrase")
        message(FATAL_ERROR "bootstrap rejected '${forbidden}' for an unexpected reason: ${forbidden_err}")
    endif()
endforeach()
