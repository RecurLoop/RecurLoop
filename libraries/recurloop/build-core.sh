#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Release/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${2:-core.rli}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[[ -x "$RECURLOOP" ]] || { echo "recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")
IMAGE=$(readlink -m "$IMAGE")
mkdir -p "$(dirname -- "$IMAGE")"

(
    cd "$TMP"
    "$RECURLOOP" --file "$DIR/core.rl"
)
[[ -s "$TMP/core.rli" ]] || { echo 'core.rl did not create core.rli' >&2; exit 1; }
mv "$TMP/core.rli" "$IMAGE"
printf '%s\n' "$IMAGE"
