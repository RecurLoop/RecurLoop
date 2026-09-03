#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Debug/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGE=/tmp/recurloop-prolog-library.rli
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [[ ! -x "$RECURLOOP" ]]; then
    echo "Recurloop executable not found or not executable: $RECURLOOP" >&2
    exit 2
fi

rm -f "$IMAGE"
"$RECURLOOP" --file "$DIR/library.rl" >/dev/null

if [[ ! -s "$IMAGE" ]]; then
    echo "Prolog language image was not produced: $IMAGE" >&2
    exit 1
fi

run_case() {
    local name=$1
    local source="$DIR/tests/$name.pl"
    local expected="$TMP/$name.expected"
    local actual="$TMP/$name.actual"

    cat >"$expected"
    "$RECURLOOP" --import "$IMAGE" --file "$source" >"$actual"

    if ! diff -u "$expected" "$actual"; then
        echo "Prolog compatibility test failed: $name" >&2
        exit 1
    fi
    printf '[prolog] %-14s ok\n' "$name"
}

run_case family <<'EOF_EXPECTED'
X = bob.
X = ann.
X = pat.
X = jim.
EOF_EXPECTED

run_case lists <<'EOF_EXPECTED'
X = 1.
X = 2.
X = 3.
Head = 1, Tail = [2, 3].
EOF_EXPECTED

run_case backtracking <<'EOF_EXPECTED'
X = a, Y = a.
X = a, Y = b.
X = b, Y = a.
X = b, Y = b.
EOF_EXPECTED

run_case unification <<'EOF_EXPECTED'
X = 1, Y = 2.
X = alpha.
false.
EOF_EXPECTED

run_case failure <<'EOF_EXPECTED'
true.
false.
true.
false.
EOF_EXPECTED

for spec in \
    "predicate ancestor" \
    "atom parent" \
    "variable X" \
    "builtin true" \
    "operator :-"; do
    "$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/family.pl" \
        --string "prolog_assert $spec" >/dev/null
 done
printf '[prolog] %-14s ok\n' 'phrase-visibility'
printf '[prolog] all compatibility tests passed\n'
