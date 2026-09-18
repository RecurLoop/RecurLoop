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

set(RECURLOOP_LLVM_VERSION "22.1.6")
# RecurLoop's LLVM backend is validated against the LLVM 22 API.
# AUTO/SYSTEM may use any compatible 22.x host installation; other major
# versions must fall back to the pinned 22.1.6 toolchain instead of being
# accepted optimistically.
set(RECURLOOP_SYSTEM_LLVM_MIN_VERSION "22.0.0")
set(RECURLOOP_SYSTEM_LLVM_MAX_VERSION "23.0.0")

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
        set(RECURLOOP_LLVM_URL
            "https://github.com/llvm/llvm-project/releases/download/llvmorg-${RECURLOOP_LLVM_VERSION}/LLVM-${RECURLOOP_LLVM_VERSION}-Linux-X64.tar.xz")
        set(RECURLOOP_LLVM_SHA256
            "c5ac8ef89ca39d30cb32e9b83772f995dd891c685ebc188d593c943a64d5f8b5")
    elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        set(RECURLOOP_LLVM_URL
            "https://github.com/llvm/llvm-project/releases/download/llvmorg-${RECURLOOP_LLVM_VERSION}/LLVM-${RECURLOOP_LLVM_VERSION}-Linux-ARM64.tar.xz")
        set(RECURLOOP_LLVM_SHA256
            "b67817634e8e1c2632dfc056af14d61b94f8e6502f4e557560eea227aa22ce37")
    endif()
endif()
