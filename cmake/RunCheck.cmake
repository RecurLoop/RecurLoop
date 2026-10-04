# Run an incremental check with stdout/stderr attached to the terminal.
# Ninja callers must use USES_TERMINAL to avoid buffering the forwarded output.

if(NOT DEFINED CHECK_PROGRAM OR CHECK_PROGRAM STREQUAL "")
    message(FATAL_ERROR "RunCheck.cmake requires CHECK_PROGRAM")
endif()

if(NOT DEFINED CHECK_LABEL OR CHECK_LABEL STREQUAL "")
    set(CHECK_LABEL "check")
endif()

if(NOT DEFINED CHECK_ARGC)
    set(CHECK_ARGC 0)
endif()

set(command "${CHECK_PROGRAM}")
if(CHECK_ARGC GREATER 0)
    math(EXPR last_arg "${CHECK_ARGC} - 1")
    foreach(index RANGE 0 ${last_arg})
        if(NOT DEFINED CHECK_ARG_${index})
            message(FATAL_ERROR "RunCheck.cmake missing CHECK_ARG_${index}")
        endif()
        list(APPEND command "${CHECK_ARG_${index}}")
    endforeach()
endif()

execute_process(
    COMMAND ${command}
    RESULT_VARIABLE result)

if(NOT result STREQUAL "0")
    message(FATAL_ERROR "[check] ${CHECK_LABEL} failed with status ${result}")
endif()
