get_filename_component(binary_dir "${PROGRAM}" DIRECTORY)
get_filename_component(build_dir "${binary_dir}" DIRECTORY)
set(libraries "${build_dir}/libraries")
set(work "${CMAKE_CURRENT_BINARY_DIR}/library-import-tests")
file(MAKE_DIRECTORY "${work}")
file(WRITE "${work}/recurloop.project.rl" "")

function(run_ok)
    execute_process(COMMAND "${PROGRAM}" --library-path "${libraries}" ${ARGV}
        WORKING_DIRECTORY "${work}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR out MATCHES "(^|\n)E\t")
        message(FATAL_ERROR "Library import failed (${rc}): ${ARGV}\n${out}${err}")
    endif()
endfunction()

function(inspect_project entry source)
    file(READ "${source}" text)
    string(HEX "${source}" path_hex)
    string(HEX "${text}" source_hex)
    file(WRITE "${work}/requests.txt"
        ":cache\n:load-file\t${entry}\n:inspect\t${path_hex}\t${source_hex}\n:quit\n")
    execute_process(COMMAND "${PROGRAM}" --library-path "${libraries}" --library project ${ARGN}
        --project-cache "${work}/cache" --serve
        INPUT_FILE "${work}/requests.txt" WORKING_DIRECTORY "${work}"
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT rc EQUAL 0 OR NOT err STREQUAL "" OR out MATCHES "(^|\n)E\t" OR
       out MATCHES "status=[1-9]" OR NOT out MATCHES "(^|\n)S\t")
        message(FATAL_ERROR "Project library inspection failed (${rc}): ${out}${err}")
    endif()
endfunction()

# The window image declares its Vulkan dependency. Both orders and repeated
# imports preserve the same public native signatures, including pointer types.
set(check [=[
let binding_window = fn (count:u32*) -> u8** { return glfwGetRequiredInstanceExtensions(count) }
let binding_timer = fn () -> u64 { return glfwGetTimerValue() }
let binding_clear = fn (command:u8*, attachments:u8*, rects:u8*) -> void {
    vkCmdClearAttachments(command, 1, attachments, 1, rects)
}
assert 6 * 7 == 42
]=])
run_ok(--string "import window\nimport vulkan\nimport window\n${check}")
run_ok(--string "import vulkan\nimport window\n${check}")
run_ok(--library window --string "${check}")
run_ok(--string "import \"language-kit\" // comment\nassert 42 == 42")
file(WRITE "${work}/import.rl" "import window\nimport vulkan\n${check}")
file(WRITE "${work}/recurloop.project.rl" "include \"import.rl\"\n")
inspect_project("${work}/recurloop.project.rl" "${work}/import.rl")

# Prove source and project-session imports retain explicit CLI search paths;
# this alias cannot be found through the executable's default library directory.
set(custom "${work}/custom libraries")
file(MAKE_DIRECTORY "${custom}")
file(COPY "${libraries}/language-kit.rli" "${libraries}/vulkan.rli" DESTINATION "${custom}")
configure_file("${libraries}/window.rli" "${custom}/custom-window.rli" COPYONLY)
run_ok(--library-path "${custom}" --string "import custom-window\n${check}")
file(WRITE "${work}/recurloop.project.rl" "import custom-window\n${check}\ntarget check { assert 42 == 42 }\n")
run_ok(--library-path "${custom}" --project "${work}/recurloop.project.rl" --target check)
inspect_project("${work}/recurloop.project.rl" "${work}/recurloop.project.rl" --library-path "${custom}")

execute_process(COMMAND "${PROGRAM}" --library-path "${libraries}" --string "import missing_library_for_test"
    WORKING_DIRECTORY "${work}" RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(rc EQUAL 0 OR NOT err MATCHES "library image.*was not found" OR NOT err MATCHES "${libraries}")
    message(FATAL_ERROR "Missing library must report the searched paths: ${out}${err}")
endif()
file(REMOVE_RECURSE "${work}")
