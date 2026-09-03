get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
set(EXAMPLE "${REPOSITORY_ROOT}/examples/03-phrases-and-syntax/friendly-context-api/main.rl")

execute_process(
    COMMAND "${PROGRAM}" --file "${EXAMPLE}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

if (NOT rc EQUAL 0 OR NOT out STREQUAL "" OR NOT err STREQUAL "")
    message(FATAL_ERROR
        "Friendly Context API example failed: status=${rc}, stdout='${out}', stderr='${err}'")
endif()
