get_filename_component(REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)

set(AUTO_OBJECT "/tmp/recurloop-showcase-auto.o")
set(LINKABLE_OBJECT "/tmp/recurloop-showcase-linkable.o")
set(MANUAL_OBJECT "/tmp/recurloop-showcase-manual.o")
set(DYNAMIC_OBJECT "/tmp/recurloop-showcase-dynamic.o")
set(STRIPPED_OBJECT "/tmp/recurloop-showcase-stripped.o")
set(LINKED_EXECUTABLE "/tmp/recurloop-showcase-linked")
set(EXECUTABLE "/tmp/recurloop-showcase")
set(C_ABI_OBJECT "/tmp/recurloop-showcase-cabi.o")
set(FIBONACCI_EXECUTABLE "/tmp/recurloop-showcase-fibonacci")
set(RAW_OUTPUT "/tmp/recurloop-showcase.raw")

file(REMOVE
    "${AUTO_OBJECT}"
    "${LINKABLE_OBJECT}"
    "${MANUAL_OBJECT}"
    "${DYNAMIC_OBJECT}"
    "${STRIPPED_OBJECT}"
    "${LINKED_EXECUTABLE}"
    "${EXECUTABLE}"
    "${C_ABI_OBJECT}"
    "${FIBONACCI_EXECUTABLE}"
    "${RAW_OUTPUT}"
)

execute_process(
    COMMAND "${PROGRAM}" --file "${REPOSITORY_ROOT}/program.rl.example"
    RESULT_VARIABLE showcase_rc
    OUTPUT_VARIABLE showcase_out
    ERROR_VARIABLE showcase_err
)

if (NOT showcase_rc EQUAL 0)
    message(FATAL_ERROR "Showcase failed with status ${showcase_rc}:\n${showcase_err}\n${showcase_out}")
endif()
if (NOT showcase_err STREQUAL "")
    message(FATAL_ERROR "Showcase wrote unexpected stderr:\n${showcase_err}")
endif()

foreach(marker
    "[01/19] values and arithmetic: ok"
    "[05/19] functions and recursion: factorial(6)=720"
    "[12/19] raw opcodes and phrase-driven x86-64 assembler"
    "[17/19] compiled Fibonacci using linked printf and atoi phrases"
    "[19/19] SHOWCASE PASSED"
)
    string(FIND "${showcase_out}" "${marker}" marker_position)
    if (marker_position EQUAL -1)
        message(FATAL_ERROR "Showcase output is missing marker '${marker}':\n${showcase_out}")
    endif()
endforeach()

foreach(elf_file "${AUTO_OBJECT}" "${LINKABLE_OBJECT}" "${MANUAL_OBJECT}" "${DYNAMIC_OBJECT}" "${STRIPPED_OBJECT}" "${LINKED_EXECUTABLE}" "${EXECUTABLE}" "${C_ABI_OBJECT}" "${FIBONACCI_EXECUTABLE}")
    if (NOT EXISTS "${elf_file}")
        message(FATAL_ERROR "Showcase did not create ${elf_file}")
    endif()
    file(READ "${elf_file}" elf_magic LIMIT 4 HEX)
    if (NOT elf_magic STREQUAL "7f454c46")
        message(FATAL_ERROR "${elf_file} does not start with the ELF magic: ${elf_magic}")
    endif()
endforeach()

execute_process(
    COMMAND "${FIBONACCI_EXECUTABLE}" 7
    RESULT_VARIABLE fibonacci_rc
    OUTPUT_VARIABLE fibonacci_out
    ERROR_VARIABLE fibonacci_err
)
if (NOT fibonacci_rc EQUAL 0 OR NOT fibonacci_out STREQUAL "1\n1\n2\n3\n5\n8\n13\n" OR NOT fibonacci_err STREQUAL "")
    message(FATAL_ERROR
        "Native Fibonacci executable failed: status=${fibonacci_rc}, stdout='${fibonacci_out}', stderr='${fibonacci_err}'")
endif()

find_program(READELF_EXECUTABLE readelf REQUIRED)

execute_process(
    COMMAND "${LINKED_EXECUTABLE}"
    RESULT_VARIABLE linked_rc
    OUTPUT_VARIABLE linked_out
    ERROR_VARIABLE linked_err
)
if (NOT linked_rc EQUAL 0 OR NOT linked_out STREQUAL "" OR NOT linked_err STREQUAL "")
    message(FATAL_ERROR
        "Executable linked from external object failed: status=${linked_rc}, stdout='${linked_out}', stderr='${linked_err}'")
endif()

execute_process(
    COMMAND "${READELF_EXECUTABLE}" -h -S -s -r "${AUTO_OBJECT}"
    RESULT_VARIABLE auto_rc
    OUTPUT_VARIABLE auto_info
    ERROR_VARIABLE auto_err
)
if (NOT auto_rc EQUAL 0)
    message(FATAL_ERROR "readelf rejected auto object:\n${auto_err}")
endif()
foreach(fragment
    "REL (Relocatable file)"
    ".recurloop.language"
    ".rodata.str1.1"
    ".tdata"
    ".init_array"
    ".fini_array"
    ".preinit_array"
    ".example-note"
    ".example-nobits"
    "object_entry"
    "native_add"
)
    string(FIND "${auto_info}" "${fragment}" fragment_position)
    if (fragment_position EQUAL -1)
        message(FATAL_ERROR "Auto object is missing '${fragment}':\n${auto_info}")
    endif()
endforeach()

execute_process(
    COMMAND "${READELF_EXECUTABLE}" -s "${MANUAL_OBJECT}"
    OUTPUT_VARIABLE manual_symbols
    COMMAND_ERROR_IS_FATAL ANY
)
foreach(symbol "manual_bundle" "native_add")
    string(FIND "${manual_symbols}" "${symbol}" symbol_position)
    if (symbol_position EQUAL -1)
        message(FATAL_ERROR "Manual object is missing symbol '${symbol}':\n${manual_symbols}")
    endif()
endforeach()

execute_process(
    COMMAND "${READELF_EXECUTABLE}" -s -r "${DYNAMIC_OBJECT}"
    OUTPUT_VARIABLE dynamic_info
    COMMAND_ERROR_IS_FATAL ANY
)
if (NOT dynamic_info MATCHES "UND[^\n]*native_add")
    message(FATAL_ERROR "Dynamic object should leave native_add undefined:\n${dynamic_info}")
endif()

execute_process(
    COMMAND "${READELF_EXECUTABLE}" -S "${STRIPPED_OBJECT}"
    OUTPUT_VARIABLE stripped_sections
    COMMAND_ERROR_IS_FATAL ANY
)
if (stripped_sections MATCHES "recurloop.language")
    message(FATAL_ERROR "Stripped object unexpectedly embeds the language image:\n${stripped_sections}")
endif()

execute_process(
    COMMAND "${EXECUTABLE}"
    RESULT_VARIABLE executable_rc
    OUTPUT_VARIABLE executable_out
    ERROR_VARIABLE executable_err
)
if (NOT executable_rc EQUAL 0 OR NOT executable_out STREQUAL "RL EXEC\n" OR NOT executable_err STREQUAL "")
    message(FATAL_ERROR
        "Generated executable failed: status=${executable_rc}, stdout='${executable_out}', stderr='${executable_err}'")
endif()

if (NOT EXISTS "${RAW_OUTPUT}")
    message(FATAL_ERROR "Showcase did not create ${RAW_OUTPUT}")
endif()
file(READ "${RAW_OUTPUT}" raw_hex HEX)
if (NOT raw_hex STREQUAL "524c205241570a")
    message(FATAL_ERROR "Raw output differs from the requested bytes: ${raw_hex}")
endif()

file(REMOVE
    "${AUTO_OBJECT}"
    "${MANUAL_OBJECT}"
    "${DYNAMIC_OBJECT}"
    "${STRIPPED_OBJECT}"
    "${LINKED_EXECUTABLE}"
    "${EXECUTABLE}"
    "${C_ABI_OBJECT}"
    "${FIBONACCI_EXECUTABLE}"
    "${RAW_OUTPUT}"
)
