if(NOT DEFINED PROGRAM)
  message(FATAL_ERROR "PROGRAM is required")
endif()
if(NOT DEFINED CORE_IMAGE)
  message(FATAL_ERROR "CORE_IMAGE is required")
endif()

get_filename_component(HERE "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
get_filename_component(REPOSITORY_ROOT "${HERE}/../../../.." ABSOLUTE)
set(HELLO "${REPOSITORY_ROOT}/examples/01-getting-started/hello-world/main.rl")
set(CORE_SOURCE "${REPOSITORY_ROOT}/libraries/recurloop/core.rl")
set(TMP "${CMAKE_CURRENT_BINARY_DIR}/core-runtime-test")
file(REMOVE_RECURSE "${TMP}")
file(MAKE_DIRECTORY "${TMP}")

execute_process(COMMAND "${PROGRAM}" --file "${HELLO}"
  RESULT_VARIABLE default_rc OUTPUT_VARIABLE default_out ERROR_VARIABLE default_err)
if(NOT default_rc EQUAL 0)
  message(FATAL_ERROR "embedded core failed: ${default_err}")
endif()

execute_process(COMMAND "${PROGRAM}" --reset --import "${CORE_IMAGE}" --file "${HELLO}"
  RESULT_VARIABLE import_rc OUTPUT_VARIABLE import_out ERROR_VARIABLE import_err)
if(NOT import_rc EQUAL 0)
  message(FATAL_ERROR "reset+import core failed: ${import_err}")
endif()
if(NOT default_out STREQUAL import_out OR NOT default_err STREQUAL import_err)
  message(FATAL_ERROR "embedded and reset+import core behavior differs")
endif()

execute_process(COMMAND "${PROGRAM}" --reset --string "print 1"
  RESULT_VARIABLE reset_rc OUTPUT_VARIABLE reset_out ERROR_VARIABLE reset_err)
if(reset_rc EQUAL 0 OR NOT reset_err MATCHES "undefined phrase")
  message(FATAL_ERROR "--reset did not leave an empty language: ${reset_err}")
endif()

set(DEFAULT_REBUILD "${TMP}/default")
set(EXPLICIT_REBUILD "${TMP}/explicit")
file(MAKE_DIRECTORY "${DEFAULT_REBUILD}" "${EXPLICIT_REBUILD}")
execute_process(COMMAND "${PROGRAM}" --file "${CORE_SOURCE}"
  WORKING_DIRECTORY "${DEFAULT_REBUILD}"
  RESULT_VARIABLE rebuild_rc ERROR_VARIABLE rebuild_err)
if(NOT rebuild_rc EQUAL 0)
  message(FATAL_ERROR "default core rebuild failed: ${rebuild_err}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -E compare_files
  "${CORE_IMAGE}" "${DEFAULT_REBUILD}/core.rli" RESULT_VARIABLE compare_default)
if(NOT compare_default EQUAL 0)
  message(FATAL_ERROR "recurloop --file core.rl did not reproduce the embedded core")
endif()

execute_process(COMMAND "${PROGRAM}" --reset --import "${CORE_IMAGE}" --file "${CORE_SOURCE}"
  WORKING_DIRECTORY "${EXPLICIT_REBUILD}"
  RESULT_VARIABLE explicit_rc ERROR_VARIABLE explicit_err)
if(NOT explicit_rc EQUAL 0)
  message(FATAL_ERROR "explicit core rebuild failed: ${explicit_err}")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" -E compare_files
  "${CORE_IMAGE}" "${EXPLICIT_REBUILD}/core.rli" RESULT_VARIABLE compare_explicit)
if(NOT compare_explicit EQUAL 0)
  message(FATAL_ERROR "reset+import core.rli + core.rl did not reproduce core.rli")
endif()

foreach(removed IN ITEMS --bootstrap --language-image --engine-image)
  execute_process(COMMAND "${PROGRAM}" "${removed}"
    RESULT_VARIABLE old_rc OUTPUT_VARIABLE old_out ERROR_VARIABLE old_err)
  if(old_rc EQUAL 0 OR NOT old_err MATCHES "was removed")
    message(FATAL_ERROR "removed option ${removed} was not rejected clearly: ${old_err}")
  endif()
endforeach()
