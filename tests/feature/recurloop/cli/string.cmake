#----------------------------------------------------------------------------------------------------------------------#
#--- short version
execute_process(
    COMMAND "${PROGRAM}" -s "debug ping"
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
    COMMAND "${PROGRAM}" --string "debug ping"
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
#--- pipeline default
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E echo_append "debug ping"
    COMMAND "${PROGRAM}"
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
#--- pipeline explicitly
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E echo_append "debug ping"
    COMMAND "${PROGRAM}" -
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
#--- mix [1]
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E echo_append "pi"
    COMMAND "${PROGRAM}" --string "debug"  -  -s "ng"
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
