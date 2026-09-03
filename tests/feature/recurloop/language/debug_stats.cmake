execute_process(
    COMMAND "${PROGRAM}" --file "${CMAKE_CURRENT_LIST_DIR}/../../../../examples/03-phrases-and-syntax/context-actions/main.rl"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

if (NOT rc EQUAL 0)
    message(FATAL_ERROR "debug:stats returned status ${rc}:\n${err}")
endif()

if (NOT err STREQUAL "")
    message(FATAL_ERROR "debug:stats wrote to stderr:\n${err}")
endif()

foreach (label IN ITEMS "Execution time:" "Elaborate time:" "Invoke time:")
    string(FIND "${out}" "${label}" position)
    if (position EQUAL -1)
        message(FATAL_ERROR "debug:stats output is missing '${label}':\n${out}")
    endif()
endforeach()
