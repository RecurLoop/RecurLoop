#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Debug/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${2:-/tmp/recurloop-core.rli}

[[ -x "$RECURLOOP" ]] || { echo "recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")

rm -f /tmp/recurloop-core.rli "$IMAGE"
"$RECURLOOP" --bootstrap --file "$DIR/core.rl"
[[ -s /tmp/recurloop-core.rli ]] || { echo 'source-defined core image was not created' >&2; exit 1; }
if [[ "$IMAGE" != /tmp/recurloop-core.rli ]]; then
    cp /tmp/recurloop-core.rli "$IMAGE"
fi
printf '%s\n' "$IMAGE"
