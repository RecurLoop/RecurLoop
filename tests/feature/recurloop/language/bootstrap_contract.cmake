get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
execute_process(
    COMMAND "${REPOSITORY_ROOT}/libraries/recurloop/check-bootstrap.sh" "${PROGRAM}"
    WORKING_DIRECTORY "${REPOSITORY_ROOT}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "bootstrap contract failed (${rc})\nstdout:\n${out}\nstderr:\n${err}")
endif()
if (NOT err STREQUAL "")
    message(FATAL_ERROR "bootstrap contract wrote stderr:\n${err}")
endif()
if (NOT out MATCHES "fixed host surface is isolated")
    message(FATAL_ERROR "bootstrap contract did not report success:\n${out}")
endif()
