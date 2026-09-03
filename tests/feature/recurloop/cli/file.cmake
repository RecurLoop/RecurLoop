#----------------------------------------------------------------------------------------------------------------------#
#--- default version
execute_process(
    COMMAND "${PROGRAM}" "${CMAKE_CURRENT_LIST_DIR}/_input_file.rl"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

set(EXPECTED_OUT [=[
pong
]=])

# stderr should be empty
if (NOT err STREQUAL "")
    message(FATAL_ERROR "Unexpected stderr:\n${err}")
endif()

# stdout
if (NOT out STREQUAL EXPECTED_OUT)
    message(FATAL_ERROR "Unexpected stdout:\n${out}")
endif()

# exit code
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "Unexpected status code:\n${rc}")
endif()

#----------------------------------------------------------------------------------------------------------------------#
#--- short version
execute_process(
    COMMAND "${PROGRAM}" -f "${CMAKE_CURRENT_LIST_DIR}/_input_file.rl"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

set(EXPECTED_OUT [=[
pong
]=])

# stderr should be empty
if (NOT err STREQUAL "")
    message(FATAL_ERROR "Unexpected stderr:\n${err}")
endif()

# stdout
if (NOT out STREQUAL EXPECTED_OUT)
    message(FATAL_ERROR "Unexpected stdout:\n${out}")
endif()

# exit code
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "Unexpected status code:\n${rc}")
endif()

#----------------------------------------------------------------------------------------------------------------------#
#--- long version
execute_process(
    COMMAND "${PROGRAM}" --file "${CMAKE_CURRENT_LIST_DIR}/_input_file.rl"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

set(EXPECTED_OUT [=[
pong
]=])

# stderr should be empty
if (NOT err STREQUAL "")
    message(FATAL_ERROR "Unexpected stderr:\n${err}")
endif()

# stdout
if (NOT out STREQUAL EXPECTED_OUT)
    message(FATAL_ERROR "Unexpected stdout:\n${out}")
endif()

# exit code
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "Unexpected status code:\n${rc}")
endif()
