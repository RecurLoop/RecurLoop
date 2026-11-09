get_filename_component(bin "${PROGRAM}" DIRECTORY)
get_filename_component(build "${bin}" DIRECTORY)
set(work "${CMAKE_CURRENT_BINARY_DIR}/inferred-regressions")
file(MAKE_DIRECTORY "${work}")

function(run_inferred name source expected)
    file(WRITE "${work}/${name}.rl" "${source}")
    execute_process(COMMAND "${PROGRAM}" --library-path "${build}/libraries"
            ${ARGN} --file "${work}/${name}.rl"
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 60)
    if(NOT rc STREQUAL "0" OR NOT out STREQUAL "${expected}" OR NOT err STREQUAL "")
        message(FATAL_ERROR "${name}: status=${rc}\nstdout=${out}\nstderr=${err}")
    endif()
endfunction()

# Defining a function must neither execute its body nor create a specialization.
# Exercise both CLI preloading and an import inside the source request.
set(definitions [=[
poly fn unused(a, b) { return a / b }
poly fn zero() { return 42 }
poly fn sum8(a, b, c, d, e, f, g, h) { return a + b + c + d + e + f + g + h }
poly specializations unused
poly specializations zero
poly specializations sum8
]=])
set(expected "unused specializations=0\nzero specializations=0\nsum8 specializations=0\n")
run_inferred(preloaded "${definitions}" "${expected}" --library inferred)
run_inferred(imported "import inferred\n${definitions}" "${expected}")
# Importing after user declarations also exercises compiler type rebasing.
run_inferred(existing_types "record ImportProbe { value:i64 }\nfn read_before_import(value:ImportProbe*) -> i64 { return value.value }\nimport inferred\n${definitions}" "${expected}")

run_inferred(calls [=[
import inferred
poly fn combine(a, b) { return a + b }
poly fn factorial(n) {
    if n <= 1 { return 1 }
    return n * factorial(n - 1)
}
poly fn sum8(a, b, c, d, e, f, g, h) { return a + b + c + d + e + f + g + h }
print combine(20, 22)
print combine("Recur", "Loop")
print combine(21, 21)
print factorial(5)
print sum8(1, 2, 3, 4, 5, 6, 7, 14)
poly specializations combine
]=] "42\nRecurLoop\n42\n120\n42\ncombine specializations=2\n  (integer,integer) -> integer compiled=1\n  (text,text) -> text compiled=1\n")

file(WRITE "${work}/invalid.rl" "import inferred\npoly fn invalid(value) { return value + }\n")
execute_process(COMMAND "${PROGRAM}" --library-path "${build}/libraries" --file "${work}/invalid.rl"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 60)
if(NOT rc MATCHES "^[1-9][0-9]*$" OR NOT err MATCHES "invalid.rl:2:[0-9]+: Inferred: expected expression")
    message(FATAL_ERROR "Invalid inferred syntax must report a source diagnostic: status=${rc}\n${out}${err}")
endif()

file(WRITE "${work}/unknown.rl" [=[
import inferred
poly fn caller(value) { return missing_function(value) }
print caller(1)
]=])
execute_process(COMMAND "${PROGRAM}" --library-path "${build}/libraries" --file "${work}/unknown.rl"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 60)
if(NOT rc MATCHES "^[1-9][0-9]*$" OR NOT err MATCHES "unknown.rl:3:[0-9]+: Inferred: call to unknown or non-callable function")
    message(FATAL_ERROR "Unknown inferred call must report its cause: status=${rc}\n${out}${err}")
endif()
file(REMOVE_RECURSE "${work}")
