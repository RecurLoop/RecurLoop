#!/usr/bin/env bash
# Official Linux x86-64 glibc release builder. LLVM is an immutable official
# binary dependency; RecurLoop never compiles LLVM in this workflow.
set -euo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C
export TZ=UTC
umask 022

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "official release builder requires a clean tracked checkout" >&2
  exit 1
fi

if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
  SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
  export SOURCE_DATE_EPOCH
fi
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]]

deps="$PWD/.cache/linux-release-deps"
mkdir -p "$deps"
sdk_path_file="$deps/llvm-sdk-path.txt"
cmake -DRECURLOOP_DEPS_DIR="$deps" -DOUTPUT_FILE="$sdk_path_file" -P cmake/PrepareLLVMArchive.cmake
sdk="$(cat "$sdk_path_file")"
test -x "$sdk/bin/clang"
test -x "$sdk/bin/clang++"

# Use the compiler from the same checksum-pinned official LLVM release. The
# package itself does not redistribute these tools; they are build dependencies.
export PATH="$sdk/bin:$PATH"
common_flags="-march=x86-64 -mtune=generic"
cmake --preset ci \
  -DRECURLOOP_DEPS_DIR="$deps" \
  -DRECURLOOP_LLVM_PROVIDER=ARCHIVE \
  -DRECURLOOP_LLVM_LINK_TARGETS=native \
  -DCMAKE_C_COMPILER="$sdk/bin/clang" \
  -DCMAKE_CXX_COMPILER="$sdk/bin/clang++" \
  -DCMAKE_C_FLAGS="$common_flags" \
  -DCMAKE_CXX_FLAGS="$common_flags"
cmake --build --preset ci --target Recurloop RecurloopUnitTests RecurloopLibraries --parallel "${RECURLOOP_BUILD_JOBS:-2}"
ctest --preset ci-unit
ctest --preset ci-feature
tools/examples.sh all "$PWD/build/CI/bin/recurloop"
cmake --build --preset ci --target RecurloopCoreVerify
libraries/recurloop/test-core.sh "$PWD/build/CI/bin/recurloop"
cmake -DBUILD_DIR=build/CI -DMAX_GLIBC=2.35 -P cmake/Package.cmake

version="$(build/CI/bin/recurloop --version | sed -n 's/^Recurloop v//p')"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
asset="recurloop-${version}-linux-x86_64.tar.gz"
first_digest="$(awk 'NR == 1 { print $1 }' "build/CI/$asset.sha256")"
# Re-stage and re-pack the same verified build. Packaging must be byte-stable.
cmake -DBUILD_DIR=build/CI -DMAX_GLIBC=2.35 -P cmake/Package.cmake
second_digest="$(awk 'NR == 1 { print $1 }' "build/CI/$asset.sha256")"
[[ -n "$first_digest" && "$first_digest" == "$second_digest" ]] || {
  echo "release package is not reproducible across two clean staging passes" >&2
  exit 1
}

rm -rf dist
mkdir -p dist
cp "build/CI/$asset" "build/CI/$asset.sha256" dist/
