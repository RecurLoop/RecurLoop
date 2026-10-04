#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Release/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ -x "$RECURLOOP" ]] || { echo "Recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")

# Individual test scripts own their source, request and expected result.
# Set this once so the first test rebuilds the shared image; later tests reuse it.
HTTP_IMAGE_DIR=$(mktemp -d)
export HTTP_IMAGE_DIR
trap 'rm -rf "$HTTP_IMAGE_DIR"' EXIT
first=1
for test in "$DIR"/tests/*.test.sh; do
    if [[ $first -eq 1 ]]; then
        HTTP_REBUILD_IMAGE=1 "$test" "$RECURLOOP"
        first=0
    else
        "$test" "$RECURLOOP"
    fi
done

echo '[http] all HTTP language tests passed'
