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

foreach (label IN ITEMS "PROCESS SNAPSHOT" "CPU since start" "Resident / peak" "Virtual / swap"
        "Threads" "Lexicon arena" "Program JIT used" "Action JIT used"
        "Elaborate time:" "Invoke time:" "Storage read / write" "Read / write calls")
    string(FIND "${out}" "${label}" position)
    if (position EQUAL -1)
        message(FATAL_ERROR "debug:stats output is missing '${label}':\n${out}")
    endif()
endforeach()

string(ASCII 27 escape)
string(FIND "${out}" "${escape}[" ansi)
if (NOT ansi EQUAL -1)
    message(FATAL_ERROR "Redirected stats must not contain ANSI escapes")
endif()
if (NOT out MATCHES "Resident / peak +[0-9.]+ [KMGT]?i?B / [0-9.]+ [KMGT]?i?B")
    message(FATAL_ERROR "Expected measured resident and peak memory:\n${out}")
endif()

# A snapshot must not clear accumulated engine counters.
execute_process(
    COMMAND "${PROGRAM}" --string "debug:stats\ndebug:stats\n"
    RESULT_VARIABLE repeat_rc OUTPUT_VARIABLE repeated ERROR_VARIABLE repeat_err
)
if (NOT repeat_rc EQUAL 0 OR NOT repeat_err STREQUAL "")
    message(FATAL_ERROR "Repeated snapshots failed: ${repeat_err}")
endif()
if (NOT repeated MATCHES "CPU since start +([0-9.]+%|n/a)" OR
    NOT repeated MATCHES "CPU since last stats +[0-9.]+%" OR
    NOT repeated MATCHES "Sample interval +[0-9.]+ s")
    message(FATAL_ERROR "Expected lifetime CPU usage followed by interval CPU usage:\n${repeated}")
endif()
string(REGEX MATCHALL "Elaborate time: +[0-9.]+ s / [0-9]+ calls" counts "${repeated}")
list(LENGTH counts count)
if (NOT count EQUAL 2)
    message(FATAL_ERROR "Expected two snapshots:\n${repeated}")
endif()
list(GET counts 0 first)
list(GET counts 1 second)
string(REGEX REPLACE ".* / ([0-9]+) calls" "\\1" first "${first}")
string(REGEX REPLACE ".* / ([0-9]+) calls" "\\1" second "${second}")
if (second LESS first)
    message(FATAL_ERROR "Snapshot reset accumulated counters: ${first} -> ${second}")
endif()
