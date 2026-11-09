set(work "${CMAKE_CURRENT_BINARY_DIR}/jit-aot-arrays")
file(MAKE_DIRECTORY "${work}")
set(source [=[
extern free(pointer:u8*) -> void abi sysv-amd64
record Row { values:i64[8] }
record Data { rows:Row[64] totals:i64[8] }
fn aggregate(data:Data*, row_count:i64) -> i64 {
    var i = 0
    while i < row_count {
        var j = 0
        while j < 8 {
            data.rows[i].values[j] = i * 8 + j
            j += 1
        }
        i += 1
    }
    var total = 0
    var j = 0
    while j < 8 {
        var sum = 0
        var k = 0
        while k < row_count {
            sum += data.rows[k].values[j]
            k += 1
        }
        data.totals[j] = sum
        total += sum
        j += 1
    }
    return total
}
fn probe() -> i64 {
    let data = alloc(Data)
    if !data { return 99 }
    defer free(cast(u8*, data))
    let result = aggregate(data, 64)
    if result != 130816 { return 98 }
    // Read the stored aggregates too, so incorrect writes cannot be hidden
    // by a correct scalar reduction result.
    var column = 0
    while column < 8 {
        if data.totals[column] != 16128 + 64 * column { return 97 }
        column += 1
    }
    return 42
}
print probe()
print probe()
]=])

# Optimized native output and source-debugger output use different lowering
# paths in an LLVM host. Both must agree with the JIT on the same function.
foreach(mode IN ITEMS optimized debug)
    set(option "")
    if(mode STREQUAL "debug")
        set(option "debug ")
    endif()
    set(executable "${work}/${mode}")
    file(WRITE "${work}/${mode}.rl" "${source}\nemit executable ${option}\"${executable}\" array_entry = fn () -> i64 { return probe() }\n")
    execute_process(COMMAND "${PROGRAM}" --file "${work}/${mode}.rl"
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 60)
    if(NOT rc STREQUAL "0" OR NOT out STREQUAL "42\n42\n" OR NOT err STREQUAL "")
        message(FATAL_ERROR "${mode} compilation/JIT: status=${rc}\n${out}${err}")
    endif()
    execute_process(COMMAND "${executable}"
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 15)
    if(NOT rc STREQUAL "42" OR NOT out STREQUAL "" OR NOT err STREQUAL "")
        message(FATAL_ERROR "${mode} ELF disagrees with JIT: status=${rc}\n${out}${err}")
    endif()
endforeach()

file(WRITE "${work}/invalid.rl" "record Row { values:i64[8] }\nfn invalid(row:Row*) -> i64 { return row.absent[0] }\n")
execute_process(COMMAND "${PROGRAM}" --file "${work}/invalid.rl"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
if(NOT rc MATCHES "^[1-9][0-9]*$" OR NOT err MATCHES "invalid.rl:2:[0-9]+: fn: record 'Row' has no field 'absent'")
    message(FATAL_ERROR "Invalid aggregate access must report a source diagnostic: status=${rc}\n${out}${err}")
endif()
file(REMOVE_RECURSE "${work}")
