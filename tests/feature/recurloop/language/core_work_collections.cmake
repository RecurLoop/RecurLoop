if(NOT DEFINED PROGRAM)
    message(FATAL_ERROR "PROGRAM is required")
endif()

execute_process(
    COMMAND "${PROGRAM}" --string "Core:Work:SelfTest"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "source-owned compiler work-memory self-test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
