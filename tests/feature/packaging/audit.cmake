cmake_minimum_required(VERSION 3.25)
find_program(CC NAMES cc gcc clang REQUIRED)
get_filename_component(root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

# Official LLVM binary metadata is immutable and cheap to validate. This test
# must never download LLVM or build it from source.
set(CMAKE_HOST_SYSTEM_NAME Linux)
set(CMAKE_HOST_SYSTEM_PROCESSOR x86_64)
unset(RECURLOOP_LLVM_ARCHIVE_URL CACHE)
unset(RECURLOOP_LLVM_ARCHIVE_SHA256 CACHE)
include("${root}/cmake/LLVMDistribution.cmake")
recurloop_llvm_archive_metadata(url sha platform_id filename)
if(NOT filename STREQUAL "LLVM-22.1.8-Linux-X64.tar.xz" OR
   NOT platform_id STREQUAL "linux-x86_64" OR
   NOT sha STREQUAL "df0e1ecf16caf3489a272a5eea4eec9b0d82878f6477fa309504f918a0006384")
    message(FATAL_ERROR "Pinned official LLVM Linux x86-64 metadata changed unexpectedly")
endif()
if(NOT url MATCHES "llvmorg-22\\.1\\.8/LLVM-22\\.1\\.8-Linux-X64\\.tar\\.xz$")
    message(FATAL_ERROR "Pinned official LLVM URL is malformed: ${url}")
endif()

set(work "${CMAKE_CURRENT_BINARY_DIR}/package-audit")
file(MAKE_DIRECTORY "${work}/bin" "${work}/lib")
file(WRITE "${work}/xml.c" "int xmlFake(void) { return 0; }\n")
file(WRITE "${work}/main.c" "extern int xmlFake(void); int main(void) { return xmlFake(); }\n")
execute_process(COMMAND "${CC}" -shared -fPIC "${work}/xml.c" -Wl,-soname,libunexpected.so.1
    -o "${work}/lib/libunexpected.so.1" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${CC}" "${work}/main.c" "-L${work}/lib" -l:libunexpected.so.1
    -o "${work}/bin/recurloop" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${CMAKE_COMMAND}" "-DPREFIX=${work}" -P "${root}/cmake/AuditLinuxPackage.cmake"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(result EQUAL 0 OR NOT error MATCHES "Undeclared runtime dependency")
    message(FATAL_ERROR "Audit did not reject an undeclared runtime dependency: ${output}${error}")
endif()
file(REMOVE "${work}/lib/libunexpected.so.1")
file(WRITE "${work}/main.c" "int main(void) { return 0; }\n")
execute_process(COMMAND "${CC}" "${work}/main.c" -o "${work}/bin/recurloop" COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${CMAKE_COMMAND}" "-DPREFIX=${work}" -P "${root}/cmake/AuditLinuxPackage.cmake"
    COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND "${CMAKE_COMMAND}" "-DPREFIX=${work}" -DMAX_GLIBC=2.0
    -P "${root}/cmake/AuditLinuxPackage.cmake"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
if(result EQUAL 0 OR NOT error MATCHES "release baseline")
    message(FATAL_ERROR "Audit did not enforce the ABI ceiling: ${output}${error}")
endif()
file(REMOVE_RECURSE "${work}")
