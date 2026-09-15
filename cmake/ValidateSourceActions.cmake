if(NOT DEFINED RUNNER OR NOT DEFINED CORE OR NOT DEFINED ALLOWLIST)
  message(FATAL_ERROR "ValidateSourceActions.cmake requires RUNNER, CORE and ALLOWLIST")
endif()

execute_process(
  COMMAND "${RUNNER}" --dump "${CORE}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE dump
  ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "cannot inspect core action ownership: ${error}")
endif()

# Actions already implemented as compiled RecurLoop functions.  They are kept
# explicit here so a stale allowlist cannot accidentally re-authorize them.
set(migrated_actions
  "language.ignore"
  "language.ping"
  "source.progress-byte"
  "workspace.pass-byte"
  "workspace.pass-cr"
  "workspace.pass-lf"
  "workspace.pass-tab"
  "workspace.pass-vtab"
  "hex.byte")
foreach(action IN LISTS migrated_actions)
  string(FIND "${dump}" "action \"${action}\"" position)
  if(NOT position EQUAL -1)
    message(FATAL_ERROR "source-owned action '${action}' still appears as a direct host action in final core.rli")
  endif()
endforeach()

file(STRINGS "${ALLOWLIST}" allowed REGEX "^[^#].+")
list(REMOVE_DUPLICATES allowed)
list(SORT allowed)

string(REGEX MATCHALL "action \"[^\"]*\"" action_fields "${dump}")
set(actual)
foreach(field IN LISTS action_fields)
  string(REGEX REPLACE "^action \"([^\"]*)\"$" "\\1" action "${field}")
  if(NOT action STREQUAL "")
    list(APPEND actual "${action}")
  endif()
endforeach()
list(REMOVE_DUPLICATES actual)
list(SORT actual)

foreach(action IN LISTS actual)
  list(FIND allowed "${action}" index)
  if(index EQUAL -1)
    message(FATAL_ERROR "final core.rli references unreviewed host action '${action}'; migrate it to core/actions.rl or explicitly review the host boundary before changing the allowlist")
  endif()
endforeach()
foreach(action IN LISTS allowed)
  list(FIND actual "${action}" index)
  if(index EQUAL -1)
    message(FATAL_ERROR "host action allowlist contains stale entry '${action}'; remove it instead of preserving unused host semantics")
  endif()
endforeach()

string(FIND "${dump}" "action \"fn.bound-action\"" bound_position)
if(bound_position EQUAL -1)
  message(FATAL_ERROR "final core.rli contains no compiled source action bindings")
endif()

list(LENGTH actual host_action_count)
message(STATUS "Source action ownership audit passed; ${host_action_count} direct host actions remain in the reviewed budget")
