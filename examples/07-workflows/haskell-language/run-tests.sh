#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /absolute/path/to/recurloop" >&2
    exit 2
fi

RECURLOOP="$(readlink -f "$1")"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=/tmp/recurloop-haskell-library.rli
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$RECURLOOP" --file "$DIR/library.rl" >"$TMP/build.out" 2>"$TMP/build.err"
[[ -f "$IMAGE" ]] || { echo '[haskell] image was not created' >&2; exit 1; }

run_ok() {
    local name="$1"
    local expected="$2"
    local out="$TMP/$name.out"
    local err="$TMP/$name.err"
    "$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/$name.hs" >"$out" 2>"$err"
    if [[ -s "$err" ]]; then
        echo "[haskell] $name: unexpected stderr" >&2
        cat "$err" >&2
        exit 1
    fi
    if [[ "$(cat "$out")" != "$expected" ]]; then
        echo "[haskell] $name: output mismatch" >&2
        echo "expected: $expected" >&2
        echo "actual:   $(cat "$out")" >&2
        exit 1
    fi
    printf '[haskell] %-18s ok\n' "$name"
}

run_ok factorial '720'
run_ok currying '42'
run_ok algebraic-data '42'
run_ok constructor-value 'Just 42'
run_ok higher-order '[2,4,6]'
run_ok lazy '42'
run_ok infinite-list '[1,1,1,1,1]'

set +e
"$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/non-exhaustive.hs" >"$TMP/non-exhaustive.out" 2>"$TMP/non-exhaustive.err"
status=$?
set -e
if [[ $status -eq 0 ]]; then
    echo '[haskell] non-exhaustive: expected failure' >&2
    exit 1
fi
if ! grep -q 'Haskell: non-exhaustive patterns' "$TMP/non-exhaustive.err"; then
    echo '[haskell] non-exhaustive: wrong diagnostic' >&2
    cat "$TMP/non-exhaustive.err" >&2
    exit 1
fi
printf '[haskell] %-18s ok\n' 'non-exhaustive'

for spec in \
    "function fromMaybe" \
    "constructor Just" \
    "type Maybe" \
    "variable x"; do
    "$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/algebraic-data.hs" \
        --string "haskell_assert $spec" >"$TMP/phrase.out" 2>"$TMP/phrase.err"
    if [[ -s "$TMP/phrase.err" ]]; then
        echo "[haskell] phrase visibility failed: $spec" >&2
        cat "$TMP/phrase.err" >&2
        exit 1
    fi
done
printf '[haskell] %-18s ok\n' 'phrase-visibility'

echo '[haskell] all compatibility tests passed'
