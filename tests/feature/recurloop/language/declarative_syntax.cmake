get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
set(EXAMPLE_DIR "${REPOSITORY_ROOT}/examples/03-phrases-and-syntax/declarative-syntax")
set(IMAGE "/tmp/recurloop-declarative-syntax.rli")

execute_process(
    COMMAND "${PROGRAM}" --file "${EXAMPLE_DIR}/main.rl"
    RESULT_VARIABLE smoke_rc
    OUTPUT_VARIABLE smoke_out
    ERROR_VARIABLE smoke_err
)
if(NOT smoke_rc EQUAL 0)
    message(FATAL_ERROR "Declarative syntax smoke example failed with status ${smoke_rc}:\n${smoke_err}\n${smoke_out}")
endif()
if(NOT smoke_err STREQUAL "")
    message(FATAL_ERROR "Declarative syntax smoke example wrote unexpected stderr:\n${smoke_err}")
endif()

file(REMOVE "${IMAGE}")
execute_process(
    COMMAND "${PROGRAM}" --file "${EXAMPLE_DIR}/roundtrip.rl"
    RESULT_VARIABLE export_rc
    OUTPUT_VARIABLE export_out
    ERROR_VARIABLE export_err
)
if(NOT export_rc EQUAL 0)
    message(FATAL_ERROR "Declarative syntax export failed with status ${export_rc}:\n${export_err}\n${export_out}")
endif()
if(NOT export_err STREQUAL "")
    message(FATAL_ERROR "Declarative syntax export wrote unexpected stderr:\n${export_err}")
endif()
if(NOT export_out STREQUAL "declarative syntax export ok\n")
    message(FATAL_ERROR "Declarative syntax export wrote unexpected stdout:\n${export_out}")
endif()
if(NOT EXISTS "${IMAGE}")
    message(FATAL_ERROR "Declarative syntax export did not create ${IMAGE}")
endif()

execute_process(
    COMMAND "${PROGRAM}" --import "${IMAGE}" --file "${EXAMPLE_DIR}/after-import.rl"
    RESULT_VARIABLE import_rc
    OUTPUT_VARIABLE import_out
    ERROR_VARIABLE import_err
)
if(NOT import_rc EQUAL 0)
    message(FATAL_ERROR "Imported declarative syntax failed with status ${import_rc}:\n${import_err}\n${import_out}")
endif()
if(NOT import_err STREQUAL "")
    message(FATAL_ERROR "Imported declarative syntax wrote unexpected stderr:\n${import_err}")
endif()
if(NOT import_out STREQUAL "declarative syntax import ok\n")
    message(FATAL_ERROR "Imported declarative syntax wrote unexpected stdout:\n${import_out}")
endif()

file(REMOVE "${IMAGE}")
