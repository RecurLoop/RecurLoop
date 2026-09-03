execute_process(
    COMMAND "${PROGRAM}" --file "${CMAKE_CURRENT_LIST_DIR}/_everyday.rl"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

set(EXPECTED_OUT [=[
RECURLOOP:ok
012
]=])

if (NOT rc EQUAL 0)
    message(FATAL_ERROR "Unexpected status code ${rc}:\n${err}")
endif()

if (NOT err STREQUAL "")
    message(FATAL_ERROR "Unexpected stderr:\n${err}")
endif()

if (NOT out STREQUAL EXPECTED_OUT)
    message(FATAL_ERROR "Unexpected stdout:\n${out}")
endif()
