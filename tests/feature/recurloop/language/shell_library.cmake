get_filename_component(
    REPOSITORY_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../../../.."
    ABSOLUTE
)

set(
    SHELL_DIR
    "${REPOSITORY_ROOT}/examples/07-workflows/shell-language"
)

execute_process(
    COMMAND
        "${SHELL_DIR}/run-tests.sh"
        "${PROGRAM}"
    WORKING_DIRECTORY
        "${REPOSITORY_ROOT}"
    RESULT_VARIABLE test_rc
)

if (NOT test_rc EQUAL 0)
    message(FATAL_ERROR
        "Shell language tests failed: status=${test_rc}"
    )
endif()
