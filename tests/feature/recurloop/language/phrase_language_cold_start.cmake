get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
set(BUILDER "${REPOSITORY_ROOT}/examples/07-workflows/reusable-language-image/build.rl")
set(CONSUMER "${REPOSITORY_ROOT}/examples/07-workflows/reusable-language-image/use.rl")
set(IMAGE "/tmp/recurloop-phrase-language.rli")

file(REMOVE "${IMAGE}")
execute_process(
    COMMAND "${PROGRAM}" --file "${BUILDER}"
    RESULT_VARIABLE build_rc
    OUTPUT_VARIABLE build_out
    ERROR_VARIABLE build_err
)
if (NOT build_rc EQUAL 0 OR NOT build_out STREQUAL "" OR NOT build_err STREQUAL "")
    message(FATAL_ERROR
        "Phrase language builder failed: status=${build_rc}, stdout='${build_out}', stderr='${build_err}'")
endif()
if (NOT EXISTS "${IMAGE}")
    message(FATAL_ERROR "Phrase language builder did not create ${IMAGE}")
endif()

execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --file "${CONSUMER}"
    RESULT_VARIABLE use_rc
    OUTPUT_VARIABLE use_out
    ERROR_VARIABLE use_err
)
set(EXPECTED_OUT "phrase language loaded in a fresh process\n")
if (NOT use_rc EQUAL 0 OR NOT use_out STREQUAL EXPECTED_OUT OR NOT use_err STREQUAL "")
    message(FATAL_ERROR
        "Cold phrase language failed: status=${use_rc}, stdout='${use_out}', stderr='${use_err}'")
endif()

execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --string "repeat nope { debug:ping }"
    RESULT_VARIABLE error_rc
    OUTPUT_VARIABLE error_out
    ERROR_VARIABLE error_err
)
if (error_rc EQUAL 0 OR NOT error_err MATCHES
    "<input>:1:8: repeat expects a non-negative decimal count")
    message(FATAL_ERROR
        "Cold compiled diagnostic has the wrong location: status=${error_rc}, stdout='${error_out}', stderr='${error_err}'")
endif()

file(REMOVE "${IMAGE}")
