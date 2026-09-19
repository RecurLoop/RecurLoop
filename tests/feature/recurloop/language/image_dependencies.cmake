set(directory "${CMAKE_CURRENT_BINARY_DIR}/image-dependencies")
set(base "${directory}/base.rli")
set(base_copy "${directory}/base-copy.rli")
set(child "${directory}/child.rli")
set(child_again "${directory}/child-again.rli")
set(standalone "${directory}/standalone.rli")
file(REMOVE_RECURSE "${directory}")
file(MAKE_DIRECTORY "${directory}")

function(run_ok)
    execute_process(COMMAND "${PROGRAM}" ${ARGN}
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT rc EQUAL 0 OR NOT err STREQUAL "")
        message(FATAL_ERROR "Image-dependency check failed (${rc}):\n${out}\n${err}")
    endif()
endfunction()

set(base_source "let base_dependency = <debug:ping>\nengine export \"${base}\"\n")
run_ok(--string "${base_source}")

set(child_source "let child_dependency = <debug:ping>\nengine export \"${child}\"\n")
run_ok(--import "${base}" --string "${child_source}")
set(child_again_source "let child_dependency = <debug:ping>\nengine export \"${child_again}\"\n")
run_ok(--import "${base}" --string "${child_again_source}")
file(SHA256 "${child}" child_hash)
file(SHA256 "${child_again}" child_again_hash)
if(NOT child_hash STREQUAL child_again_hash)
    message(FATAL_ERROR "Equivalent dependency images are not deterministic")
endif()

set(check_source "base_dependency\nchild_dependency\n")
execute_process(COMMAND "${PROGRAM}" --import "${child}" --string "${check_source}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR NOT out STREQUAL "pong\npong\n")
    message(FATAL_ERROR "Transitive image import failed (${rc}):\n${out}\n${err}")
endif()

set(runtime_import_source
    "engine import \"${base}\"\nlet runtime_dependency = <debug:ping>\nengine export \"${standalone}\"\n")
run_ok(--string "${runtime_import_source}")

file(COPY_FILE "${base}" "${base_copy}")
file(REMOVE "${base}")

execute_process(COMMAND "${PROGRAM}" --import "${standalone}" --string "base_dependency\nruntime_dependency\n"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR NOT out STREQUAL "pong\npong\n")
    message(FATAL_ERROR "Full export after a runtime import was not standalone (${rc}):\n${out}\n${err}")
endif()
execute_process(COMMAND "${PROGRAM}" --import "${child}" --string "print 1\n"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(rc EQUAL 0 OR NOT err MATCHES "cannot open engine image for reading")
    message(FATAL_ERROR "Missing image dependency was not reported:\n${out}\n${err}")
endif()

execute_process(COMMAND "${PROGRAM}" --import "${base_copy}" --import "${child}" --string "${check_source}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR NOT out STREQUAL "pong\npong\n")
    message(FATAL_ERROR "Preloaded equivalent dependency was not reused (${rc}):\n${out}\n${err}")
endif()

file(REMOVE_RECURSE "${directory}")
