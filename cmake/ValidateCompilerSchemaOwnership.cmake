if(NOT DEFINED ROOT)
    message(FATAL_ERROR "ValidateCompilerSchemaOwnership.cmake requires -DROOT=<repository-root>")
endif()

set(_files
    "${ROOT}/source/compiler/LanguageState.cpp"
    "${ROOT}/source/compiler/TypeSystem.cpp")

# These are physical lexicon keys owned by libraries/recurloop/core/compiler.rl.
# Production compiler code must address them through RegistryRole/SlotRole tags,
# never by spelling their source-owned keys.
set(_forbidden
    "\\0compiler-language"
    "calling-conventions"
    "function-sources"
    "module-selections"
    "link-objects"
    "link-archives"
    "link-paths"
    "shared-libraries"
    "abi-kinds"
    "automatic-modules"
    "embed-language"
    "selection-generation"
    "link-sequence"
    "link-generation"
    "module-entry"
    "next-id"
    "by-id")

foreach(_file IN LISTS _files)
    if(NOT EXISTS "${_file}")
        message(FATAL_ERROR "Compiler schema ownership audit cannot find ${_file}")
    endif()
    file(READ "${_file}" _text)
    foreach(_literal IN LISTS _forbidden)
        string(FIND "${_text}" "${_literal}" _position)
        if(NOT _position EQUAL -1)
            message(FATAL_ERROR
                "Production compiler source ${_file} contains source-owned registry key '${_literal}'. "
                "Use compiler::RegistrySchema semantic roles instead; physical keys belong to core/compiler.rl.")
        endif()
    endforeach()
endforeach()

message(STATUS "Compiler registry schema ownership audit passed")
