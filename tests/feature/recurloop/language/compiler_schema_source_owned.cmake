if(NOT DEFINED PROGRAM)
  message(FATAL_ERROR "PROGRAM is required")
endif()

get_filename_component(HERE "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
get_filename_component(REPOSITORY_ROOT "${HERE}/../../../.." ABSOLUTE)
set(TMP "${CMAKE_CURRENT_BINARY_DIR}/compiler-schema-source-owned-test")
set(SOURCE_COPY "${TMP}/recurloop")
set(FIRST "${TMP}/first")
set(SECOND "${TMP}/second")
file(REMOVE_RECURSE "${TMP}")
file(MAKE_DIRECTORY "${SOURCE_COPY}" "${FIRST}" "${SECOND}")
file(COPY "${REPOSITORY_ROOT}/libraries/recurloop/" DESTINATION "${SOURCE_COPY}")

set(COMPILER_SOURCE "${SOURCE_COPY}/core/compiler.rl")
file(READ "${COMPILER_SOURCE}" TEXT)

# Rename the physical compiler-language root without depending on its previous
# spelling, then rename only quoted registry/slot keys. Semantic roles remain
# stable and are the only production-C++ contract.
string(REGEX REPLACE "language-root \"[^\"]+\""
                     "language-root \"stage6-language-root\""
                     TEXT "${TEXT}")

# Rename only quoted physical keys.  The unquoted semantic roles remain stable.
set(REPLACEMENTS
  "calling-conventions|cc-stage6"
  "functions|fn-stage6"
  "function-sources|src-stage6"
  "modules|mod-stage6"
  "settings|state-stage6"
  "module-selections|select-stage6"
  "link-objects|objects-stage6"
  "link-archives|archives-stage6"
  "link-paths|paths-stage6"
  "shared-libraries|shared-stage6"
  "types|types-stage6"
  "by-id|ids-stage6"
  "abi-kinds|abi-stage6"
  "next-id|next-stage6"
  "automatic-modules|automatic-stage6"
  "embed-language|embed-stage6"
  "selection-generation|selection-generation-stage6"
  "link-sequence|link-sequence-stage6"
  "link-generation|link-generation-stage6"
  "module-entry|module-entry-stage6")

foreach(PAIR IN LISTS REPLACEMENTS)
  string(REPLACE "|" ";" PARTS "${PAIR}")
  list(GET PARTS 0 OLD)
  list(GET PARTS 1 NEW)
  string(REPLACE "\"${OLD}\"" "\"${NEW}\"" TEXT "${TEXT}")
endforeach()
file(WRITE "${COMPILER_SOURCE}" "${TEXT}")

execute_process(
  COMMAND "${PROGRAM}" --file "${SOURCE_COPY}/core.rl"
  WORKING_DIRECTORY "${FIRST}"
  RESULT_VARIABLE FIRST_RC
  OUTPUT_VARIABLE FIRST_OUT
  ERROR_VARIABLE FIRST_ERR)
if(NOT FIRST_RC EQUAL 0)
  message(FATAL_ERROR "source-owned compiler schema first rebuild failed: ${FIRST_ERR}")
endif()
if(NOT EXISTS "${FIRST}/core.rli")
  message(FATAL_ERROR "source-owned compiler schema first rebuild did not produce core.rli")
endif()

execute_process(
  COMMAND "${PROGRAM}" --reset --import "${FIRST}/core.rli" --file "${SOURCE_COPY}/core.rl"
  WORKING_DIRECTORY "${SECOND}"
  RESULT_VARIABLE SECOND_RC
  OUTPUT_VARIABLE SECOND_OUT
  ERROR_VARIABLE SECOND_ERR)
if(NOT SECOND_RC EQUAL 0)
  message(FATAL_ERROR "source-owned compiler schema second rebuild failed: ${SECOND_ERR}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E compare_files "${FIRST}/core.rli" "${SECOND}/core.rli"
  RESULT_VARIABLE COMPARE_RC)
if(NOT COMPARE_RC EQUAL 0)
  message(FATAL_ERROR "renamed compiler schema did not reach a byte-for-byte self-hosting fixed point")
endif()

execute_process(
  COMMAND "${PROGRAM}" --reset --import "${FIRST}/core.rli" --string "print 2 + 3 * 4"
  RESULT_VARIABLE RUN_RC
  OUTPUT_VARIABLE RUN_OUT
  ERROR_VARIABLE RUN_ERR)
if(NOT RUN_RC EQUAL 0)
  message(FATAL_ERROR "renamed compiler schema image failed to execute source: ${RUN_ERR}")
endif()
string(STRIP "${RUN_OUT}" RUN_OUT)
if(NOT RUN_OUT STREQUAL "14")
  message(FATAL_ERROR "renamed compiler schema produced unexpected result '${RUN_OUT}'")
endif()
