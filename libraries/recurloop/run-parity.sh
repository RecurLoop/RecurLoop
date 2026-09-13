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

mapfile -t files < <(find "$ROOT/examples" -path "$ROOT/examples/07-workflows" -prune -o -name main.rl -print | sort)
for file in "${files[@]}"; do
    name=${file#"$ROOT/"}
    set +e
    "$RECURLOOP" --file "$file" >"$TMP/a.out" 2>"$TMP/a.err"
    a=$?
    "$RECURLOOP" --reset --import "$IMAGE" --file "$file" >"$TMP/b.out" 2>"$TMP/b.err"
    b=$?
    set -e
    [[ $a -eq $b ]] || { echo "[core-parity] status mismatch: $name ($a != $b)" >&2; exit 1; }
    # Runtime timing values are intentionally nondeterministic. Preserve the
    # diagnostic shape and call counts while normalizing only elapsed seconds.
    sed -E 's/[0-9]+\.[0-9]+ s/<time>/g' "$TMP/a.out" >"$TMP/a.norm.out"
    sed -E 's/[0-9]+\.[0-9]+ s/<time>/g' "$TMP/b.out" >"$TMP/b.norm.out"
    sed -E 's/[0-9]+\.[0-9]+ s/<time>/g' "$TMP/a.err" >"$TMP/a.norm.err"
    sed -E 's/[0-9]+\.[0-9]+ s/<time>/g' "$TMP/b.err" >"$TMP/b.norm.err"
    diff -u "$TMP/a.norm.out" "$TMP/b.norm.out"
    diff -u "$TMP/a.norm.err" "$TMP/b.norm.err"
    printf '[core-parity] %s ok\n' "$name"
done
printf '[core-parity] %d real examples match embedded core and reset+import core\n' "${#files[@]}"
