get_filename_component(bin "${PROGRAM}" DIRECTORY)
get_filename_component(build "${bin}" DIRECTORY)
set(work "${CMAKE_CURRENT_BINARY_DIR}/target-regressions")
file(MAKE_DIRECTORY "${work}")

function(run_target name expected_status expected_output expected_error)
    execute_process(COMMAND "${PROGRAM}" --library-path "${build}/libraries"
            --project-cache "${work}/cache" --target "${name}"
        WORKING_DIRECTORY "${work}"
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 60)
    if(NOT rc STREQUAL "${expected_status}" OR NOT out STREQUAL "${expected_output}")
        message(FATAL_ERROR "Target ${name}: status=${rc}\n${out}${err}")
    endif()
    if(expected_error STREQUAL "")
        if(NOT err STREQUAL "")
            message(FATAL_ERROR "Target ${name}: unexpected diagnostic: ${err}")
        endif()
    elseif(NOT err MATCHES "${expected_error}")
        message(FATAL_ERROR "Target ${name}: expected ${expected_error}, got ${err}")
    endif()
endfunction()

# Implicit project discovery, a deferred fn definition, dependencies, and cache
# restoration all participate in the normal --target path.
file(WRITE "${work}/recurloop.project.rl" [=[
target prepare { print "prepare" }
target run depends [prepare] {
    fn answer() -> i64 { return 42 }
    print answer()
}
target fail { assert false }
target cycle depends [cycle] { print "must not run" }
]=])
run_target(run 0 "prepare\n42\n" "")
run_target(run 0 "prepare\n42\n" "")
run_target(missing 1 "" "Unknown RecurLoop target: missing")
run_target(cycle 1 "" "Cyclic target dependency: cycle")
run_target(fail 1 "" "recurloop.project.rl:6:[0-9]+:.*assertion failed: false")
file(REMOVE_RECURSE "${work}")
