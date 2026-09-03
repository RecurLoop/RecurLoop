get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)

execute_process(
    COMMAND "${PROGRAM}" --file "${REPOSITORY_ROOT}/examples/03-phrases-and-syntax/indentation-syntax/main.rl"
    RESULT_VARIABLE indentation_rc
    OUTPUT_VARIABLE indentation_out
    ERROR_VARIABLE indentation_err
)

if (NOT indentation_rc EQUAL 0 OR
    NOT indentation_out STREQUAL "5\n13\n1\n42\n10\n" OR
    NOT indentation_err STREQUAL "")
    message(FATAL_ERROR
        "Indentation functions failed: status=${indentation_rc}, stdout='${indentation_out}', stderr='${indentation_err}'")
endif()
