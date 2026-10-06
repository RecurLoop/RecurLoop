#!/usr/bin/env bash
# Official Linux x86-64 glibc release builder. LLVM is an immutable official
# binary dependency; RecurLoop never compiles LLVM in this workflow.
set -euo pipefail
phase=${1:-all}
if [[ $# -gt 1 ]]; then
  echo "usage: $0 [all|configure|build|unit|feature|examples|core|package]" >&2
  exit 2
fi
case "$phase" in
  all|configure|build|unit|feature|examples|core|package) ;;
  *) echo "unknown release phase: $phase" >&2; exit 2 ;;
esac
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
sdk_path_file="$deps/llvm-sdk-path.txt"

load_sdk() {
  sdk="$(cat "$sdk_path_file")"
  test -x "$sdk/bin/clang"
  test -x "$sdk/bin/clang++"
  export PATH="$sdk/bin:$PATH"
}

# Limit cold-build concurrency to available CPUs and roughly 2 GiB per compiler.
# RECURLOOP_BUILD_JOBS remains an explicit override for other runner sizes.
if [[ -z "${RECURLOOP_BUILD_JOBS:-}" ]]; then
  build_jobs=$(nproc)
  available_kib=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
  memory_jobs=$((available_kib / 2097152))
  (( memory_jobs > 0 )) || memory_jobs=1
  (( build_jobs <= memory_jobs )) || build_jobs=$memory_jobs
else
  build_jobs=$RECURLOOP_BUILD_JOBS
fi
[[ "$build_jobs" =~ ^[1-9][0-9]*$ ]] || { echo "RECURLOOP_BUILD_JOBS must be a positive integer" >&2; exit 2; }

configure_release() {
  mkdir -p "$deps"
  cmake -DRECURLOOP_DEPS_DIR="$deps" -DOUTPUT_FILE="$sdk_path_file" -P cmake/PrepareLLVMArchive.cmake
  load_sdk

  # Use the compiler from the same checksum-pinned official LLVM release. The
  # package itself does not redistribute these tools; they are build dependencies.
  common_flags="-march=x86-64 -mtune=generic"
  cmake --preset ci \
    -DRECURLOOP_DEPS_DIR="$deps" \
    -DRECURLOOP_LLVM_PROVIDER=ARCHIVE \
    -DRECURLOOP_LLVM_LINK_TARGETS=native \
    -DCMAKE_C_COMPILER="$sdk/bin/clang" \
    -DCMAKE_CXX_COMPILER="$sdk/bin/clang++" \
    -DCMAKE_C_FLAGS="$common_flags" \
    -DCMAKE_CXX_FLAGS="$common_flags"
}

build_release() {
  echo "[release] build parallelism: $build_jobs"
  cmake --build --preset ci --target Recurloop RecurloopUnitTests RecurloopLibraries --parallel "$build_jobs"
}

verify_core() {
  cmake --build --preset ci --target RecurloopCoreVerify --parallel "$build_jobs"
  libraries/recurloop/test-core.sh "$PWD/build/CI/bin/recurloop"
}

package_release() {
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
}

if [[ "$phase" == all || "$phase" == configure ]]; then
  configure_release
else
  load_sdk
fi

case "$phase" in
  configure) ;;
  build) build_release ;;
  unit) ctest --preset ci-unit ;;
  feature) ctest --preset ci-feature ;;
  examples) tools/examples.sh all "$PWD/build/CI/bin/recurloop" ;;
  core) verify_core ;;
  package) package_release ;;
  all)
    build_release
    ctest --preset ci-unit
    ctest --preset ci-feature
    tools/examples.sh all "$PWD/build/CI/bin/recurloop"
    verify_core
    package_release
    ;;
esac
