# CLI projects must enable the configured cache without polluting target output.
set(root "${CMAKE_CURRENT_BINARY_DIR}/cli-project-cache")
file(REMOVE_RECURSE "${root}")
file(MAKE_DIRECTORY "${root}/src")
file(WRITE "${root}/recurloop.project.rl" [=[
include "src/answer.rl"
target check { print CacheProbe:answer() }
]=])
file(WRITE "${root}/src/answer.rl" [=[
let CacheProbe = phrase { dictionary = true }
let CacheProbe:answer = fn () -> i64 { return 42 }
]=])

function(run_project expected)
    execute_process(
        COMMAND "${PROGRAM}" --project "${root}/recurloop.project.rl"
                --project-cache "${root}/cache" --target check
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR NOT out STREQUAL "${expected}\n")
        message(FATAL_ERROR "CLI project failed: rc=${rc}\n${out}\n${err}")
    endif()
endfunction()

run_project(42)
foreach(module IN ITEMS recurloop.project src/answer)
    if(NOT EXISTS "${root}/cache/modules/${module}.rli" OR
       NOT EXISTS "${root}/cache/modules/${module}.manifest")
        message(FATAL_ERROR "CLI did not cache ${module}")
    endif()
endforeach()
run_project(42)

execute_process(
    COMMAND "${PROGRAM}" --project "${root}/recurloop.project.rl"
            --project-cache "${root}/cache" --trace "${root}/src/answer.rl"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR out MATCHES "E\t[^\n]+" OR
   NOT out MATCHES "S\t")
    string(SUBSTRING "${out}" 0 1024 excerpt)
    message(FATAL_ERROR "CLI trace failed: rc=${rc}\n${excerpt}\n${err}")
endif()

file(WRITE "${root}/src/answer.rl" [=[
let CacheProbe = phrase { dictionary = true }
let CacheProbe:answer = fn () -> i64 { return 43 }
]=])
run_project(43)
file(REMOVE_RECURSE "${root}")
