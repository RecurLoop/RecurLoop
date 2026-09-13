#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Debug/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$DIR/../.." && pwd)
IMAGE=${2:-/tmp/recurloop-core.rli}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP" /tmp/recurloop-records-and-methods' EXIT

[[ -x "$RECURLOOP" ]] || { echo "recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")

"$DIR/build-core.sh" "$RECURLOOP" "$IMAGE" >/dev/null

run_pair() {
    local name=$1
    local legacy_source=$2
    local core_source=$3
    local legacy_out="$TMP/$name.legacy.out"
    local core_out="$TMP/$name.core.out"
    local legacy_err="$TMP/$name.legacy.err"
    local core_err="$TMP/$name.core.err"

    set +e
    "$RECURLOOP" --file "$legacy_source" >"$legacy_out" 2>"$legacy_err"
    local legacy_rc=$?
    "$RECURLOOP" --language-image "$IMAGE" --file "$core_source" >"$core_out" 2>"$core_err"
    local core_rc=$?
    set -e

    if [[ $legacy_rc -ne $core_rc ]]; then
        echo "[core-parity] $name status mismatch: legacy=$legacy_rc core=$core_rc" >&2
        [[ -s "$legacy_err" ]] && { echo '--- legacy stderr ---' >&2; cat "$legacy_err" >&2; }
        [[ -s "$core_err" ]] && { echo '--- core stderr ---' >&2; cat "$core_err" >&2; }
        return 1
    fi
    if [[ $legacy_rc -ne 0 ]]; then
        echo "[core-parity] $name failed on both paths with status $legacy_rc" >&2
        echo '--- legacy stderr ---' >&2; cat "$legacy_err" >&2
        echo '--- core stderr ---' >&2; cat "$core_err" >&2
        return 1
    fi

    diff -u "$legacy_out" "$core_out"
    diff -u "$legacy_err" "$core_err"
    printf '[core-parity] %-18s legacy == source-core\n' "$name"
}

# The first four cases use the repository's real getting-started examples as
# the compatibility reference. The source-core side implements the same
# observable program through the library-defined language.
run_pair functions \
    "$ROOT/examples/01-getting-started/functions-and-recursion/main.rl" \
    "$DIR/parity/functions/core.rl"
run_pair control-flow \
    "$ROOT/examples/01-getting-started/values-and-control-flow/main.rl" \
    "$DIR/parity/control-flow/core.rl"
run_pair records \
    "$ROOT/examples/01-getting-started/records-and-methods/main.rl" \
    "$DIR/parity/records/core.rl"
run_pair lifetime-null \
    "$ROOT/examples/01-getting-started/lifetime-and-null/main.rl" \
    "$DIR/parity/lifetime-null/core.rl"

# Focused parity cases exercise library features not isolated by a single
# getting-started example.
for name in defer function-values null-pointers extern-interop; do
    run_pair "$name" "$DIR/parity/$name/legacy.rl" "$DIR/parity/$name/core.rl"
done

echo '[core-parity] compatibility surface matches (8 areas; 4 real examples)'
