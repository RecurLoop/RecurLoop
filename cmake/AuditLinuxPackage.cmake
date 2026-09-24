cmake_minimum_required(VERSION 3.25)
include("${CMAKE_CURRENT_LIST_DIR}/ReleasePlatform.cmake")
find_program(READELF readelf REQUIRED)
if(NOT DEFINED PREFIX OR NOT EXISTS "${PREFIX}/bin/recurloop")
    message(FATAL_ERROR "PREFIX must identify an installed package")
endif()
get_filename_component(PREFIX "${PREFIX}" ABSOLUTE)
if(DEFINED RELEASE_PLATFORM AND NOT RELEASE_PLATFORM STREQUAL "" AND
   DEFINED RELEASE_DESCRIPTION AND NOT RELEASE_DESCRIPTION STREQUAL "")
    set(release_platform "${RELEASE_PLATFORM}")
    set(release_description "${RELEASE_DESCRIPTION}")
else()
    recurloop_release_platform("${CMAKE_HOST_SYSTEM_NAME}" "${CMAKE_HOST_SYSTEM_PROCESSOR}"
        release_platform release_description)
endif()
if(NOT release_platform STREQUAL "linux-x86_64")
    message(FATAL_ERROR "AuditLinuxPackage.cmake only audits linux-x86_64 packages")
endif()

# Symlinks must stay inside the package. Absolute or escaping links make a
# relocatable archive depend on the builder's filesystem.
file(GLOB_RECURSE package_entries LIST_DIRECTORIES TRUE "${PREFIX}/*")
foreach(path IN LISTS package_entries)
    if(IS_SYMLINK "${path}")
        file(READ_SYMLINK "${path}" target)
        if(IS_ABSOLUTE "${target}")
            message(FATAL_ERROR "Absolute symlink in package: ${path} -> ${target}")
        endif()
        get_filename_component(parent "${path}" DIRECTORY)
        file(REAL_PATH "${parent}/${target}" resolved BASE_DIRECTORY "${parent}")
        string(FIND "${resolved}" "${PREFIX}/" inside)
        if(NOT resolved STREQUAL PREFIX AND NOT inside EQUAL 0)
            message(FATAL_ERROR "Symlink escapes package: ${path} -> ${target}")
        endif()
    endif()
endforeach()

# Check every installed ELF. LLVM itself is linked statically; a small, explicit
# set of ordinary host runtime libraries may remain dynamic. New dependencies
# must be reviewed here instead of silently leaking in from the build host.
file(GLOB_RECURSE files LIST_DIRECTORIES FALSE "${PREFIX}/*")
set(max_glibc "0.0")
foreach(path IN LISTS files)
    file(READ "${path}" magic LIMIT 4 HEX)
    if(NOT magic STREQUAL "7f454c46")
        continue()
    endif()

    execute_process(COMMAND "${READELF}" -h "${path}" OUTPUT_VARIABLE header RESULT_VARIABLE result)
    if(NOT result EQUAL 0 OR NOT header MATCHES "Machine:[^\n]*(X86-64|Advanced Micro Devices X86-64)")
        message(FATAL_ERROR "Unexpected ELF architecture in ${path}:\n${header}")
    endif()

    execute_process(COMMAND "${READELF}" -l "${path}" OUTPUT_VARIABLE program_headers RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "Cannot inspect program headers in ${path}")
    endif()
    string(REGEX MATCH "Requesting program interpreter: ([^]]+)" interpreter_match "${program_headers}")
    if(interpreter_match)
        set(interpreter "${CMAKE_MATCH_1}")
        if(NOT interpreter STREQUAL "/lib64/ld-linux-x86-64.so.2")
            message(FATAL_ERROR "Unexpected ELF interpreter in ${path}: ${interpreter}")
        endif()
    endif()

    execute_process(COMMAND "${READELF}" -d "${path}" OUTPUT_VARIABLE dynamic RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "Cannot inspect ${path}")
    endif()
    string(REGEX MATCHALL "Shared library: \\[[^]]+\\]" needed "${dynamic}")
    foreach(entry IN LISTS needed)
        if(NOT entry MATCHES "\\[(libc\\.so\\.6|libm\\.so\\.6|libdl\\.so\\.2|libpthread\\.so\\.0|librt\\.so\\.1|libresolv\\.so\\.2|libutil\\.so\\.1|libz\\.so\\.1|libzstd\\.so\\.1|libtinfo\\.so\\.6|libxml2\\.so\\.2|ld-linux-x86-64\\.so\\.2)\\]")
            message(FATAL_ERROR "Undeclared runtime dependency in ${path}: ${entry}")
        endif()
        if(entry MATCHES "libgcc_s|libstdc\\+\\+")
            message(FATAL_ERROR "Production binary must embed its C++/GCC runtime: ${path}: ${entry}")
        endif()
    endforeach()

    string(REGEX MATCHALL "\\((RPATH|RUNPATH)\\)[^\n]*" rpaths "${dynamic}")
    foreach(entry IN LISTS rpaths)
        string(REGEX REPLACE ".*\\[([^]]*)\\].*" "\\1" search_path "${entry}")
        string(REPLACE ":" ";" directories "${search_path}")
        foreach(directory IN LISTS directories)
            if(NOT directory MATCHES "^\\$ORIGIN(/|$)")
                message(FATAL_ERROR "Non-relocatable ELF search path in ${path}: ${directory}")
            endif()
        endforeach()
    endforeach()

    # Read undefined symbols only; definitions in the packaged libc are not
    # requirements imposed on the target's libc.
    execute_process(COMMAND "${READELF}" --dyn-syms --wide "${path}" OUTPUT_VARIABLE symbols)
    string(REGEX MATCHALL "UND[^\n]*@GLIBC_[0-9.]+" requirements "${symbols}")
    foreach(entry IN LISTS requirements)
        string(REGEX REPLACE ".*@GLIBC_([0-9.]+).*" "\\1" version "${entry}")
        if(version VERSION_GREATER max_glibc)
            set(max_glibc "${version}")
        endif()
    endforeach()
endforeach()

if(DEFINED MAX_GLIBC AND max_glibc VERSION_GREATER MAX_GLIBC)
    message(FATAL_ERROR "Package requires glibc ${max_glibc}; release baseline is ${MAX_GLIBC}")
endif()
file(MAKE_DIRECTORY "${PREFIX}/share/recurloop")
file(WRITE "${PREFIX}/share/recurloop/BUILD-COMPATIBILITY.txt"
    "Package: ${release_platform}\n"
    "Runtime ABI: ${release_description}\n"
    "Required glibc: >= ${max_glibc}\n"
    "LLVM backend: statically linked into bin/recurloop\n"
    "Native file output: requires compatible lld/clang on PATH\n"
    "Unsupported by this artifact: musl, non-x86-64 hosts, Windows, Darwin/iOS, bare metal\n")
message(STATUS "Package ELF audit passed; glibc requirement: ${max_glibc}")
