option(ENABLE_TESTS_BENCHMARK "Build benchmarks" ON)
option(ENABLE_TESTS_FEATURE "Register feature tests" ON)
option(ENABLE_TESTS_UNIT "Build unit tests" ON)

include(FetchContent)

if(ENABLE_TESTS_BENCHMARK)
    set(BENCHMARK_ENABLE_TESTING OFF)
    FetchContent_Declare(benchmark
        GIT_REPOSITORY https://github.com/google/benchmark.git
        GIT_TAG v1.9.1
        BINARY_DIR "${CMAKE_BINARY_DIR}/dependencies/benchmark"
        SYSTEM)
    FetchContent_MakeAvailable(benchmark)

    add_executable(RadixBenchmark benchmark/radix/Radix.cpp)
    target_link_libraries(RadixBenchmark PRIVATE RadixLib benchmark::benchmark)
    target_include_directories(RadixBenchmark PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
    set_target_properties(RadixBenchmark PROPERTIES
        FOLDER "Benchmarks"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests/benchmark")
endif()

if(ENABLE_TESTS_UNIT)
    set(BUILD_GMOCK OFF)
    set(INSTALL_GTEST OFF)
    FetchContent_Declare(googletest
        GIT_REPOSITORY https://github.com/google/googletest.git
        GIT_TAG v1.15.2
        BINARY_DIR "${CMAKE_BINARY_DIR}/dependencies/googletest"
        SYSTEM)
    FetchContent_MakeAvailable(googletest)

    function(recurloop_add_unit_tests directory library)
        file(GLOB_RECURSE test_sources CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/unit/${directory}/*_test.cpp")
        foreach(test_source IN LISTS test_sources)
            file(RELATIVE_PATH test_name "${CMAKE_CURRENT_SOURCE_DIR}/unit" "${test_source}")
            string(REPLACE "/" "_" test_name "${test_name}")
            string(REPLACE "_test.cpp" "" test_name "${test_name}")
            set(target "unit_test_${test_name}")

            add_executable(${target} "${test_source}")
            target_link_libraries(${target} PRIVATE gtest_main ${library})
            target_include_directories(${target} PRIVATE "${RECURLOOP_INCLUDE_DIR}" "${RECURLOOP_SOURCE_DIR}")
            if(RECURLOOP_ENABLE_LLVM AND library STREQUAL "RecurloopLib")
                target_compile_definitions(${target} PRIVATE RECURLOOP_ENABLE_LLVM=1)
            endif()
            set_target_properties(${target} PROPERTIES
                FOLDER "Tests"
                RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests/unit")
            add_test(NAME "[Unit] ${test_name}" COMMAND "$<TARGET_FILE:${target}>")
            set_tests_properties("[Unit] ${test_name}" PROPERTIES WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
        endforeach()
    endfunction()

    recurloop_add_unit_tests(radix RadixLib)
    recurloop_add_unit_tests(recurloop RecurloopLib)
endif()

if(ENABLE_TESTS_FEATURE)
    file(GLOB_RECURSE feature_tests CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/feature/recurloop/*.cmake")
    foreach(feature_test IN LISTS feature_tests)
        file(RELATIVE_PATH test_name "${CMAKE_CURRENT_SOURCE_DIR}/feature" "${feature_test}")
        string(REPLACE "/" "_" test_name "${test_name}")
        string(REPLACE ".cmake" "" test_name "${test_name}")
        add_test(NAME "[Feature] ${test_name}"
            COMMAND "${CMAKE_COMMAND}"
                "-DPROGRAM=$<TARGET_FILE:Recurloop>"
                "-DLLVM_BACKEND=${RECURLOOP_ENABLE_LLVM}"
                -P "${feature_test}")
    endforeach()

    if(RECURLOOP_ENABLE_LLVM)
        add_test(NAME "[Feature] recurloop_llvm_output"
            COMMAND "${CMAKE_COMMAND}"
                "-DPROGRAM=$<TARGET_FILE:Recurloop>"
                "-DREADELF=${CMAKE_READELF}"
                "-DTARGET_TRIPLE=${RECURLOOP_LLVM_TARGET_TRIPLE}"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/llvm/output.cmake")
    endif()
endif()
