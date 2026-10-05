get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)

# Debug executable emission includes precise maps from both production and
# built-in hosts; optimized release output is intentionally outside this test.
execute_process(
    COMMAND "${PROGRAM}" --file "${REPOSITORY_ROOT}/examples/07-workflows/source-debugger/debugger_executable.rl"
    INPUT_FILE "${CMAKE_CURRENT_LIST_DIR}/_debugger_executable_commands.txt"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

# Some containers deny native ptrace calls. Keep the feature test portable while
# still exercising emission and the complete backend wherever policy permits.
if (NOT rc EQUAL 0 AND err MATCHES "operating system denied ptrace")
    message(STATUS "native debugger test skipped: ptrace is unavailable")
    return()
endif()
if (NOT rc EQUAL 0 OR NOT err STREQUAL "")
    message(FATAL_ERROR "native debugger returned status ${rc}:\n${err}\n${out}")
endif()

foreach(fragment
    "[debug] breakpoint 1 function \"debugger_program\""
    "[debug] executable started pid"
    "debugger_executable.rl:17:1 phrase \"var\" function \"debugger_program\""
    "[debug] step"
    "debugger_executable.rl:12:1 phrase \"var\" function \"add_one\""
    "[debug] value:i64 = 40"
    "[debug] finish"
    "debugger_executable.rl:18:1 phrase \"assignment\" function \"debugger_program\""
    "[debug] answer:i64 = 41"
    "debugger_executable.rl:19:1 phrase \"return\" function \"debugger_program\""
    "[debug] int 42"
    "[debug] executable exited with status 42"
)
    string(FIND "${out}" "${fragment}" position)
    if (position EQUAL -1)
        message(FATAL_ERROR "native debugger output is missing '${fragment}':\n${out}")
    endif()
endforeach()
