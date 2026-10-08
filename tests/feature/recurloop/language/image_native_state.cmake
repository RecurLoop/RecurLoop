set(kit "${CMAKE_CURRENT_BINARY_DIR}/native-state-kit.rli")
set(clean "${CMAKE_CURRENT_BINARY_DIR}/native-state-clean.rli")
set(rejected "${CMAKE_CURRENT_BINARY_DIR}/native-state-rejected.rli")
file(REMOVE "${kit}" "${clean}" "${rejected}")
get_filename_component(root "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)

function(run_ok)
    execute_process(COMMAND "${PROGRAM}" ${ARGN}
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT rc EQUAL 0 OR NOT err STREQUAL "")
        message(FATAL_ERROR "Native-state image check failed (${rc}):\n${out}\n${err}")
    endif()
endfunction()

run_ok(--file "${root}/libraries/language-kit/library.rl" -- "${kit}")
set(setup [=[
let owned_native_cleanup = phrase {
    type = <phrase-types:elaborate>
    permanent = true
    action = fn (state:Context*, called:Phrase*) -> void {
        let slot = context:phrase:address(state, called)
        var raw:i64 = 0
        if !slot || !context:phrase:read(state, slot, 0, cast(u8*, &raw), 8) {
            context:diagnostic:error(state, "owned native cleanup could not read its slot")
            return
        }
        raw = 0
        if !context:phrase:write(state, slot, 0, cast(u8*, &raw), 8) {
            context:diagnostic:error(state, "owned native cleanup could not clear its slot")
        }
    }
}
let setup_native_state = fn (state:Context*, called:Phrase*) -> void {
    LanguageKit:state_set(state, "portable_counter", 42)
    LanguageKit:publish_text(state, "published_text", "owned text")
    if !LanguageKit:state_pointer_set(state, "native_state", 1234) {
        context:diagnostic:error(state, "could not store native pointer")
    }
    let cleanup = context:phrase:find(state, "owned_native_cleanup")
    if !LanguageKit:state_pointer_set_owned(state, "owned_native_state", 5678, cleanup) {
        context:diagnostic:error(state, "could not store owned native pointer")
    }
}
setup_native_state
]=])
execute_process(COMMAND "${PROGRAM}" --import "${kit}" --string
    "${setup}\nengine export \"${rejected}\"\n"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(rc EQUAL 0 OR NOT err MATCHES "non-zero native pointer" OR EXISTS "${rejected}")
    message(FATAL_ERROR "Export must reject live native state before writing a file:\n${out}\n${err}")
endif()

set(clear [=[
let clear_native_state = fn (state:Context*, called:Phrase*) -> void {
    LanguageKit:state_set(state, "native_state", 0)
    let kit = context:phrase:find(state, "LanguageKit")
    let owner = context:phrase:find:exact(state, kit, "ProcessPointers")
    let owned = context:phrase:find:exact(state, owner, "owned_native_state")
    if !owned {
        context:diagnostic:error(state, "owned native pointer slot is missing")
        return
    }
    context:phrase:dispatch(state, owned)
    if LanguageKit:state_get(state, "owned_native_state") != 0 {
        context:diagnostic:error(state, "owned native cleanup did not clear its slot")
    }
    context:phrase:dispatch(state, LanguageKit:state_pointer_find(state, "__languagekit_lifetime_root"))
    context:phrase:dispatch(state, LanguageKit:state_pointer_find(state, "__languagekit_binding_head"))
    if LanguageKit:state_get(state, "__languagekit_lifetime_root") ||
       LanguageKit:state_get(state, "__languagekit_lifetime_current") ||
       LanguageKit:state_get(state, "__languagekit_lifetime_controls") ||
       LanguageKit:state_get(state, "__languagekit_binding_head") {
        context:diagnostic:error(state, "LanguageKit cleanup left live native pointers")
    }
}
clear_native_state
]=])
run_ok(--import "${kit}" --string "${setup}\n${clear}\nengine export \"${clean}\"\n")
set(check [=[
let check_native_state = fn (state:Context*, called:Phrase*) -> void {
    if LanguageKit:state_get(state, "native_state") != 0 {
        context:diagnostic:error(state, "native pointer survived import")
    }
    if LanguageKit:state_get(state, "portable_counter") != 42 {
        context:diagnostic:error(state, "portable counter did not survive import")
    }
    // Cleared ownership slots and their finalizers survive export/import.
    LanguageKit:publish_integer(state, "fresh_value", 7)
    context:phrase:dispatch(state, LanguageKit:state_pointer_find(state, "__languagekit_binding_head"))
    context:phrase:dispatch(state, LanguageKit:state_pointer_find(state, "__languagekit_lifetime_root"))
    if LanguageKit:state_get(state, "__languagekit_lifetime_live_objects") != 0 ||
       LanguageKit:state_get(state, "__languagekit_lifetime_live_refs") != 0 {
        context:diagnostic:error(state, "Imported LanguageKit finalizers did not release fresh state")
    }
}
check_native_state
]=])
run_ok(--import "${clean}" --string "${check}")
file(REMOVE "${kit}" "${clean}")
