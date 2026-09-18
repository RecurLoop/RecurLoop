option(ENABLE_TESTS_BENCHMARK "Build benchmarks" OFF)
option(ENABLE_TESTS_FEATURE "Register feature tests" ON)
option(ENABLE_TESTS_UNIT "Build unit tests" ON)

include(FetchContent)

if(ENABLE_TESTS_BENCHMARK)
    set(BENCHMARK_ENABLE_TESTING OFF)
    recurloop_reuse_dependency_source(benchmark)
    FetchContent_Declare(benchmark
        GIT_REPOSITORY https://github.com/google/benchmark.git
        GIT_TAG v1.9.1
        GIT_SHALLOW TRUE
        GIT_PROGRESS FALSE
        BINARY_DIR "${CMAKE_BINARY_DIR}/dependencies/benchmark"
        SYSTEM)
    FetchContent_MakeAvailable(benchmark)

    add_executable(RadixBenchmark benchmark/radix/Radix.cpp)
    target_link_libraries(RadixBenchmark PRIVATE RadixLib benchmark::benchmark)
    target_include_directories(RadixBenchmark PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
    set_target_properties(RadixBenchmark PROPERTIES
        FOLDER "Benchmarks"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests/benchmark")
    add_custom_target(RecurloopBenchmarks DEPENDS RadixBenchmark)
endif()

if(ENABLE_TESTS_UNIT)
    set(BUILD_GMOCK OFF)
    set(INSTALL_GTEST OFF)
    recurloop_reuse_dependency_source(googletest)
    FetchContent_Declare(googletest
        GIT_REPOSITORY https://github.com/google/googletest.git
        GIT_TAG v1.15.2
        GIT_SHALLOW TRUE
        GIT_PROGRESS FALSE
        BINARY_DIR "${CMAKE_BINARY_DIR}/dependencies/googletest"
        SYSTEM)
    FetchContent_MakeAvailable(googletest)

    add_custom_target(RecurloopUnitTests)
    set_target_properties(RecurloopUnitTests PROPERTIES FOLDER "Verification")

    set(recurloop_unit_check_outputs)

    function(recurloop_add_unit_tests directory library)
        file(GLOB_RECURSE test_sources CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/unit/${directory}/*_test.cpp")
        foreach(test_source IN LISTS test_sources)
            file(RELATIVE_PATH test_name "${CMAKE_CURRENT_SOURCE_DIR}/unit" "${test_source}")
            string(REPLACE "/" "_" test_name "${test_name}")
            string(REPLACE "_test.cpp" "" test_name "${test_name}")
            set(target "unit_test_${test_name}")

            add_executable(${target} "${test_source}")
            if(library STREQUAL "RecurloopLib")
                target_link_libraries(${target} PRIVATE gtest_main RecurloopRuntimeLib)
            else()
                target_link_libraries(${target} PRIVATE gtest_main ${library})
            endif()
            target_include_directories(${target} PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
            if(RECURLOOP_ENABLE_LLVM AND library STREQUAL "RecurloopLib")
                target_compile_definitions(${target} PRIVATE RECURLOOP_ENABLE_LLVM=1)
            endif()
            set_target_properties(${target} PROPERTIES
                FOLDER "Tests"
                RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests/unit")
            add_dependencies(RecurloopUnitTests ${target})

            add_test(NAME "[Unit] ${test_name}" COMMAND "$<TARGET_FILE:${target}>")
            set_tests_properties("[Unit] ${test_name}" PROPERTIES
                WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
                LABELS "unit")

            # The executable target is the dependency graph. If any source or
            # transitive header/library makes Ninja relink this test, the target
            # file becomes newer than the stamp and this unit test runs once.
            set(stamp "${RECURLOOP_CHECK_DIR}/unit/${test_name}.stamp")
            set(work_dir "${RECURLOOP_CHECK_DIR}/work/unit/${test_name}")
            add_custom_command(
                OUTPUT "${stamp}"
                COMMAND "${CMAKE_COMMAND}" -E make_directory "${RECURLOOP_CHECK_DIR}/unit" "${work_dir}"
                COMMAND "${CMAKE_COMMAND}" -E chdir "${work_dir}"
                    "${CMAKE_COMMAND}"
                    "-DQUIET_LABEL=unit ${test_name}"
                    "-DQUIET_PROGRAM=$<TARGET_FILE:${target}>"
                    "-DQUIET_ARGC=1"
                    "-DQUIET_ARG_0=--gtest_brief=1"
                    -P "${CMAKE_SOURCE_DIR}/cmake/RunQuiet.cmake"
                COMMAND "${CMAKE_COMMAND}" -E touch "${stamp}"
                DEPENDS ${target}
                COMMENT "[check][unit] ${test_name}"
                VERBATIM)
            list(APPEND recurloop_unit_check_outputs "${stamp}")
        endforeach()

        set(recurloop_unit_check_outputs "${recurloop_unit_check_outputs}" PARENT_SCOPE)
    endfunction()

    recurloop_add_unit_tests(radix RadixLib)
    recurloop_add_unit_tests(recurloop RecurloopLib)

    add_custom_target(RecurloopCheckUnit DEPENDS ${recurloop_unit_check_outputs})
    set_target_properties(RecurloopCheckUnit PROPERTIES FOLDER "Verification")
else()
    add_custom_target(RecurloopCheckUnit)
    set_target_properties(RecurloopCheckUnit PROPERTIES FOLDER "Verification")
endif()

if(ENABLE_TESTS_FEATURE)
    set(recurloop_feature_check_outputs)

    function(recurloop_add_feature_test relative_path)
        cmake_parse_arguments(PARSE_ARGV 1 ARG "LLVM" "" "DEPENDS")

        if(ARG_LLVM)
            set(feature_test "${CMAKE_CURRENT_SOURCE_DIR}/${relative_path}")
            set(test_name "recurloop_llvm_output")
        else()
            set(feature_test "${CMAKE_CURRENT_SOURCE_DIR}/feature/${relative_path}")
            file(RELATIVE_PATH test_name "${CMAKE_CURRENT_SOURCE_DIR}/feature" "${feature_test}")
            string(REPLACE "/" "_" test_name "${test_name}")
            string(REPLACE ".cmake" "" test_name "${test_name}")
        endif()
        if(NOT EXISTS "${feature_test}")
            message(FATAL_ERROR "feature test does not exist: ${feature_test}")
        endif()

        set(ctest_name "[Feature] ${test_name}")

        if(ARG_LLVM)
            if(NOT RECURLOOP_ENABLE_LLVM)
                return()
            endif()
            add_test(NAME "${ctest_name}"
                COMMAND "${CMAKE_COMMAND}"
                    "-DPROGRAM=$<TARGET_FILE:Recurloop>"
                    "-DREADELF=${CMAKE_READELF}"
                    "-DTARGET_TRIPLE=${RECURLOOP_LLVM_TARGET_TRIPLE}"
                    -P "${feature_test}")
            set_tests_properties("${ctest_name}" PROPERTIES LABELS "feature;llvm")
        else()
            add_test(NAME "${ctest_name}"
                COMMAND "${CMAKE_COMMAND}"
                    "-DPROGRAM=$<TARGET_FILE:Recurloop>"
                    "-DCORE_IMAGE=${RECURLOOP_CORE_IMAGE}"
                    "-DLLVM_BACKEND=${RECURLOOP_ENABLE_LLVM}"
                    -P "${feature_test}")
            set_tests_properties("${ctest_name}" PROPERTIES LABELS "feature")
        endif()

        set(stamp "${RECURLOOP_CHECK_DIR}/feature/${test_name}.stamp")
        set(work_dir "${RECURLOOP_CHECK_DIR}/work/feature/${test_name}")
        if(ARG_LLVM)
            add_custom_command(
                OUTPUT "${stamp}"
                COMMAND "${CMAKE_COMMAND}" -E make_directory "${RECURLOOP_CHECK_DIR}/feature" "${work_dir}"
                COMMAND "${CMAKE_COMMAND}" -E chdir "${work_dir}"
                    "${CMAKE_COMMAND}"
                    "-DQUIET_LABEL=feature ${test_name}"
                    "-DQUIET_PROGRAM=${CMAKE_COMMAND}"
                    "-DQUIET_ARGC=5"
                    "-DQUIET_ARG_0=-DPROGRAM=$<TARGET_FILE:Recurloop>"
                    "-DQUIET_ARG_1=-DREADELF=${CMAKE_READELF}"
                    "-DQUIET_ARG_2=-DTARGET_TRIPLE=${RECURLOOP_LLVM_TARGET_TRIPLE}"
                    "-DQUIET_ARG_3=-P"
                    "-DQUIET_ARG_4=${feature_test}"
                    -P "${CMAKE_SOURCE_DIR}/cmake/RunQuiet.cmake"
                COMMAND "${CMAKE_COMMAND}" -E touch "${stamp}"
                DEPENDS "${feature_test}" ${ARG_DEPENDS}
                COMMENT "[check][feature] ${test_name}"
                VERBATIM
                USES_TERMINAL)
        else()
            add_custom_command(
                OUTPUT "${stamp}"
                COMMAND "${CMAKE_COMMAND}" -E make_directory "${RECURLOOP_CHECK_DIR}/feature" "${work_dir}"
                COMMAND "${CMAKE_COMMAND}" -E chdir "${work_dir}"
                    "${CMAKE_COMMAND}"
                    "-DQUIET_LABEL=feature ${test_name}"
                    "-DQUIET_PROGRAM=${CMAKE_COMMAND}"
                    "-DQUIET_ARGC=5"
                    "-DQUIET_ARG_0=-DPROGRAM=$<TARGET_FILE:Recurloop>"
                    "-DQUIET_ARG_1=-DCORE_IMAGE=${RECURLOOP_CORE_IMAGE}"
                    "-DQUIET_ARG_2=-DLLVM_BACKEND=${RECURLOOP_ENABLE_LLVM}"
                    "-DQUIET_ARG_3=-P"
                    "-DQUIET_ARG_4=${feature_test}"
                    -P "${CMAKE_SOURCE_DIR}/cmake/RunQuiet.cmake"
                COMMAND "${CMAKE_COMMAND}" -E touch "${stamp}"
                DEPENDS "${feature_test}" ${ARG_DEPENDS}
                COMMENT "[check][feature] ${test_name}"
                VERBATIM
                USES_TERMINAL)
        endif()

        list(APPEND recurloop_feature_check_outputs "${stamp}")
        set(recurloop_feature_check_outputs "${recurloop_feature_check_outputs}" PARENT_SCOPE)
    endfunction()

    # CLI behavior depends on the normal runtime/language surface.
    recurloop_add_feature_test(recurloop/cli/error_locations.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/cli/_error_location_inner.rl"
            "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/cli/_error_location_outer.rl")
    recurloop_add_feature_test(recurloop/cli/file.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/cli/_input_file.rl")
    foreach(test IN ITEMS help string version)
        recurloop_add_feature_test("recurloop/cli/${test}.cmake"
            DEPENDS ${RECURLOOP_CHECK_COMMON_FILES})
    endforeach()

    # Language integration tests declare their concrete implementation/input
    # dependencies. Selection is therefore a normal Ninja mtime/DEPENDS decision.
    recurloop_add_feature_test(recurloop/language/compiler_schema_source_owned.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES} ${RECURLOOP_CHECK_COMPILER_FILES})
    recurloop_add_feature_test(recurloop/language/core_negative_fixed_point.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES})
    recurloop_add_feature_test(recurloop/language/core_runtime.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            "${CMAKE_SOURCE_DIR}/examples/01-getting-started/hello-world/main.rl")
    recurloop_add_feature_test(recurloop/language/core_work_collections.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES})
    recurloop_add_feature_test(recurloop/language/debug_stats.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            "${CMAKE_SOURCE_DIR}/examples/03-phrases-and-syntax/context-actions/main.rl")
    recurloop_add_feature_test(recurloop/language/debugger.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_DEBUGGER_FILES}
            ${RECURLOOP_CHECK_DEBUGGER_EXAMPLE_FILES}
            "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/language/_debugger_commands.txt"
            "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/language/_debugger_continue.txt")
    recurloop_add_feature_test(recurloop/language/debugger_executable.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_DEBUGGER_FILES}
            ${RECURLOOP_CHECK_COMPILER_FILES}
            ${RECURLOOP_CHECK_ASSEMBLER_FRONTEND_FILES}
            ${RECURLOOP_CHECK_LLVM_FILES}
            ${RECURLOOP_CHECK_DEBUGGER_EXAMPLE_FILES}
            "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/language/_debugger_executable_commands.txt")
    recurloop_add_feature_test(recurloop/language/declarative_syntax.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES} ${RECURLOOP_CHECK_DECLARATIVE_EXAMPLE_FILES})
    recurloop_add_feature_test(recurloop/language/everyday.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/language/_everyday.rl")
    recurloop_add_feature_test(recurloop/language/friendly_context_api.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES} ${RECURLOOP_CHECK_FRIENDLY_CONTEXT_EXAMPLE_FILES})
    recurloop_add_feature_test(recurloop/language/indentation_functions.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES} ${RECURLOOP_CHECK_INDENTATION_EXAMPLE_FILES})
    recurloop_add_feature_test(recurloop/language/lexicon_merge.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/language/_lexicon_merge.rl")
    recurloop_add_feature_test(recurloop/language/persistent_extensions.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES} ${RECURLOOP_CHECK_PERSISTENT_EXAMPLE_FILES})
    recurloop_add_feature_test(recurloop/language/phrase_aliases.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/language/_phrase_aliases.rl")
    recurloop_add_feature_test(recurloop/language/phrase_language_cold_start.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES} ${RECURLOOP_CHECK_REUSABLE_LANGUAGE_FILES})
    recurloop_add_feature_test(recurloop/language/phrase_syntax_cold_start.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES} ${RECURLOOP_CHECK_REUSABLE_SYNTAX_FILES})
    recurloop_add_feature_test(recurloop/language/shell_library.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_LANGUAGE_KIT_FILES}
            ${RECURLOOP_CHECK_SHELL_FILES}
            ${RECURLOOP_CHECK_SHELL_EXAMPLE_FILES}
            ${RECURLOOP_CHECK_COMPILER_FILES}
            ${RECURLOOP_CHECK_ASSEMBLER_FRONTEND_FILES}
            ${RECURLOOP_CHECK_LLVM_FILES})
    recurloop_add_feature_test(recurloop/language/showcase.cmake
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_COMPILER_FILES}
            ${RECURLOOP_CHECK_ASSEMBLER_FRONTEND_FILES}
            ${RECURLOOP_CHECK_LLVM_FILES})
    recurloop_add_feature_test(recurloop/language/source_owned_actions.cmake
        DEPENDS ${RECURLOOP_CHECK_COMMON_FILES} ${RECURLOOP_CHECK_COMPILER_FILES})
    recurloop_add_feature_test(llvm/output.cmake LLVM
        DEPENDS
            ${RECURLOOP_CHECK_COMMON_FILES}
            ${RECURLOOP_CHECK_COMPILER_FILES}
            ${RECURLOOP_CHECK_ASSEMBLER_FRONTEND_FILES}
            ${RECURLOOP_CHECK_LLVM_FILES})

    add_custom_target(RecurloopCheckFeature DEPENDS ${recurloop_feature_check_outputs})
    set_target_properties(RecurloopCheckFeature PROPERTIES FOLDER "Verification")
else()
    add_custom_target(RecurloopCheckFeature)
    set_target_properties(RecurloopCheckFeature PROPERTIES FOLDER "Verification")
endif()
