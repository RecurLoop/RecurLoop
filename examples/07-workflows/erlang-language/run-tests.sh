#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /absolute/path/to/recurloop" >&2
    exit 2
fi

RECURLOOP="$(readlink -f "$1")"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=/tmp/recurloop-erlang-library.rli
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$RECURLOOP" --file "$DIR/library.rl" >"$TMP/build.out" 2>"$TMP/build.err"
[[ -f "$IMAGE" ]] || { echo '[erlang] image was not created' >&2; exit 1; }

run_ok() {
    local name="$1"
    local expected="$2"
    local out="$TMP/$name.out"
    local err="$TMP/$name.err"
    "$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/$name.erl" >"$out" 2>"$err"
    if [[ -s "$err" ]]; then
        echo "[erlang] $name: unexpected stderr" >&2
        cat "$err" >&2
        exit 1
    fi
    if [[ "$(cat "$out")" != "$expected" ]]; then
        echo "[erlang] $name: output mismatch" >&2
        printf 'expected:\n%s\n' "$expected" >&2
        printf 'actual:\n%s\n' "$(cat "$out")" >&2
        exit 1
    fi
    printf '[erlang] %-20s ok\n' "$name"
}

run_fail() {
    local name="$1"
    local diagnostic="$2"
    local out="$TMP/$name.out"
    local err="$TMP/$name.err"
    set +e
    "$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/$name.erl" >"$out" 2>"$err"
    local status=$?
    set -e
    if [[ $status -eq 0 ]]; then
        echo "[erlang] $name: expected failure" >&2
        exit 1
    fi
    if ! grep -q "$diagnostic" "$err"; then
        echo "[erlang] $name: wrong diagnostic" >&2
        cat "$err" >&2
        exit 1
    fi
    printf '[erlang] %-20s ok\n' "$name"
}

run_ok arithmetic '42'
run_ok function-clauses '5050'
run_ok tuple-pattern '42'
run_ok ping-pong 'pong'
run_ok selective-receive $'answer=42\nnoise'
run_ok main-before-worker 'ok'
run_ok mailbox-recursion $'one\ntwo'
run_fail badmatch 'Erlang: badmatch'
run_fail deadlock 'Erlang: receive would block with no runnable process'

for spec in \
    "module ping_pong" \
    "function main" \
    "function pong" \
    "variable From" \
    "atom ping" \
    "builtin spawn"; do
    "$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/ping-pong.erl" \
        --string "erlang_assert $spec" >"$TMP/phrase.out" 2>"$TMP/phrase.err"
    if [[ -s "$TMP/phrase.err" ]]; then
        echo "[erlang] phrase visibility failed: $spec" >&2
        cat "$TMP/phrase.err" >&2
        exit 1
    fi
done
printf '[erlang] %-20s ok\n' 'phrase-visibility'

echo '[erlang] all compatibility tests passed'
