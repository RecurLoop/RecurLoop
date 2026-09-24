include_guard(GLOBAL)

# RecurLoop consumes released LLVM binaries; it never builds LLVM from source.
# Keep immutable release metadata here so local builds and CI resolve exactly
# the same archive when ARCHIVE is selected.
set(RECURLOOP_LLVM_VERSION "22.1.8")
set(RECURLOOP_SYSTEM_LLVM_MIN_VERSION "22.0.0")
set(RECURLOOP_SYSTEM_LLVM_MAX_VERSION "23.0.0")

set(RECURLOOP_LLVM_ARCHIVE_URL "" CACHE STRING
    "Override the official LLVM binary archive URL")
set(RECURLOOP_LLVM_ARCHIVE_SHA256 "" CACHE STRING
    "SHA256 for RECURLOOP_LLVM_ARCHIVE_URL")

function(recurloop_host_identity out_system out_processor)
    set(system "${CMAKE_HOST_SYSTEM_NAME}")
    set(processor "${CMAKE_HOST_SYSTEM_PROCESSOR}")
    if(system STREQUAL "")
        cmake_host_system_information(RESULT system QUERY OS_NAME)
    endif()
    if(processor STREQUAL "")
        cmake_host_system_information(RESULT processor QUERY OS_PLATFORM)
    endif()
    set(${out_system} "${system}" PARENT_SCOPE)
    set(${out_processor} "${processor}" PARENT_SCOPE)
endfunction()

function(recurloop_normalize_host_arch input out_arch)
    string(TOLOWER "${input}" arch)
    if(arch MATCHES "^(x86_64|amd64|x64)$")
        set(arch "x86_64")
    elseif(arch MATCHES "^(aarch64|arm64)$")
        set(arch "arm64")
    endif()
    set(${out_arch} "${arch}" PARENT_SCOPE)
endfunction()

function(recurloop_llvm_archive_metadata out_url out_sha out_id out_filename)
    recurloop_host_identity(host_system host_processor)
    recurloop_normalize_host_arch("${host_processor}" arch)
    string(TOLOWER "${host_system}" os)

    if(NOT RECURLOOP_LLVM_ARCHIVE_URL STREQUAL "")
        string(LENGTH "${RECURLOOP_LLVM_ARCHIVE_SHA256}" hash_length)
        if(NOT hash_length EQUAL 64 OR
           NOT RECURLOOP_LLVM_ARCHIVE_SHA256 MATCHES "^[0-9a-fA-F]+$")
            message(FATAL_ERROR
                "RECURLOOP_LLVM_ARCHIVE_URL requires a 64-character RECURLOOP_LLVM_ARCHIVE_SHA256")
        endif()
        get_filename_component(filename "${RECURLOOP_LLVM_ARCHIVE_URL}" NAME)
        if(filename STREQUAL "")
            set(filename "llvm-${RECURLOOP_LLVM_VERSION}.archive")
        endif()
        set(${out_url} "${RECURLOOP_LLVM_ARCHIVE_URL}" PARENT_SCOPE)
        string(TOLOWER "${RECURLOOP_LLVM_ARCHIVE_SHA256}" custom_sha)
        set(${out_sha} "${custom_sha}" PARENT_SCOPE)
        set(${out_id} "${os}-${arch}-custom" PARENT_SCOPE)
        set(${out_filename} "${filename}" PARENT_SCOPE)
        return()
    endif()

    set(base "https://github.com/llvm/llvm-project/releases/download/llvmorg-${RECURLOOP_LLVM_VERSION}")
    if(host_system STREQUAL "Linux" AND arch STREQUAL "x86_64")
        set(filename "LLVM-${RECURLOOP_LLVM_VERSION}-Linux-X64.tar.xz")
        set(sha "df0e1ecf16caf3489a272a5eea4eec9b0d82878f6477fa309504f918a0006384")
        set(id "linux-x86_64")
    elseif(host_system STREQUAL "Linux" AND arch STREQUAL "arm64")
        set(filename "LLVM-${RECURLOOP_LLVM_VERSION}-Linux-ARM64.tar.xz")
        set(sha "805efad2bb91cb4967fa569e0881d10c0f69c04461cf671cccbae19f547acc34")
        set(id "linux-arm64")
    elseif(host_system STREQUAL "Darwin" AND arch STREQUAL "arm64")
        set(filename "LLVM-${RECURLOOP_LLVM_VERSION}-macOS-ARM64.tar.xz")
        set(sha "f260f4f7c0d430828a81ae8a3826a1d63fc0963ec2459489308cc23b1f7eab4f")
        set(id "macos-arm64")
    elseif(host_system STREQUAL "Windows" AND arch STREQUAL "x86_64")
        set(filename "clang+llvm-${RECURLOOP_LLVM_VERSION}-x86_64-pc-windows-msvc.tar.xz")
        set(sha "d96c2cc1736f4eb7fa43cb9bbdf56d93551a9ae0a9aadb9c99c3c3b2b712a234")
        set(id "windows-x86_64")
    elseif(host_system STREQUAL "Windows" AND arch STREQUAL "arm64")
        set(filename "clang+llvm-${RECURLOOP_LLVM_VERSION}-aarch64-pc-windows-msvc.tar.xz")
        set(sha "de718c58ebbc5f61d58c17b90457fcf42983bc2c4a4aba3e010d108713bfd7f1")
        set(id "windows-arm64")
    else()
        message(FATAL_ERROR
            "LLVM ${RECURLOOP_LLVM_VERSION} has no configured official binary archive for "
            "${host_system}/${host_processor}. Use RECURLOOP_LLVM_PROVIDER=SYSTEM "
            "(recommended for musl/embedded/custom hosts), or provide "
            "RECURLOOP_LLVM_ARCHIVE_URL and RECURLOOP_LLVM_ARCHIVE_SHA256.")
    endif()

    set(${out_url} "${base}/${filename}" PARENT_SCOPE)
    set(${out_sha} "${sha}" PARENT_SCOPE)
    set(${out_id} "${id}" PARENT_SCOPE)
    set(${out_filename} "${filename}" PARENT_SCOPE)
endfunction()
