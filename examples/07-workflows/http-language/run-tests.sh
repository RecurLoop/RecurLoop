#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Debug/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ -x "$RECURLOOP" ]] || { echo "Recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")

# Individual test scripts own their source, request and expected result.
# Set this once so the first test rebuilds the shared image; later tests reuse it.
rm -f /tmp/recurloop-language-kit.rli /tmp/recurloop-http-library.rli
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
