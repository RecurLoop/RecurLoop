get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)

execute_process(
    COMMAND "${PROGRAM}" --file "${REPOSITORY_ROOT}/tests/feature/recurloop/language/_phrase_aliases.rl"
    RESULT_VARIABLE aliases_rc
    OUTPUT_VARIABLE aliases_out
    ERROR_VARIABLE aliases_err
)

if (NOT aliases_rc EQUAL 0 OR NOT aliases_out STREQUAL "5\n13\n1\n" OR NOT aliases_err STREQUAL "")
    message(FATAL_ERROR
        "Phrase aliases failed: status=${aliases_rc}, stdout='${aliases_out}', stderr='${aliases_err}'")
endif()
