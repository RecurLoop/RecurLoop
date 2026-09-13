#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Debug/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$DIR/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[[ -x "$RECURLOOP" ]] || { echo "recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")
IMAGE="$TMP/core.rli"
"$DIR/build-core.sh" "$RECURLOOP" "$IMAGE" >/dev/null

HELLO="$ROOT/examples/01-getting-started/hello-world/main.rl"
"$RECURLOOP" --file "$HELLO" >"$TMP/default.out" 2>"$TMP/default.err"
"$RECURLOOP" --reset --import "$IMAGE" --file "$HELLO" >"$TMP/import.out" 2>"$TMP/import.err"
diff -u "$TMP/default.out" "$TMP/import.out"
diff -u "$TMP/default.err" "$TMP/import.err"
echo '[core] embedded == reset+import'

set +e
"$RECURLOOP" --reset --string 'print 1' >"$TMP/reset.out" 2>"$TMP/reset.err"
status=$?
set -e
if [[ $status -eq 0 ]] || ! grep -q 'undefined phrase' "$TMP/reset.err"; then
    echo '[core] --reset did not produce an empty language' >&2
    cat "$TMP/reset.err" >&2
    exit 1
fi
echo '[core] reset leaves only the host kernel'

mkdir "$TMP/default-rebuild" "$TMP/explicit-rebuild"
(
    cd "$TMP/default-rebuild"
    "$RECURLOOP" --file "$DIR/core.rl"
)
cmp "$IMAGE" "$TMP/default-rebuild/core.rli"
echo '[core] recurloop --file core.rl reproduces core.rli'

(
    cd "$TMP/explicit-rebuild"
    "$RECURLOOP" --reset --import "$IMAGE" --file "$DIR/core.rl"
)
cmp "$IMAGE" "$TMP/explicit-rebuild/core.rli"
echo '[core] reset+import core.rli + core.rl reproduces core.rli'
