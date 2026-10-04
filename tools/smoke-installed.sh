#!/bin/sh
# Clean installed-package smoke test. No compiler, CMake, readelf, network or
# source/dependency cache is required: LLVM JIT execution is in-process.
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
RL
recurloop --file native.rl

# Native file output intentionally requires optional host Clang/LLD. A clean
# runtime must diagnose missing tools rather than depend on the builder's SDK.
mkdir empty-path
for kind in object executable; do
  printf 'emit %s "answer" main = fn () -> i64 { return 42 }\n' "$kind" > output.rl
  if diagnostic=$(PATH="$work/empty-path" "$prefix/bin/recurloop" --file output.rl 2>&1); then
    echo "native $kind output unexpectedly succeeded without host linker tools" >&2
    exit 1
  fi
  case "$diagnostic" in
    *'Install Clang/LLD 22'*) ;;
    *) echo "unexpected missing-tool diagnostic: $diagnostic" >&2; exit 1 ;;
  esac
done
