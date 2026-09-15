if(NOT DEFINED SEED OR NOT DEFINED CORE)
  message(FATAL_ERROR "ValidateSeedImage.cmake requires SEED and CORE")
endif()
if(NOT EXISTS "${SEED}")
  message(FATAL_ERROR "seed image does not exist: ${SEED}")
endif()
if(NOT EXISTS "${CORE}")
  message(FATAL_ERROR "core image does not exist: ${CORE}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E compare_files "${SEED}" "${CORE}"
  RESULT_VARIABLE same_result)
if(same_result EQUAL 0)
  message(FATAL_ERROR "stage-0 seed unexpectedly equals final core; bootstrap parity must not be restored")
endif()

file(SIZE "${SEED}" seed_size)
file(SIZE "${CORE}" core_size)
if(NOT seed_size LESS core_size)
  message(FATAL_ERROR "stage-0 seed is not smaller than final core (${seed_size} >= ${core_size}); seed is not minimal")
endif()

message(STATUS "RecurLoop seed/core separation: seed=${seed_size} bytes, core=${core_size} bytes")
