if(NOT DEFINED INPUT OR NOT DEFINED FINGERPRINT OR NOT DEFINED CACHE_DIR)
    message(FATAL_ERROR "CacheCore.cmake requires INPUT, FINGERPRINT and CACHE_DIR")
endif()
if(NOT EXISTS "${INPUT}")
    return()
endif()

file(MAKE_DIRECTORY "${CACHE_DIR}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${INPUT}" "${CACHE_DIR}/core.rli"
                COMMAND_ERROR_IS_FATAL ANY)
file(WRITE "${CACHE_DIR}/core.fingerprint.tmp" "${FINGERPRINT}\n")
file(RENAME "${CACHE_DIR}/core.fingerprint.tmp" "${CACHE_DIR}/core.fingerprint")
