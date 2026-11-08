#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Release/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RECURLOOP=$(readlink -f "$RECURLOOP")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Exercise the copied starter outside the checkout, including paths with spaces.
WORKSPACE="$TMP/my application"
mkdir -p "$WORKSPACE"
cp -R "$DIR/src" "$DIR/tests" "$DIR/docs" "$DIR/.vscode" "$WORKSPACE/"
cp "$DIR/recurloop.project.rl" "$DIR/recurloop.docs" "$WORKSPACE/"
if [[ -d "$(dirname -- "$RECURLOOP")/../libraries" ]]; then
    export RECURLOOP_LIBRARY_PATH="$(cd -- "$(dirname -- "$RECURLOOP")/../libraries" && pwd)${RECURLOOP_LIBRARY_PATH:+:$RECURLOOP_LIBRARY_PATH}"
fi
cd "$WORKSPACE"
printf '42\n' > "$TMP/expected"

"$RECURLOOP" --targets > "$TMP/targets"
for target in run build build-debug debug test docs clean; do
    grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"$target\"" "$TMP/targets"
done
[[ ! -e build ]]
"$RECURLOOP" --target test
[[ ! -e build ]]

# Running, building and exporting must not invoke tests as hidden dependencies.
printf 'assert false\n' > tests/main.rl
"$RECURLOOP" --target run > "$TMP/run"
diff -u "$TMP/expected" "$TMP/run"
[[ ! -e build ]]
if "$RECURLOOP" --target test > "$TMP/failed-test" 2>&1; then
    echo '[application-project] a failing assertion was ignored' >&2
    exit 1
fi

"$RECURLOOP" --target build
./build/app > "$TMP/native"
diff -u "$TMP/expected" "$TMP/native"
"$RECURLOOP" --target build-debug
./build/app-debug > "$TMP/native-debug"
diff -u "$TMP/expected" "$TMP/native-debug"

"$RECURLOOP" --target docs > "$TMP/export"
[[ ! -s "$TMP/export" ]]
[[ -s build/docs/my-application.json ]]
"$RECURLOOP" --docs show overview --from build/docs/my-application.json > "$TMP/overview"
grep -Fq 'My application' "$TMP/overview"
"$RECURLOOP" --docs search 'answer' --from build/docs/my-application.json --json > "$TMP/search"
grep -Fq 'Application:answer' "$TMP/search"
"$RECURLOOP" --docs list --from build/docs/my-application.json --json > "$TMP/pages"
grep -Fq '"total":3' "$TMP/pages"

"$RECURLOOP" --target clean
[[ ! -e build && -f src/main.rl && -f tests/main.rl && -f docs/overview.rl ]]
"$RECURLOOP" --target docs
[[ -s build/docs/my-application.json && ! -e build/app ]]
"$RECURLOOP" --target clean
echo '[application-project] targets, native builds, independent tests, documentation roundtrip and clean passed'
