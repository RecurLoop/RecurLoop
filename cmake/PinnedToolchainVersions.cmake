set(RECURLOOP_ZSTD_VERSION "1.5.7")
set(RECURLOOP_ZSTD_URL
    "https://github.com/facebook/zstd/releases/download/v${RECURLOOP_ZSTD_VERSION}/zstd-${RECURLOOP_ZSTD_VERSION}.tar.gz")
set(RECURLOOP_ZSTD_SHA256
    "eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3")

set(RECURLOOP_ZLIB_VERSION "1.3.1")
set(RECURLOOP_ZLIB_URL
    "https://github.com/madler/zlib/releases/download/v${RECURLOOP_ZLIB_VERSION}/zlib-${RECURLOOP_ZLIB_VERSION}.tar.gz")
set(RECURLOOP_ZLIB_SHA256
    "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23")

set(RECURLOOP_LLVM_VERSION "22.1.8")
# RecurLoop's LLVM backend is validated against the LLVM 22 API.
# AUTO/SYSTEM may use any compatible 22.x host installation; other major
# versions must fall back to the pinned 22.1.8 toolchain instead of being
# accepted optimistically.
set(RECURLOOP_SYSTEM_LLVM_MIN_VERSION "22.0.0")
set(RECURLOOP_SYSTEM_LLVM_MAX_VERSION "23.0.0")

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
        set(RECURLOOP_LLVM_URL
            "https://github.com/llvm/llvm-project/releases/download/llvmorg-${RECURLOOP_LLVM_VERSION}/LLVM-${RECURLOOP_LLVM_VERSION}-Linux-X64.tar.xz")
        set(RECURLOOP_LLVM_SHA256
            "df0e1ecf16caf3489a272a5eea4eec9b0d82878f6477fa309504f918a0006384")
    elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        set(RECURLOOP_LLVM_URL
            "https://github.com/llvm/llvm-project/releases/download/llvmorg-${RECURLOOP_LLVM_VERSION}/LLVM-${RECURLOOP_LLVM_VERSION}-Linux-ARM64.tar.xz")
        set(RECURLOOP_LLVM_SHA256
            "805efad2bb91cb4967fa569e0881d10c0f69c04461cf671cccbae19f547acc34")
    endif()
endif()
