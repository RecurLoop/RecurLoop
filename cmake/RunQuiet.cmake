# Run one incremental check quietly. Successful checks produce no child output;
# on failure, replay captured stdout/stderr so Ninja's step list stays readable
# without losing diagnostics.

if(NOT DEFINED QUIET_PROGRAM OR QUIET_PROGRAM STREQUAL "")
    message(FATAL_ERROR "RunQuiet.cmake requires QUIET_PROGRAM")
endif()

if(NOT DEFINED QUIET_LABEL OR QUIET_LABEL STREQUAL "")
    set(QUIET_LABEL "check")
endif()

if(NOT DEFINED QUIET_ARGC)
    set(QUIET_ARGC 0)
endif()

set(command "${QUIET_PROGRAM}")
if(QUIET_ARGC GREATER 0)
    math(EXPR last_arg "${QUIET_ARGC} - 1")
    foreach(index RANGE 0 ${last_arg})
        if(NOT DEFINED QUIET_ARG_${index})
            message(FATAL_ERROR "RunQuiet.cmake missing QUIET_ARG_${index}")
        endif()
        list(APPEND command "${QUIET_ARG_${index}}")
    endforeach()
endif()

execute_process(
    COMMAND ${command}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE stdout
    ERROR_VARIABLE stderr)

if(NOT result EQUAL 0)
    set(details "")
    if(NOT stdout STREQUAL "")
        string(APPEND details "\n----- stdout -----\n${stdout}")
    endif()
    if(NOT stderr STREQUAL "")
        string(APPEND details "\n----- stderr -----\n${stderr}")
    endif()
    message(FATAL_ERROR "[check] ${QUIET_LABEL} failed with exit code ${result}${details}")
endif()
