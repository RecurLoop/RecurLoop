if(NOT DEFINED PROGRAM OR NOT DEFINED CORE_IMAGE)
  message(FATAL_ERROR "PROGRAM and CORE_IMAGE are required")
endif()

set(root "${CMAKE_CURRENT_BINARY_DIR}/recurloop-negative-fixed-point")
file(REMOVE_RECURSE "${root}")
file(MAKE_DIRECTORY "${root}/source" "${root}/first" "${root}/second")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/../../../../libraries/recurloop/" DESTINATION "${root}/source")

set(compiler "${root}/source/core/compiler.rl")
file(READ "${compiler}" text)
string(FIND "${text}" "registry functions \"functions\"" position)
if(position EQUAL -1)
  message(FATAL_ERROR "negative fixed-point test cannot find the functions registry declaration")
endif()
string(REPLACE "registry functions \"functions\"" "registry functions \"functions-negative-fixed-point\"" text "${text}")
file(WRITE "${compiler}" "${text}")

execute_process(
  COMMAND "${PROGRAM}" --file "${root}/source/core.rl"
  WORKING_DIRECTORY "${root}/first"
  RESULT_VARIABLE first_result
  OUTPUT_VARIABLE first_output
  ERROR_VARIABLE first_error)
if(NOT first_result EQUAL 0)
  message(FATAL_ERROR "modified core did not build (${first_result})\nstdout:\n${first_output}\nstderr:\n${first_error}")
endif()

execute_process(
  COMMAND "${PROGRAM}" --reset --import "${root}/first/core.rli" --file "${root}/source/core.rl"
  WORKING_DIRECTORY "${root}/second"
  RESULT_VARIABLE second_result
  OUTPUT_VARIABLE second_output
  ERROR_VARIABLE second_error)
if(NOT second_result EQUAL 0)
  message(FATAL_ERROR "modified core did not self-host (${second_result})\nstdout:\n${second_output}\nstderr:\n${second_error}")
endif()

execute_process(COMMAND "${CMAKE_COMMAND}" -E compare_files "${root}/first/core.rli" "${root}/second/core.rli"
                RESULT_VARIABLE modified_fixed_point)
if(NOT modified_fixed_point EQUAL 0)
  message(FATAL_ERROR "modified semantic core did not reach its own byte-for-byte fixed point")
endif()

execute_process(COMMAND "${CMAKE_COMMAND}" -E compare_files "${CORE_IMAGE}" "${root}/first/core.rli"
                RESULT_VARIABLE baseline_comparison)
if(baseline_comparison EQUAL 0)
  message(FATAL_ERROR "semantic modification of core.rl produced the unchanged baseline core.rli")
endif()
