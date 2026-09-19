set(IMAGE "/tmp/recurloop-lexicon-fragment-test.rli")
file(REMOVE "${IMAGE}")

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
if (NOT out STREQUAL "pong\npong\npong\npong\npong\npong\n")
    message(FATAL_ERROR "Unexpected lexicon merge output:\n${out}")
endif()
if (NOT EXISTS "${IMAGE}")
    message(FATAL_ERROR "Lexicon export did not create ${IMAGE}")
endif()

execute_process(
    COMMAND "${PROGRAM}" --file "${CMAKE_CURRENT_LIST_DIR}/_lexicon_fragment_consumer.rl"
    RESULT_VARIABLE consumer_rc
    OUTPUT_VARIABLE consumer_out
    ERROR_VARIABLE consumer_err
)
if (NOT consumer_rc EQUAL 0)
    message(FATAL_ERROR "Lexicon fragment consumer failed with status ${consumer_rc}:\n${consumer_err}\n${consumer_out}")
endif()
if (NOT consumer_err STREQUAL "")
    message(FATAL_ERROR "Lexicon fragment consumer wrote unexpected stderr:\n${consumer_err}")
endif()
if (NOT consumer_out STREQUAL "pong\npong\n")
    message(FATAL_ERROR "Unexpected lexicon fragment consumer output:\n${consumer_out}")
endif()
file(REMOVE "${IMAGE}")
