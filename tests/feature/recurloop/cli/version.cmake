#----------------------------------------------------------------------------------------------------------------------#
#--- long version
execute_process(
    COMMAND "${PROGRAM}" --version
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

# stderr should be empty
if (NOT err STREQUAL "")
    message(FATAL_ERROR "Unexpected stderr:\n${err}")
endif()

# stdout
if (NOT out MATCHES "^[^\n]*\n?$")
    message(FATAL_ERROR "Unexpected stdout:\n${out}")
endif()

# exit code
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "Unexpected status code:\n${rc}")
endif()

#----------------------------------------------------------------------------------------------------------------------#
#--- short version
execute_process(
    COMMAND "${PROGRAM}" -v
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

# stderr should be empty
if (NOT err STREQUAL "")
    message(FATAL_ERROR "Unexpected stderr:\n${err}")
endif()

# stdout
if (NOT out MATCHES "^[^\n]*\n?$")
    message(FATAL_ERROR "Unexpected stdout:\n${out}")
endif()

# exit code
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "Unexpected status code:\n${rc}")
endif()



#----------------------------------------------------------------------------------------------------------------------#
#--- version wins with invalid argument
execute_process(
    COMMAND "${PROGRAM}" invalid_argument --version
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

# stderr should be empty
if (NOT err STREQUAL "")
    message(FATAL_ERROR "Unexpected stderr:\n${err}")
endif()

# stdout
if (NOT out MATCHES "^[^\n]*\n?$")
    message(FATAL_ERROR "Unexpected stdout:\n${out}")
endif()

# exit code
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "Unexpected status code:\n${rc}")
endif()
