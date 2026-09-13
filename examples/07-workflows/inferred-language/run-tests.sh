#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Debug/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
KIT_IMAGE=/tmp/recurloop-language-kit.rli
IMAGE=/tmp/recurloop-inferred-library.rli
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[[ -x "$RECURLOOP" ]] || { echo "Recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")

rm -f "$KIT_IMAGE" "$IMAGE"
"$RECURLOOP" --file "$DIR/../language-kit/library.rl" >/dev/null
"$RECURLOOP" --import "$KIT_IMAGE" --file "$DIR/library.rl" >/dev/null
[[ -s "$IMAGE" ]] || { echo '[inferred] image was not created' >&2; exit 1; }

run_ok() {
    local name=$1
    local actual="$TMP/$name.out"
    "$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/$name.infer" >"$actual"
    diff -u "$DIR/tests/$name.expected" "$actual"
    printf '[inferred] %-20s ok\n' "$name"
}

for name in lazy-specialization control-flow recursion shared-interop selectors phrase-visibility shared-reader; do
    run_ok "$name"
done

echo '[inferred] all native lazy-specialization tests passed'
