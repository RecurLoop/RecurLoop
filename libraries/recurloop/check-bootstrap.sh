#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Debug/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[[ -x "$RECURLOOP" ]] || { echo "recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")

# Positive contract: the fixed host can load the seed and the seed can define
# proc/form/shape without the compatibility language being installed.
"$RECURLOOP" --bootstrap \
    --file "$DIR/bootstrap/seed.rl" \
    --file "$DIR/tests/seed-proc.rl" >"$TMP/positive.out" 2>"$TMP/positive.err"
printf 'proc=42\n' >"$TMP/positive.expected"
diff -u "$TMP/positive.expected" "$TMP/positive.out"
test ! -s "$TMP/positive.err"

# Negative contract: ordinary RecurLoop language roots are library/default-mode
# concerns, not part of the fixed bootstrap surface.
check_forbidden() {
    local name=$1
    local source=$2
    set +e
    "$RECURLOOP" --bootstrap --string "$source" >"$TMP/$name.out" 2>"$TMP/$name.err"
    local rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
        echo "[bootstrap-contract] unexpectedly accepted $name: $source" >&2
        return 1
    fi
}

check_forbidden print 'print 1'
check_forbidden record 'record X { value:i64 }'
check_forbidden control 'if true { }'
check_forbidden debugger 'debug:ping'
check_forbidden emit 'emit raw "/tmp/recurloop-bootstrap-contract.raw" { 1 }'

echo '[bootstrap-contract] fixed host surface is isolated from compatibility language'
