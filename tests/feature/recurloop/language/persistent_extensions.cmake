get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
set(EXAMPLE "${REPOSITORY_ROOT}/examples/03-phrases-and-syntax/persistent-extensions/main.rl")
set(IMAGE "/tmp/recurloop-persistent-extensions.rli")

file(REMOVE "${IMAGE}")
execute_process(
    COMMAND "${PROGRAM}" --file "${EXAMPLE}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

set(EXPECTED_OUT [=[matchLongest selected alphabet
compiled .rl syntax survived the engine image
]=])

if (NOT rc EQUAL 0)
    message(FATAL_ERROR "Self-sufficient extension example failed with status ${rc}:\n${err}\n${out}")
endif()
if (NOT err STREQUAL "")
    message(FATAL_ERROR "Self-sufficient extension example wrote unexpected stderr:\n${err}")
endif()
if (NOT out STREQUAL EXPECTED_OUT)
    message(FATAL_ERROR "Self-sufficient extension example wrote unexpected stdout:\n${out}")
endif()
if (NOT EXISTS "${IMAGE}")
    message(FATAL_ERROR "Self-sufficient extension example did not export ${IMAGE}")
endif()

execute_process(
    COMMAND "${PROGRAM}" --file "${EXAMPLE}" --string "repeat nope { debug:ping }"
    RESULT_VARIABLE error_rc
    OUTPUT_VARIABLE error_out
    ERROR_VARIABLE error_err
)
if (error_rc EQUAL 0 OR NOT error_err MATCHES
    "<input>:1:[0-9]+: repeat expects a non-negative decimal count before its block")
    message(FATAL_ERROR
        "Compiled .rl diagnostic did not preserve its source location: status=${error_rc}, stdout='${error_out}', stderr='${error_err}'")
endif()

file(REMOVE "${IMAGE}")
