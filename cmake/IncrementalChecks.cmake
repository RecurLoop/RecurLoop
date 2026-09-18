# Incremental verification is expressed as ordinary CMake/Ninja dependencies.
# Each successful check writes a stamp. Ninja reruns only stamps whose declared
# inputs are newer. There is deliberately no git-diff parsing, name matching,
# timing heuristic, or separate dependency solver here.

set(RECURLOOP_CHECK_DIR "${CMAKE_BINARY_DIR}/check")

file(GLOB_RECURSE RECURLOOP_CHECK_BASE_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/source/utilities/*"
    "${CMAKE_SOURCE_DIR}/include/utilities/*"
    "${CMAKE_SOURCE_DIR}/source/radix/*"
    "${CMAKE_SOURCE_DIR}/include/radix/*"
    "${CMAKE_SOURCE_DIR}/source/lexicon/*"
    "${CMAKE_SOURCE_DIR}/include/lexicon/*"
    "${CMAKE_SOURCE_DIR}/source/context/*"
    "${CMAKE_SOURCE_DIR}/include/context/*")

file(GLOB_RECURSE RECURLOOP_CHECK_RECURLOOP_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/source/recurloop/*"
    "${CMAKE_SOURCE_DIR}/include/recurloop/*")

set(RECURLOOP_CHECK_DEBUGGER_FILES
    "${CMAKE_SOURCE_DIR}/source/recurloop/Debugger.cpp"
    "${CMAKE_SOURCE_DIR}/include/recurloop/Debugger.hpp"
    "${CMAKE_SOURCE_DIR}/source/compiler/DebugInfo.cpp"
    "${CMAKE_SOURCE_DIR}/include/compiler/DebugInfo.hpp")

file(GLOB RECURLOOP_CHECK_ASSEMBLER_FRONTEND_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/source/recurloop/Assembler*"
    "${CMAKE_SOURCE_DIR}/include/recurloop/Assembler*")

set(RECURLOOP_CHECK_LLVM_FILES
    "${CMAKE_SOURCE_DIR}/source/recurloop/LlvmBackend.cpp"
    "${CMAKE_SOURCE_DIR}/source/recurloop/LlvmBackend.hpp"
    "${CMAKE_SOURCE_DIR}/cmake/RecurLoopLLVM.cmake"
    "${CMAKE_SOURCE_DIR}/cmake/PreparePinnedToolchain.cmake")

# Everything in recurloop/ that is not backend/debugger-specific is the normal
# language/runtime surface. New files enter this group automatically.
set(RECURLOOP_CHECK_LANGUAGE_FILES ${RECURLOOP_CHECK_RECURLOOP_FILES})
list(REMOVE_ITEM RECURLOOP_CHECK_LANGUAGE_FILES
    ${RECURLOOP_CHECK_DEBUGGER_FILES}
    ${RECURLOOP_CHECK_ASSEMBLER_FRONTEND_FILES}
    ${RECURLOOP_CHECK_LLVM_FILES})

file(GLOB_RECURSE RECURLOOP_CHECK_COMPILER_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/source/compiler/*"
    "${CMAKE_SOURCE_DIR}/include/compiler/*")

file(GLOB_RECURSE RECURLOOP_CHECK_CORE_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/libraries/recurloop/*.rl"
    "${CMAKE_SOURCE_DIR}/libraries/recurloop/core/*"
    "${CMAKE_SOURCE_DIR}/source/bootstrap/*"
    "${CMAKE_SOURCE_DIR}/include/recurloop/bootstrap/*")

set(RECURLOOP_CHECK_RUNTIME_FILES
    "${CMAKE_SOURCE_DIR}/source/main.cpp"
    "${CMAKE_SOURCE_DIR}/source/runtime/RecurloopRuntime.cpp")

set(RECURLOOP_CHECK_BUILD_FILES
    "${CMAKE_SOURCE_DIR}/CMakeLists.txt"
    "${CMAKE_SOURCE_DIR}/CMakePresets.json"
    "${CMAKE_SOURCE_DIR}/cmake/CoreFingerprint.cmake"
    "${CMAKE_SOURCE_DIR}/cmake/EmbedCoreImage.cmake"
    "${CMAKE_SOURCE_DIR}/cmake/IncrementalChecks.cmake")

set(RECURLOOP_CHECK_COMMON_FILES
    ${RECURLOOP_CHECK_BASE_FILES}
    ${RECURLOOP_CHECK_LANGUAGE_FILES}
    ${RECURLOOP_CHECK_CORE_FILES}
    ${RECURLOOP_CHECK_RUNTIME_FILES}
    ${RECURLOOP_CHECK_BUILD_FILES})

file(GLOB_RECURSE RECURLOOP_CHECK_LANGUAGE_KIT_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/libraries/build/*.rl"
    "${CMAKE_SOURCE_DIR}/libraries/language-kit/*.rl")
file(GLOB_RECURSE RECURLOOP_CHECK_SHELL_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/libraries/shell/*.rl")
file(GLOB_RECURSE RECURLOOP_CHECK_INFERRED_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/libraries/inferred/*.rl")
file(GLOB_RECURSE RECURLOOP_CHECK_HTTP_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/libraries/http/*.rl")

file(GLOB_RECURSE RECURLOOP_CHECK_DEBUGGER_EXAMPLE_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/examples/07-workflows/source-debugger/*")
file(GLOB_RECURSE RECURLOOP_CHECK_DECLARATIVE_EXAMPLE_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/examples/03-phrases-and-syntax/declarative-syntax/*")
file(GLOB_RECURSE RECURLOOP_CHECK_FRIENDLY_CONTEXT_EXAMPLE_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/examples/03-phrases-and-syntax/friendly-context-api/*")
file(GLOB_RECURSE RECURLOOP_CHECK_INDENTATION_EXAMPLE_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/examples/03-phrases-and-syntax/indentation-syntax/*")
file(GLOB_RECURSE RECURLOOP_CHECK_PERSISTENT_EXAMPLE_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/examples/03-phrases-and-syntax/persistent-extensions/*")
file(GLOB_RECURSE RECURLOOP_CHECK_REUSABLE_LANGUAGE_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/examples/07-workflows/reusable-language-image/*")
file(GLOB_RECURSE RECURLOOP_CHECK_REUSABLE_SYNTAX_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/examples/07-workflows/reusable-syntax-image/*")
file(GLOB_RECURSE RECURLOOP_CHECK_SHELL_EXAMPLE_FILES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/examples/07-workflows/shell-language/*")

function(recurloop_add_checked_example name)
    cmake_parse_arguments(PARSE_ARGV 1 ARG "" "" "DEPENDS")

    set(example_dir "${CMAKE_SOURCE_DIR}/examples/${name}")
    if(NOT IS_DIRECTORY "${example_dir}")
        message(FATAL_ERROR "incremental example directory does not exist: ${example_dir}")
    endif()

    file(GLOB_RECURSE example_files CONFIGURE_DEPENDS "${example_dir}/*")
    list(FILTER example_files EXCLUDE REGEX "/README[.]md$")

    string(REPLACE "/" "_" check_name "${name}")
    string(REPLACE "-" "_" check_name "${check_name}")
    set(stamp "${RECURLOOP_CHECK_DIR}/examples/${check_name}.stamp")
    set(work_dir "${RECURLOOP_CHECK_DIR}/work/examples/${check_name}")

    add_custom_command(
        OUTPUT "${stamp}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${RECURLOOP_CHECK_DIR}/examples" "${work_dir}"
        COMMAND "${CMAKE_COMMAND}" -E chdir "${work_dir}"
            "${CMAKE_COMMAND}"
            "-DQUIET_LABEL=example ${name}"
            "-DQUIET_PROGRAM=${CMAKE_SOURCE_DIR}/tools/examples.sh"
            "-DQUIET_ARGC=3"
            "-DQUIET_ARG_0=run"
            "-DQUIET_ARG_1=$<TARGET_FILE:Recurloop>"
            "-DQUIET_ARG_2=${name}"
            -P "${CMAKE_SOURCE_DIR}/cmake/RunQuiet.cmake"
        COMMAND "${CMAKE_COMMAND}" -E touch "${stamp}"
        DEPENDS ${example_files} ${ARG_DEPENDS}
        COMMENT "[check][example] ${name}"
        VERBATIM
        USES_TERMINAL)

    set_property(GLOBAL APPEND PROPERTY RECURLOOP_CHECK_EXAMPLE_OUTPUTS "${stamp}")
endfunction()

function(recurloop_add_checked_examples_in category)
    cmake_parse_arguments(PARSE_ARGV 1 ARG "" "" "DEPENDS")
    file(GLOB_RECURSE mains CONFIGURE_DEPENDS
        "${CMAKE_SOURCE_DIR}/examples/${category}/main.rl")
    foreach(main IN LISTS mains)
        get_filename_component(dir "${main}" DIRECTORY)
        file(RELATIVE_PATH name "${CMAKE_SOURCE_DIR}/examples" "${dir}")
        recurloop_add_checked_example("${name}" DEPENDS ${ARG_DEPENDS})
    endforeach()
endfunction()

function(recurloop_define_incremental_example_checks)
    # Core examples. Native-output examples additionally depend on the compiler,
    # assembler frontend and LLVM backend; the remaining examples use the normal
    # language/runtime surface.
    foreach(category IN ITEMS
            01-getting-started
            02-functions
            03-phrases-and-syntax
            05-applications
            06-benchmarks)
        recurloop_add_checked_examples_in("${category}"
            DEPENDS ${RECURLOOP_CHECK_COMMON_FILES})
    endforeach()
    recurloop_add_checked_examples_in(04-native-output
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_COMPILER_FILES}
            ${RECURLOOP_CHECK_ASSEMBLER_FRONTEND_FILES}
            ${RECURLOOP_CHECK_LLVM_FILES})

    # Workflows explicitly declare the standard-library/backend inputs they use.
    recurloop_add_checked_example(07-workflows/reusable-language-image
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES})
    recurloop_add_checked_example(07-workflows/reusable-syntax-image
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES})
    recurloop_add_checked_example(07-workflows/language-kit
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_LANGUAGE_KIT_FILES}
            ${RECURLOOP_CHECK_INFERRED_FILES})
    recurloop_add_checked_example(07-workflows/shell-language
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_LANGUAGE_KIT_FILES}
            ${RECURLOOP_CHECK_SHELL_FILES}
            ${RECURLOOP_CHECK_COMPILER_FILES}
            ${RECURLOOP_CHECK_ASSEMBLER_FRONTEND_FILES}
            ${RECURLOOP_CHECK_LLVM_FILES})
    recurloop_add_checked_example(07-workflows/inferred-language
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_LANGUAGE_KIT_FILES}
            ${RECURLOOP_CHECK_INFERRED_FILES})
    recurloop_add_checked_example(07-workflows/http-language
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_LANGUAGE_KIT_FILES}
            ${RECURLOOP_CHECK_HTTP_FILES}
            ${RECURLOOP_CHECK_COMPILER_FILES}
            ${RECURLOOP_CHECK_ASSEMBLER_FRONTEND_FILES}
            ${RECURLOOP_CHECK_LLVM_FILES})
    recurloop_add_checked_example(07-workflows/source-debugger
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_DEBUGGER_FILES})
    foreach(workflow IN ITEMS amber-language prolog-language haskell-language erlang-language)
        recurloop_add_checked_example("07-workflows/${workflow}"
            DEPENDS ${RECURLOOP_CHECK_COMMON_FILES})
    endforeach()

    get_property(example_outputs GLOBAL PROPERTY RECURLOOP_CHECK_EXAMPLE_OUTPUTS)
    add_custom_target(RecurloopCheckExamples DEPENDS ${example_outputs})
    set_target_properties(RecurloopCheckExamples PROPERTIES FOLDER "Verification")

    add_custom_target(RecurloopCheck)
    add_dependencies(RecurloopCheck
        RecurloopCheckUnit
        RecurloopCheckFeature
        RecurloopCheckExamples)
    set_target_properties(RecurloopCheck PROPERTIES FOLDER "Verification")
endfunction()
