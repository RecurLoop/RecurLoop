if(NOT DEFINED ROOT)
  message(FATAL_ERROR "ValidateFinalHostBoundary.cmake requires -DROOT=<repository-root>")
endif()

file(GLOB_RECURSE production_cpp "${ROOT}/source/*.cpp" "${ROOT}/source/*.hpp" "${ROOT}/include/*.hpp")
foreach(path IN LISTS production_cpp)
  file(READ "${path}" content)
  string(FIND "${content}" "#include <llvm/" llvm_include)
  string(FIND "${content}" "llvm::" llvm_namespace)
  if((NOT llvm_include EQUAL -1 OR NOT llvm_namespace EQUAL -1) AND
     NOT path STREQUAL "${ROOT}/source/recurloop/LlvmBackend.cpp")
    message(FATAL_ERROR "LLVM C++ API escaped the backend boundary: ${path}")
  endif()
endforeach()

foreach(required IN ITEMS
    "${ROOT}/libraries/recurloop/core/collections.rl"
    "${ROOT}/libraries/recurloop/core/actions.rl"
    "${ROOT}/libraries/recurloop/core/host-actions.allow"
    "${ROOT}/docs/host-abi.md")
  if(NOT EXISTS "${required}")
    message(FATAL_ERROR "final autonomy boundary is missing required file: ${required}")
  endif()
endforeach()

if(EXISTS "${ROOT}/todo.md")
  message(FATAL_ERROR "final autonomy tree must not contain todo.md")
endif()

message(STATUS "Final Host ABI/backend boundary audit passed")
