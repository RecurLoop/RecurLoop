function(expect_source_error name source expected)
    execute_process(
        COMMAND "${PROGRAM}" --string "${source}"
        RESULT_VARIABLE rc
        OUTPUT_VARIABLE out
        ERROR_VARIABLE err
    )

    if (rc EQUAL 0)
        message(FATAL_ERROR "${name}: expected a non-zero status; stdout='${out}', stderr='${err}'")
    endif()
    string(FIND "${err}" "${expected}" position)
    if (position EQUAL -1)
        message(FATAL_ERROR "${name}: expected '${expected}' in stderr, got '${err}'")
    endif()
endfunction()

expect_source_error(
    "undefined phrase"
    "debug ping\nthis_does_not_exist\n"
    "<input>:2:1: undefined phrase"
)

expect_source_error(
    "multiline expression"
    "assert (true &&\n  missing)\n"
    "<input>:2:3: expression: undefined variable: 'missing'"
)

expect_source_error(
    "function body"
    "let f = fn () -> i64 {\n  return missing\n}\n"
    "<input>:2:10: fn: unknown fn local or typed function 'missing'"
)

expect_source_error(
    "multiline function signature"
    "let f = fn (\n  value:i64,\n  value:i64\n) -> i64 { return value }\n"
    "<input>:3:3: fn: duplicate parameter 'value'"
)

expect_source_error(
    "typed record"
    "record Bad {\n  value:\n}\n"
    "<input>:3:1: typed declaration: expected a type"
)

expect_source_error(
    "assembler"
    "emit object \"/tmp/recurloop-error-location.o\" = asm {\n.text\n  not_an_instruction rax\n}\n"
    "<input>:3:3: assembler: unknown instruction 'not_an_instruction'"
)

expect_source_error(
    "phrase definition"
    "let bad = phrase {\n  nope = true\n}\n"
    "<input>:2:3: phrase definition: unknown field 'nope'"
)

expect_source_error(
    "inline phrase action"
    "let bad = phrase {\n  action = fn (context:Context*, phrase:Phrase*) -> void {\n    return missing\n  }\n}\n"
    "<input>:3:12: fn: unknown fn local or typed function 'missing'"
)

execute_process(
    COMMAND "${PROGRAM}" --file
    RESULT_VARIABLE option_rc
    OUTPUT_VARIABLE option_out
    ERROR_VARIABLE option_err
)
if (option_rc EQUAL 0 OR NOT option_err MATCHES "<command-line>:1:1: option '--file' requires a path")
    message(FATAL_ERROR
        "missing option argument: status=${option_rc}, stdout='${option_out}', stderr='${option_err}'")
endif()

set(include_fixture "${CMAKE_CURRENT_LIST_DIR}/_error_location_outer.rl")
set(inner_fixture "${CMAKE_CURRENT_LIST_DIR}/_error_location_inner.rl")
execute_process(
    COMMAND "${PROGRAM}" --file "${include_fixture}"
    RESULT_VARIABLE include_rc
    OUTPUT_VARIABLE include_out
    ERROR_VARIABLE include_err
)
string(FIND "${include_err}" "${inner_fixture}:2:1: undefined phrase" include_position)
if (include_rc EQUAL 0 OR include_position EQUAL -1)
    message(FATAL_ERROR
        "included source: status=${include_rc}, stdout='${include_out}', stderr='${include_err}'")
endif()
