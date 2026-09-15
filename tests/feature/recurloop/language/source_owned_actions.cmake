if(NOT DEFINED PROGRAM)
  message(FATAL_ERROR "PROGRAM is required")
endif()

# A source-owned compiler action is internal compiler code. Its first JIT must
# not inherit module selections or auto/manual linking policy from the program
# currently being compiled. In particular, a selected entry may legitimately
# name the function that is about to be defined and therefore not exist yet.
set(source [=[
module manual
module clear
module entry not_built_yet
debug ping
]=])
execute_process(
  COMMAND "${PROGRAM}" --string "${source}"
  RESULT_VARIABLE rc
  OUTPUT_VARIABLE out
  ERROR_VARIABLE err)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "source-owned action JIT inherited user module policy: ${err}")
endif()
if(NOT out STREQUAL "pong\n")
  message(FATAL_ERROR "source-owned language.ping returned unexpected output: '${out}'")
endif()
