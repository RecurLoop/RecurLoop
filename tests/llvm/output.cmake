if (NOT DEFINED PROGRAM OR NOT EXISTS "${PROGRAM}")
    message(FATAL_ERROR "LLVM output test needs PROGRAM")
endif()
if (NOT DEFINED READELF OR READELF STREQUAL "")
    find_program(READELF readelf REQUIRED)
endif()

set(source "/tmp/recurloop-llvm-output-test.rl")
set(object "/tmp/recurloop-llvm-output-test.o")
set(executable "/tmp/recurloop-llvm-output-test")
file(REMOVE "${object}" "${executable}")

if (DEFINED TARGET_TRIPLE AND NOT TARGET_TRIPLE MATCHES "^x86_64")
    set(image "/tmp/recurloop-llvm-output-test.rli")
    file(REMOVE "${image}")
    file(WRITE "${source}" [=[
fn llvm_cross_helper(value:i64) -> i64 {
    return value + 1
}

engine export "/tmp/recurloop-llvm-output-test.rli"
]=])
    execute_process(COMMAND "${PROGRAM}" --file "${source}" RESULT_VARIABLE image_result
                    OUTPUT_VARIABLE image_output ERROR_VARIABLE image_error)
    if (NOT image_result EQUAL 0)
        message(FATAL_ERROR "LLVM source image failed (${image_result}):\n${image_output}${image_error}")
    endif()
    file(WRITE "${source}" [=[

emit object "/tmp/recurloop-llvm-output-test.o" llvm_cross_caller = fn (value:i64) -> i64 {
    return llvm_cross_helper(value)
}
]=])
    execute_process(COMMAND "${PROGRAM}" --import "${image}" --file "${source}" RESULT_VARIABLE caller_result
                    OUTPUT_VARIABLE caller_output ERROR_VARIABLE caller_error)
    if (NOT caller_result EQUAL 0)
        message(FATAL_ERROR "LLVM cross object failed (${caller_result}):\n${caller_output}${caller_error}")
    endif()
    execute_process(COMMAND "${READELF}" -Ws "${object}" RESULT_VARIABLE readelf_result
                    OUTPUT_VARIABLE symbols ERROR_VARIABLE readelf_error)
    if (NOT readelf_result EQUAL 0 OR NOT symbols MATCHES "llvm_cross_helper" OR
        NOT symbols MATCHES "llvm_cross_caller")
        message(FATAL_ERROR "LLVM cross object did not combine both inputs:\n${symbols}${readelf_error}")
    endif()
    execute_process(COMMAND "${READELF}" -h "${object}" RESULT_VARIABLE header_result
                    OUTPUT_VARIABLE header ERROR_VARIABLE header_error)
    if (TARGET_TRIPLE MATCHES "^aarch64" AND
        (NOT header_result EQUAL 0 OR NOT header MATCHES "Machine:[ ]+AArch64"))
        message(FATAL_ERROR "LLVM cross object is not AArch64:\n${header}${header_error}")
    endif()
    file(REMOVE "${source}" "${object}" "${image}")
    return()
endif()

file(WRITE "${source}" [=[
let done = <return>
let plus = <+>

extern assembly_answer() -> i64 abi sysv-amd64
let assembly_answer = asm {
    mov rax, 37
    ret
}

fn llvm_output_dependency(value:i64) -> i64 {
    return value
}

fn llvm_output_apply(callback:fn (i64) -> i64, value:i64) -> i64 {
    return callback(value)
}

emit object "/tmp/recurloop-llvm-output-test.o" llvm_add = fn (left:i64, right:i64) -> i64 {
    done left plus right
}

emit executable "/tmp/recurloop-llvm-output-test" llvm_program = fn () -> i64 {
    var fraction = 0.5
    return assembly_answer() + llvm_output_dependency(
        llvm_output_apply(fn (value:i64) -> i64 { return value }, cast(i64, fraction * 10.0))
    )
}

fn llvm_runtime_add(left:i64, right:i64) -> i64 {
    return left + right
}
assert llvm_runtime_add(20, 22) == 42

// Compiled phrase blocks also use the LLVM runtime pipeline when it is enabled.
let llvm_runtime_phrase = {
    invoke llvm_runtime_add(20, 22)
}
llvm_runtime_phrase
]=])

execute_process(COMMAND "${PROGRAM}" --file "${source}" RESULT_VARIABLE compile_result
                OUTPUT_VARIABLE compile_output ERROR_VARIABLE compile_error)
if (NOT compile_result EQUAL 0)
    message(FATAL_ERROR "LLVM output failed (${compile_result}):\n${compile_output}${compile_error}")
endif()

execute_process(COMMAND "${READELF}" -Ws "${object}" RESULT_VARIABLE readelf_result
                OUTPUT_VARIABLE symbols ERROR_VARIABLE readelf_error)
if (NOT readelf_result EQUAL 0 OR NOT symbols MATCHES "llvm_add")
    message(FATAL_ERROR "LLVM object does not export llvm_add:\n${symbols}${readelf_error}")
endif()

execute_process(COMMAND "${executable}" RESULT_VARIABLE run_result)
if (NOT run_result EQUAL 42)
    message(FATAL_ERROR "LLVM executable returned ${run_result}, expected 42")
endif()

file(REMOVE "${source}" "${object}" "${executable}")
