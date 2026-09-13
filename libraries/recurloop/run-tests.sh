#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Debug/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGE=/tmp/recurloop-core.rli
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[[ -x "$RECURLOOP" ]] || { echo "recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")

"$DIR/build-core.sh" "$RECURLOOP" "$IMAGE" >/dev/null

run_ok() {
    local name=$1
    local actual="$TMP/$name.out"
    "$RECURLOOP" --language-image "$IMAGE" --file "$DIR/tests/$name.rl" >"$actual"
    diff -u "$DIR/tests/$name.expected" "$actual"
    printf '[minimal-core] %-20s ok\n' "$name"
}

for name in \
    seed-proc \
    seed-shape \
    seed-form \
    seed-growth \
    functions-control \
    defer \
    defer-scope \
    records-methods \
    record-layout
do
    run_ok "$name"
done

# Prove that the image is independently usable without installing the legacy
# language first. --language-image starts from the fixed bootstrap only.
"$RECURLOOP" --language-image "$IMAGE" --file "$DIR/tests/functions-control.rl" >"$TMP/image.out"
diff -u "$DIR/tests/functions-control.expected" "$TMP/image.out"
printf '[minimal-core] %-20s ok\n' 'language-image'

# Keep compatibility import covered while the old default language still exists.
"$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/functions-control.rl" >"$TMP/compat.out"
diff -u "$DIR/tests/functions-control.expected" "$TMP/compat.out"
printf '[minimal-core] %-20s ok\n' 'compat-import'

seed_lines=$(wc -l <"$DIR/bootstrap/seed.rl")
support_lines=$(wc -l <"$DIR/core/10-support.rl")
language_support_lines=$(wc -l <"$DIR/core/20-language-support.rl")
records_lines=$(wc -l <"$DIR/core/30-records.rl")
functions_lines=$(wc -l <"$DIR/core/40-functions.rl")
program_lines=$(wc -l <"$DIR/core/50-program.rl")
image_bytes=$(wc -c <"$IMAGE")
printf '[minimal-core] seed=%d support=%d language=%d records=%d functions=%d program=%d lines; image=%d bytes\n' \
    "$seed_lines" "$support_lines" "$language_support_lines" "$records_lines" "$functions_lines" "$program_lines" "$image_bytes"
echo '[minimal-core] bootstrap + source-defined core passed'
