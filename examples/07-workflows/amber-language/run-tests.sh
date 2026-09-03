#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /absolute/path/to/Recurloop" >&2
    exit 2
fi

RECURLOOP="$(readlink -f "$1")"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=/tmp/recurloop-amber-library.rli
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$RECURLOOP" --file "$DIR/library.rl" >"$TMP/build.out" 2>"$TMP/build.err"
[[ -s "$IMAGE" ]] || { echo '[amber] image was not created' >&2; exit 1; }

cat >"$TMP/official.expected" <<'OUT'
Hello, my name is John
I'm an adult
My favorite fruits are:
apple
banana
cherry
date
OUT
"$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/basic-syntax.ab" >"$TMP/official.out" 2>"$TMP/official.err"
[[ ! -s "$TMP/official.err" ]] || { cat "$TMP/official.err" >&2; exit 1; }
diff -u "$TMP/official.expected" "$TMP/official.out"
printf '[amber] %-20s ok\n' 'basic-syntax'

cat >"$TMP/shell.expected" <<'OUT'
hello-RecurLoop-42
beta

7
succeeded
/tmp

Amber compatibility smoke test complete
OUT
"$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/shell-smoke.rl" >"$TMP/shell.out" 2>"$TMP/shell.err"
[[ ! -s "$TMP/shell.err" ]] || { cat "$TMP/shell.err" >&2; exit 1; }
diff -u "$TMP/shell.expected" "$TMP/shell.out"
printf '[amber] %-20s ok\n' 'shell-smoke'

for spec in \
    "variable name" \
    "variable fruits" \
    "array fruits" \
    "type Int" \
    "builtin echo" \
    "grammar for"; do
    "$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/basic-syntax.ab" \
        --string "amber_assert $spec" >/dev/null
 done
for spec in "function amber_add" "variable mutable"; do
    "$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/shell-smoke.rl" \
        --string "amber_assert $spec" >/dev/null
 done
printf '[amber] %-20s ok\n' 'phrase-visibility'

echo '[amber] all compatibility tests passed'
