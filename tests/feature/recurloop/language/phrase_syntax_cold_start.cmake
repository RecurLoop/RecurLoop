get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
set(BUILDER "${REPOSITORY_ROOT}/examples/07-workflows/reusable-syntax-image/build.rl")
set(CONSUMER "${REPOSITORY_ROOT}/examples/07-workflows/reusable-syntax-image/use.rl")
set(IMAGE "/tmp/recurloop-phrase-syntax.rli")

file(REMOVE "${IMAGE}")
execute_process(
    COMMAND "${PROGRAM}" --file "${BUILDER}"
    RESULT_VARIABLE build_rc
    OUTPUT_VARIABLE build_out
    ERROR_VARIABLE build_err
)
if (NOT build_rc EQUAL 0 OR NOT build_out STREQUAL "" OR NOT build_err STREQUAL "")
    message(FATAL_ERROR
        "Phrase syntax builder failed: status=${build_rc}, stdout='${build_out}', stderr='${build_err}'")
endif()
if (NOT EXISTS "${IMAGE}")
    message(FATAL_ERROR "Phrase syntax builder did not create ${IMAGE}")
endif()

execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --file "${CONSUMER}"
    RESULT_VARIABLE use_rc
    OUTPUT_VARIABLE use_out
    ERROR_VARIABLE use_err
)
set(EXPECTED_OUT "phrase-defined fn syntax loaded in a fresh process\n")
if (NOT use_rc EQUAL 0 OR NOT use_out STREQUAL EXPECTED_OUT OR NOT use_err STREQUAL "")
    message(FATAL_ERROR
        "Cold phrase syntax failed: status=${use_rc}, stdout='${use_out}', stderr='${use_err}'")
endif()

execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --string
            "let invalid = fn () -> integer { return truth maybe }"
    RESULT_VARIABLE error_rc
    OUTPUT_VARIABLE error_out
    ERROR_VARIABLE error_err
)
if (error_rc EQUAL 0 OR NOT error_err MATCHES
    "<input>:1:[0-9]+: truth expects on, only, or off")
    message(FATAL_ERROR
        "Phrase syntax diagnostic is missing its location: status=${error_rc}, stdout='${error_out}', stderr='${error_err}'")
endif()

file(REMOVE "${IMAGE}")
