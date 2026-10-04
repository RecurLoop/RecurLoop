#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Release/bin/recurloop}

DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$DIR/../../.." && pwd)
KIT_LIBRARY="$ROOT/libraries/language-kit/library.rl"
SHELL_LIBRARY="$ROOT/libraries/shell/library.rl"

TMP=$(mktemp -d)
KIT_IMAGE="$TMP/language-kit.rli"
IMAGE="$TMP/library.rli"
COMPILED="$TMP/recurloop-shell-functions"

cleanup() {
    rm -rf "$TMP"
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

# The stdio server uses the same command handler as the interactive REPL.
# Check that stripping transport newlines does not suppress shell execution.
printf 'echo "test"\nprint 42\necho "again"\n:quit\n' \
    | "$RECURLOOP" --import "$IMAGE" --serve >"$TMP/repl.out"
printf 'test\n42\nagain\n' >"$TMP/repl.expected"
diff -u "$TMP/repl.expected" "$TMP/repl.out"

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

    sed "s#/tmp/recurloop-#$TMP/recurloop-#g" "$source" >"$TMP/$name.rl"
    "$RECURLOOP" \
        --import "$IMAGE" \
        --file "$TMP/$name.rl" \
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
run_ok conditional
run_ok explicit-selector
run_ok preference-block

#
# Compiled-function test.
#
# compiled-functions.rl emits:
#
#   /tmp/recurloop-shell-functions
#

sed "s#/tmp/recurloop-#$TMP/recurloop-#g" "$DIR/tests/compiled-functions.rl" >"$TMP/compiled-functions.rl"
"$RECURLOOP" \
    --import "$IMAGE" \
    --file "$TMP/compiled-functions.rl" \
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
sed "s#/tmp/recurloop-#$TMP/recurloop-#g" "$DIR/bash_like.rl" >"$TMP/bash_like.rl"
sed "s#/tmp/recurloop-#$TMP/recurloop-#g" "$DIR/example.rl" >"$TMP/example.rl"

"$RECURLOOP" --import "$IMAGE" --file "$TMP/bash_like.rl" >"$TMP/legacy-bash-like-build.out"
if [[ ! -x "$TMP/recurloop-bash-like" ]]; then
    echo "[shell] legacy bash_like executable was not created" >&2
    exit 1
fi
"$TMP/recurloop-bash-like" >"$TMP/legacy-bash-like.out"
diff -u "$DIR/tests/legacy-bash-like.expected" "$TMP/legacy-bash-like.out"
printf '[shell] %-20s ok\n' "legacy-bash-like"

"$RECURLOOP" --import "$IMAGE" --file "$TMP/example.rl" >"$TMP/legacy-example-build.out"
if [[ ! -x "$TMP/recurloop-shell-app-example" ]]; then
    echo "[shell] legacy application executable was not created" >&2
    exit 1
fi
"$TMP/recurloop-shell-app-example" >"$TMP/legacy-example.out"
diff -u "$DIR/tests/legacy-example.expected" "$TMP/legacy-example.out"
printf '[shell] %-20s ok\n' "legacy-example"

echo "[shell] all compatibility tests passed"
