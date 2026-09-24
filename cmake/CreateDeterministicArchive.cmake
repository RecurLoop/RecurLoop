cmake_minimum_required(VERSION 3.25)

foreach(required ROOT_DIR ARCHIVE SOURCE_DATE_EPOCH)
    if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
        message(FATAL_ERROR "${required} is required")
    endif()
endforeach()
if(NOT IS_DIRECTORY "${ROOT_DIR}")
    message(FATAL_ERROR "Archive root does not exist: ${ROOT_DIR}")
endif()
if(NOT SOURCE_DATE_EPOCH MATCHES "^[0-9]+$")
    message(FATAL_ERROR "SOURCE_DATE_EPOCH must be an integer, got '${SOURCE_DATE_EPOCH}'")
endif()

find_program(TAR_EXECUTABLE tar REQUIRED)
find_program(GZIP_EXECUTABLE gzip REQUIRED)
execute_process(COMMAND "${TAR_EXECUTABLE}" --version
    OUTPUT_VARIABLE tar_version ERROR_VARIABLE tar_error RESULT_VARIABLE tar_result)
if(NOT tar_result EQUAL 0 OR NOT tar_version MATCHES "GNU tar")
    message(FATAL_ERROR "Deterministic Linux archives require GNU tar: ${tar_error}${tar_version}")
endif()

get_filename_component(root_parent "${ROOT_DIR}" DIRECTORY)
get_filename_component(root_name "${ROOT_DIR}" NAME)
get_filename_component(archive_dir "${ARCHIVE}" DIRECTORY)
file(MAKE_DIRECTORY "${archive_dir}")
set(tar_file "${ARCHIVE}.tmp.tar")
file(REMOVE "${ARCHIVE}" "${tar_file}" "${tar_file}.gz")

execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env LC_ALL=C TZ=UTC
        "${TAR_EXECUTABLE}"
        --sort=name
        "--mtime=@${SOURCE_DATE_EPOCH}"
        --owner=0 --group=0 --numeric-owner
        --format=gnu
        --mode=u=rwX,go=rX
        -cf "${tar_file}" "${root_name}"
    WORKING_DIRECTORY "${root_parent}"
    RESULT_VARIABLE tar_result ERROR_VARIABLE tar_error)
if(NOT tar_result EQUAL 0)
    message(FATAL_ERROR "Deterministic tar creation failed: ${tar_error}")
endif()
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env LC_ALL=C TZ=UTC
        "${GZIP_EXECUTABLE}" -n -9 -f "${tar_file}"
    RESULT_VARIABLE gzip_result ERROR_VARIABLE gzip_error)
if(NOT gzip_result EQUAL 0)
    message(FATAL_ERROR "Deterministic gzip compression failed: ${gzip_error}")
endif()
file(RENAME "${tar_file}.gz" "${ARCHIVE}")
