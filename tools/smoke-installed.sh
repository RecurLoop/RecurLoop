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

test -s "$prefix/share/recurloop/standard-libraries.txt"
while IFS= read -r library; do
  test -s "$prefix/share/recurloop/libraries/${library}.rli"
done < "$prefix/share/recurloop/standard-libraries.txt"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cd "$work"
PATH="$prefix/bin:$PATH"
export PATH
recurloop --version
recurloop --library shell --library inferred --string 'assert 6 * 7 == 42'
recurloop --string 'import window
import vulkan
import window
assert 6 * 7 == 42'

cat > native.rl <<'RL'
fn add(a:i64, b:i64) -> i64 { return a + b }
assert add(20, 22) == 42
RL
recurloop --file native.rl

# These operations exercise allocator/zero-fill libc calls and source-owned
# actions, beyond loading an image or running a scalar addition. Run them on
# every clean compatibility image, especially the glibc 2.35 release floor.
cat > inferred.rl <<'RL'
import inferred
poly fn twice(value) { return value + value }
print "defined"
assert twice(21) == 42
RL
test "$(recurloop --file inferred.rl)" = defined

cat > arrays.rl <<'RL'
link shared "c"
record Table { values:i64[64] total:i64 }
fn aggregate(n:i64) -> i64 {
  let x = alloc(Table)
  if !x { return -1 }
  var i:i64 = 0
  x.total = 0
  while i < 64 { x.values[i] = 0 i += 1 }
  i = 0
  while i < n {
    let t = i % 64
    x.values[t] += 1
    i += 1
  }
  i = 0
  while i < 64 { x.total += x.values[i] i += 1 }
  return x.total
}
assert aggregate(100) == 100
RL
recurloop --file arrays.rl

cat > recurloop.project.rl <<'RL'
import project
let Application = [
    answer = fn () -> i64 { return 42 }
]
target run { print Application:answer() }
target test { assert Application:answer() == 42 }
RL
targets=$(recurloop --targets)
for name in run test; do
  case "$targets" in
    *"\"name\":\"$name\""*) ;;
    *) echo "missing project target $name: $targets" >&2; exit 1 ;;
  esac
done
test "$(recurloop --target run)" = 42
recurloop --target test

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
