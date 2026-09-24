include_guard(GLOBAL)

set(RECURLOOP_RELEASE_FORMAT_VERSION "2")
# Official LLVM 22.1.8 Linux binaries are produced on Ubuntu 22.04. The current
# glibc release profile therefore uses that ABI generation as its conservative
# floor. Older glibc and musl get separate profiles instead of an unverified
# compatibility claim.
set(RECURLOOP_RELEASE_GLIBC_BASELINE "2.35")

function(recurloop_release_platform system_name system_processor out_platform out_description)
    string(TOLOWER "${system_name}" system)
    string(TOLOWER "${system_processor}" processor)
    if(processor STREQUAL "")
        cmake_host_system_information(RESULT detected_processor QUERY OS_PLATFORM)
        string(TOLOWER "${detected_processor}" processor)
    endif()

    if(system STREQUAL "linux" AND processor MATCHES "^(x86_64|amd64)$")
        set(${out_platform} "linux-x86_64" PARENT_SCOPE)
        set(${out_description} "Linux x86-64 (glibc >= ${RECURLOOP_RELEASE_GLIBC_BASELINE})" PARENT_SCOPE)
        return()
    endif()

    message(FATAL_ERROR
        "No production release profile exists for ${system_name}/${system_processor}. "
        "Add an explicit host adapter, ABI contract, package recipe and compatibility tests; "
        "do not silently reuse the Linux x86-64 package recipe.")
endfunction()
