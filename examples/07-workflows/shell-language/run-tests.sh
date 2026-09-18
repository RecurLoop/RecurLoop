#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Release/bin/recurloop}

DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$DIR/../../.." && pwd)
KIT_LIBRARY="$ROOT/libraries/language-kit/library.rl"
SHELL_LIBRARY="$ROOT/libraries/shell/library.rl"

KIT_IMAGE=/tmp/recurloop-language-kit.rli
IMAGE=/tmp/recurloop-shell-library.rli
COMPILED=/tmp/recurloop-shell-functions

TMP=$(mktemp -d)

cleanup() {
    rm -rf "$TMP"
    rm -f "$COMPILED"
}

trap cleanup EXIT

if [[ ! -x "$RECURLOOP" ]]; then
    echo "Recurloop executable not found: $RECURLOOP" >&2
    exit 2
fi

RECURLOOP=$(readlink -f "$RECURLOOP")

rm -f \
    "$KIT_IMAGE" \
    "$IMAGE" \
    "$COMPILED"

#
# Build LanguageKit image.
#

"$RECURLOOP" \
    --file "$KIT_LIBRARY" \
    -- "$KIT_IMAGE" \
    >/dev/null

if [[ ! -s "$KIT_IMAGE" ]]; then
    echo "[shell] LanguageKit image was not created: $KIT_IMAGE" >&2
    exit 1
fi

#
# Build Shell image on top of LanguageKit.
#

"$RECURLOOP" \
    --import "$KIT_IMAGE" \
    --file "$SHELL_LIBRARY" \
    -- "$IMAGE" \
    >/dev/null

if [[ ! -s "$IMAGE" ]]; then
    echo "[shell] Shell image was not created: $IMAGE" >&2
    exit 1
fi

#
# Run an ordinary source-file test.
#
# Expected layout:
#
#   tests/<name>.rl
#   tests/<name>.expected
#

run_ok() {
    local name=$1
    local source="$DIR/tests/$name.rl"
    local expected="$DIR/tests/$name.expected"
    local actual="$TMP/$name.out"

    if [[ ! -f "$source" ]]; then
        echo "[shell] missing test source: $source" >&2
        exit 1
    fi

    if [[ ! -f "$expected" ]]; then
        echo "[shell] missing expected output: $expected" >&2
        exit 1
    fi

    "$RECURLOOP" \
        --import "$IMAGE" \
        --file "$source" \
        >"$actual"

    if ! diff -u "$expected" "$actual"; then
        echo "[shell] $name failed" >&2
        exit 1
    fi

    printf '[shell] %-20s ok\n' "$name"
}

#
# Normal interpreted/source tests.
#

run_ok top-level
run_ok direct-top-level
run_ok pipeline
run_ok explicit-selector
run_ok preference-block

#
# Compiled-function test.
#
# compiled-functions.rl emits:
#
#   /tmp/recurloop-shell-functions
#

"$RECURLOOP" \
    --import "$IMAGE" \
    --file "$DIR/tests/compiled-functions.rl" \
    >/dev/null

if [[ ! -x "$COMPILED" ]]; then
    echo "[shell] compiled executable was not created: $COMPILED" >&2
    exit 1
fi

"$COMPILED" >"$TMP/compiled-functions.out"

if ! diff -u \
    "$DIR/tests/compiled-functions.expected" \
    "$TMP/compiled-functions.out"
then
    echo "[shell] compiled-functions failed" >&2
    exit 1
fi

printf '[shell] %-20s ok\n' "compiled-functions"

# Keep the two larger shell application examples from the stable tree as
# compatibility regressions. They exercise asynchronous Invocation objects,
# native pipeline stages and importing the shell library into an application.
rm -f /tmp/recurloop-bash-like /tmp/recurloop-shell-app-example

"$RECURLOOP" --import "$IMAGE" --file "$DIR/bash_like.rl" >"$TMP/legacy-bash-like-build.out"
if [[ ! -x /tmp/recurloop-bash-like ]]; then
    echo "[shell] legacy bash_like executable was not created" >&2
    exit 1
fi
/tmp/recurloop-bash-like >"$TMP/legacy-bash-like.out"
diff -u "$DIR/tests/legacy-bash-like.expected" "$TMP/legacy-bash-like.out"
printf '[shell] %-20s ok\n' "legacy-bash-like"

"$RECURLOOP" --import "$IMAGE" --file "$DIR/example.rl" >"$TMP/legacy-example-build.out"
if [[ ! -x /tmp/recurloop-shell-app-example ]]; then
    echo "[shell] legacy application executable was not created" >&2
    exit 1
fi
/tmp/recurloop-shell-app-example >"$TMP/legacy-example.out"
diff -u "$DIR/tests/legacy-example.expected" "$TMP/legacy-example.out"
printf '[shell] %-20s ok\n' "legacy-example"

echo "[shell] all compatibility tests passed"
