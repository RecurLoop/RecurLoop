get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)

execute_process(
    COMMAND "${PROGRAM}" --file "${REPOSITORY_ROOT}/examples/07-workflows/source-debugger/debugger.rl"
    INPUT_FILE "${CMAKE_CURRENT_LIST_DIR}/_debugger_commands.txt"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

if (NOT rc EQUAL 0)
    message(FATAL_ERROR "debugger example returned status ${rc}:\n${err}\n${out}")
endif()
if (NOT err STREQUAL "")
    message(FATAL_ERROR "debugger example wrote to stderr:\n${err}")
endif()

foreach(fragment
    "[debug] trace on"
    "[debug] breakpoint 1 phrase \"print\""
    "[debug] breakpoint "
    "target.rl:2:1 phrase \"print\""
    "[debug] int 1"
    "[debug] deleted breakpoint 1"
    "[debug] stopped "
    "target.rl:3:1 phrase \"counter\""
    "[debug] int 1"
    "first stop, counter=1"
    "finished, counter=2"
    "[debug] finished"
)
    string(FIND "${out}" "${fragment}" position)
    if (position EQUAL -1)
        message(FATAL_ERROR "debugger output is missing '${fragment}':\n${out}")
    endif()
endforeach()

execute_process(
    COMMAND "${PROGRAM}"
            --string "debug:break line \"${REPOSITORY_ROOT}/examples/07-workflows/source-debugger/target.rl\":4\n"
            --string "debug:run \"${REPOSITORY_ROOT}/examples/07-workflows/source-debugger/target.rl\"\n"
    INPUT_FILE "${CMAKE_CURRENT_LIST_DIR}/_debugger_continue.txt"
    RESULT_VARIABLE line_rc
    OUTPUT_VARIABLE line_out
    ERROR_VARIABLE line_err
)
if (NOT line_rc EQUAL 0 OR NOT line_err STREQUAL "")
    message(FATAL_ERROR
        "line breakpoint failed: status=${line_rc}\n${line_err}\n${line_out}")
endif()
foreach(fragment
    "[debug] breakpoint 1 ${REPOSITORY_ROOT}/examples/07-workflows/source-debugger/target.rl:4"
    "target.rl:4:1 phrase \"print\""
    "finished, counter=2"
)
    string(FIND "${line_out}" "${fragment}" position)
    if (position EQUAL -1)
        message(FATAL_ERROR "line breakpoint output is missing '${fragment}':\n${line_out}")
    endif()
endforeach()
