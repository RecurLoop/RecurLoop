# Exact source cases supplied in recurloop-critical-regressions.zip.
get_filename_component(bin "${PROGRAM}" DIRECTORY)
get_filename_component(build "${bin}" DIRECTORY)
set(fixtures "${CMAKE_CURRENT_LIST_DIR}/../../../fixtures/critical-regressions")
set(work "${CMAKE_CURRENT_BINARY_DIR}/critical-regressions")
file(REMOVE_RECURSE "${work}")
file(MAKE_DIRECTORY "${work}/02-jit-array/build")
file(COPY "${fixtures}/" DESTINATION "${work}")

function(run_case directory expected)
    execute_process(COMMAND "${PROGRAM}" --library-path "${build}/libraries" ${ARGN}
        WORKING_DIRECTORY "${work}/${directory}"
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 60)
    if(NOT rc STREQUAL "0" OR NOT err STREQUAL "")
        message(FATAL_ERROR "${directory} ${ARGN}: status=${rc}\nstdout=${out}\nstderr=${err}")
    endif()
    if(expected STREQUAL "targets")
        string(JSON count LENGTH "${out}" targets)
        string(JSON first GET "${out}" targets 0 name)
        string(JSON second GET "${out}" targets 1 name)
        if(NOT count EQUAL 2 OR NOT first STREQUAL "run" OR NOT second STREQUAL "test")
            message(FATAL_ERROR "Unexpected project targets: ${out}")
        endif()
    elseif(NOT out STREQUAL "${expected}")
        message(FATAL_ERROR "${directory} ${ARGN}: expected '${expected}', got '${out}'")
    endif()
endfunction()

run_case(01-inferred-poly "IMPORT_OK\n" --file control.rl)
run_case(01-inferred-poly "defined\n" --file bug.rl)
run_case(02-jit-array "100\n" --file bug.rl)
run_case(02-jit-array "" --file native.rl)
execute_process(COMMAND "${work}/02-jit-array/build/array-aggregation-native"
    WORKING_DIRECTORY "${work}/02-jit-array"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 15)
if(NOT rc STREQUAL "0" OR NOT out STREQUAL "100\n" OR NOT err STREQUAL "")
    message(FATAL_ERROR "Native array aggregation disagrees with JIT: status=${rc}\n${out}${err}")
endif()

run_case(03-project-targets "DIRECT_FILE_OK\n" --file control.rl)
run_case(03-project-targets "" --file recurloop.project.rl)
# The first listing starts with an empty cache; subsequent actions restore it.
# Repeat the sequence to cover a second process using the same cached project.
foreach(pass RANGE 1 2)
    run_case(03-project-targets targets --targets)
    run_case(03-project-targets "42\n" --target run)
    run_case(03-project-targets "" --target test)
endforeach()
file(REMOVE_RECURSE "${work}")
