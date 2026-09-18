cmake_minimum_required(VERSION 3.25)

get_filename_component(ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
if(NOT DEFINED OUTPUT OR OUTPUT STREQUAL "")
    set(OUTPUT "${ROOT}/recurloop-work.zip")
elseif(NOT IS_ABSOLUTE "${OUTPUT}")
    set(OUTPUT "${ROOT}/${OUTPUT}")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/CoreFingerprint.cmake")
recurloop_core_fingerprint(current_fingerprint "${ROOT}")

execute_process(
    COMMAND git ls-files -co --exclude-standard
    WORKING_DIRECTORY "${ROOT}"
    RESULT_VARIABLE git_result
    OUTPUT_VARIABLE git_files
    ERROR_VARIABLE git_error
    OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT git_result EQUAL 0)
    message(FATAL_ERROR "bundle: git ls-files failed: ${git_error}")
endif()

string(REPLACE "\r\n" "\n" git_files "${git_files}")
string(REPLACE "\n" ";" candidates "${git_files}")
set(files)
foreach(relative IN LISTS candidates)
    if(relative STREQUAL "" OR relative MATCHES "(^|/)build(-[^/]*)?/" OR
       relative MATCHES "(^|/)\\.cache/" OR relative MATCHES "(^|/)\\.debug/" OR
       relative MATCHES "(^|/)__pycache__/" OR relative MATCHES "[.]pyc$" OR
       relative MATCHES "[.]zip$")
        continue()
    endif()
    if(EXISTS "${ROOT}/${relative}" AND NOT IS_DIRECTORY "${ROOT}/${relative}")
        list(APPEND files "${relative}")
    endif()
endforeach()

set(created_artifacts FALSE)
set(core_source "")
foreach(candidate IN ITEMS "${ROOT}/artifacts" "${ROOT}/.cache/core")
    if(EXISTS "${candidate}/core.rli" AND EXISTS "${candidate}/core.fingerprint")
        file(READ "${candidate}/core.fingerprint" fingerprint)
        string(STRIP "${fingerprint}" fingerprint)
        if(fingerprint STREQUAL current_fingerprint)
            set(core_source "${candidate}/core.rli")
            break()
        endif()
    endif()
endforeach()

if(NOT core_source STREQUAL "")
    if(NOT EXISTS "${ROOT}/artifacts/core.rli")
        file(MAKE_DIRECTORY "${ROOT}/artifacts")
        execute_process(COMMAND "${CMAKE_COMMAND}" -E copy "${core_source}" "${ROOT}/artifacts/core.rli"
                        COMMAND_ERROR_IS_FATAL ANY)
        file(WRITE "${ROOT}/artifacts/core.fingerprint" "${current_fingerprint}\n")
        set(created_artifacts TRUE)
    endif()
    list(APPEND files artifacts/core.rli artifacts/core.fingerprint)
endif()

get_filename_component(output_dir "${OUTPUT}" DIRECTORY)
file(MAKE_DIRECTORY "${output_dir}")
file(REMOVE "${OUTPUT}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar cf "${OUTPUT}" --format=zip -- ${files}
    WORKING_DIRECTORY "${ROOT}"
    RESULT_VARIABLE archive_result
    OUTPUT_VARIABLE archive_output
    ERROR_VARIABLE archive_error)

if(created_artifacts)
    file(REMOVE "${ROOT}/artifacts/core.rli" "${ROOT}/artifacts/core.fingerprint")
    file(GLOB remaining_artifacts "${ROOT}/artifacts/*")
    if(NOT remaining_artifacts)
        file(REMOVE_RECURSE "${ROOT}/artifacts")
    endif()
endif()

if(NOT archive_result EQUAL 0)
    message(FATAL_ERROR "bundle: archive creation failed: ${archive_error}${archive_output}")
endif()

file(SIZE "${OUTPUT}" output_bytes)
math(EXPR output_kib "(${output_bytes} + 1023) / 1024")
if(core_source STREQUAL "")
    message("[bundle] ${OUTPUT} (${output_kib} KiB, source only)")
else()
    message("[bundle] ${OUTPUT} (${output_kib} KiB, includes source-matched core.rli)")
endif()
