#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /absolute/path/to/recurloop" >&2
    exit 2
fi

RECURLOOP="$(readlink -f "$1")"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=/tmp/recurloop-amber-library.rli
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$RECURLOOP" --file "$DIR/library.rl" >"$TMP/build.out" 2>"$TMP/build.err"
[[ -s "$IMAGE" ]] || {
    echo '[amber] image was not created' >&2
    cat "$TMP/build.err" >&2
    exit 1
}

cat >"$TMP/basic-syntax.expected" <<'OUT'
RecurLoop compatibility fixture
phrases
pipelines
native-code
language image is active
OUT

"$RECURLOOP" \
    --import "$IMAGE" \
    --file "$DIR/tests/basic-syntax.ab" \
    >"$TMP/basic-syntax.out" \
    2>"$TMP/basic-syntax.err"

if [[ -s "$TMP/basic-syntax.err" ]]; then
    echo '[amber] basic-syntax: unexpected stderr' >&2
    cat "$TMP/basic-syntax.err" >&2
    exit 1
fi

if ! diff -u "$TMP/basic-syntax.expected" "$TMP/basic-syntax.out"; then
    echo '[amber] basic-syntax: output mismatch' >&2
    exit 1
fi
printf '[amber] %-20s ok\n' 'basic-syntax'

cat >"$TMP/shell.expected" <<'OUT'
hello-RecurLoop-42
beta

7
succeeded
/tmp

Amber compatibility smoke test complete
OUT

"$RECURLOOP" \
    --import "$IMAGE" \
    --file "$DIR/tests/shell-smoke.rl" \
    >"$TMP/shell.out" \
    2>"$TMP/shell.err"

if [[ -s "$TMP/shell.err" ]]; then
    echo '[amber] shell-smoke: unexpected stderr' >&2
    cat "$TMP/shell.err" >&2
    exit 1
fi

if ! diff -u "$TMP/shell.expected" "$TMP/shell.out"; then
    echo '[amber] shell-smoke: output mismatch' >&2
    exit 1
fi
printf '[amber] %-20s ok\n' 'shell-smoke'

cat >"$TMP/phrase-grammar.expected" <<'OUT'
alpha
beta
7
OUT
"$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/phrase-grammar.ab" \
    >"$TMP/phrase-grammar.out" 2>"$TMP/phrase-grammar.err"
if [[ -s "$TMP/phrase-grammar.err" ]]; then
    cat "$TMP/phrase-grammar.err" >&2
    exit 1
fi
diff -u "$TMP/phrase-grammar.expected" "$TMP/phrase-grammar.out"
printf '[amber] %-20s ok\n' 'phrase-grammar'

# Both constructs cross the old fixed lookahead sizes. The long comment also
# checks that a refill cannot turn its tail into array syntax.
{
    printf 'let values = [\n// %*s\n"ok"]\necho(values)\necho("' 70000 ''
    printf '%*s' 1048704 '' | tr ' ' x
    printf '")\n'
} >"$TMP/streamed.ab"
{
    printf 'ok\n'
    printf '%*s' 1048704 '' | tr ' ' x
    printf '\n'
} >"$TMP/streamed.expected"
"$RECURLOOP" --import "$IMAGE" --file "$TMP/streamed.ab" \
    >"$TMP/streamed.out" 2>"$TMP/streamed.err"
if [[ -s "$TMP/streamed.err" ]]; then
    cat "$TMP/streamed.err" >&2
    exit 1
fi
cmp "$TMP/streamed.expected" "$TMP/streamed.out"
printf '[amber] %-20s ok\n' 'streamed-input'

for spec in \
    "variable engine" \
    "variable enabled" \
    "variable capabilities" \
    "array capabilities" \
    "type Int" \
    "builtin echo" \
    "grammar for"; do
    "$RECURLOOP" \
        --import "$IMAGE" \
        --file "$DIR/tests/basic-syntax.ab" \
        --string "amber_assert $spec" \
        >/dev/null
done

for spec in "function amber_add" "variable mutable"; do
    "$RECURLOOP" \
        --import "$IMAGE" \
        --file "$DIR/tests/shell-smoke.rl" \
        --string "amber_assert $spec" \
        >/dev/null
done

printf '[amber] %-20s ok\n' 'phrase-visibility'
echo '[amber] all compatibility tests passed'
