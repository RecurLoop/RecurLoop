#!/bin/sh
# Clean installed-package smoke test. No compiler, CMake, readelf, network or
# source/dependency cache is required: LLVM object generation is in-process.
set -eu
prefix=$1
manifest="$prefix/share/recurloop/PACKAGE-MANIFEST.sha256"

for command in sha256sum mktemp; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "smoke test requires $command" >&2
    exit 1
  }
done

if [ ! -f "$manifest" ]; then
  echo "missing package integrity manifest: $manifest" >&2
  exit 1
fi
(
  cd "$prefix"
  sha256sum -c share/recurloop/PACKAGE-MANIFEST.sha256 >/dev/null
)

for library in language-kit shell inferred http gui ide project embed; do
  test -s "$prefix/share/recurloop/libraries/${library}.rli"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cd "$work"
PATH="$prefix/bin:$PATH"
export PATH
recurloop --version
recurloop --library shell --library inferred --string 'assert 6 * 7 == 42'
cat > native.rl <<'RL'
fn add(a:i64, b:i64) -> i64 { return a + b }
assert add(20, 22) == 42
emit object "answer.o" answer = fn () -> i64 { return 42 }
RL
recurloop --file native.rl
test -s answer.o
