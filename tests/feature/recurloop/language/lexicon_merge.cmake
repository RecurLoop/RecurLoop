execute_process(
    COMMAND "${PROGRAM}" --file "${CMAKE_CURRENT_LIST_DIR}/_lexicon_merge.rl"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

if (NOT rc EQUAL 0)
    message(FATAL_ERROR "Lexicon merge failed with status ${rc}:\n${err}\n${out}")
endif()
if (NOT err STREQUAL "")
    message(FATAL_ERROR "Lexicon merge wrote unexpected stderr:\n${err}")
endif()
if (NOT out STREQUAL "pong\npong\npong\npong\n")
    message(FATAL_ERROR "Unexpected lexicon merge output:\n${out}")
endif()
