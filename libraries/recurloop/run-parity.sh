#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Debug/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${2:-/tmp/recurloop-core.rli}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[[ -x "$RECURLOOP" ]] || { echo "recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")

"$DIR/build-core.sh" "$RECURLOOP" "$IMAGE" >/dev/null

run_case() {
    local name=$1
    local case_dir="$DIR/parity/$name"
    local legacy_out="$TMP/$name.legacy.out"
    local core_out="$TMP/$name.core.out"

    set +e
    "$RECURLOOP" --file "$case_dir/legacy.rl" >"$legacy_out" 2>"$TMP/$name.legacy.err"
    local legacy_rc=$?
    "$RECURLOOP" --language-image "$IMAGE" --file "$case_dir/core.rl" >"$core_out" 2>"$TMP/$name.core.err"
    local core_rc=$?
    set -e

    if [[ $legacy_rc -ne 0 || $core_rc -ne 0 ]]; then
        echo "[core-parity] $name failed: legacy=$legacy_rc core=$core_rc" >&2
        [[ -s "$TMP/$name.legacy.err" ]] && { echo '--- legacy stderr ---' >&2; cat "$TMP/$name.legacy.err" >&2; }
        [[ -s "$TMP/$name.core.err" ]] && { echo '--- core stderr ---' >&2; cat "$TMP/$name.core.err" >&2; }
        return 1
    fi

    diff -u "$legacy_out" "$core_out"
    printf '[core-parity] %-16s legacy == source-core\n' "$name"
}

for name in functions control-flow records; do
    run_case "$name"
done

echo '[core-parity] selected compatibility surface matches'
