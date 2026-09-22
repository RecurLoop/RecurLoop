if(NOT DEFINED PROGRAM)
  message(FATAL_ERROR "PROGRAM is required")
endif()

execute_process(
  COMMAND "${PROGRAM}" --file "${CMAKE_CURRENT_LIST_DIR}/_object_allocation.rl"
  RESULT_VARIABLE rc
  OUTPUT_VARIABLE out
  ERROR_VARIABLE err
)

if(NOT rc EQUAL 0)
  message(FATAL_ERROR "alloc(Type)/sizeof(Type) failed with ${rc}:\n${err}")
endif()
if(NOT err STREQUAL "")
  message(FATAL_ERROR "alloc(Type)/sizeof(Type) wrote stderr:\n${err}")
endif()
