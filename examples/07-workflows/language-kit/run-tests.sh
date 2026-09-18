#!/usr/bin/env bash
set -euo pipefail

RECURLOOP=${1:-build/Release/bin/recurloop}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$DIR/../../.." && pwd)
LIBRARY="$ROOT/libraries/language-kit/library.rl"
KIT_IMAGE=/tmp/recurloop-language-kit.rli
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[[ -x "$RECURLOOP" ]] || { echo "Recurloop executable not found: $RECURLOOP" >&2; exit 2; }
RECURLOOP=$(readlink -f "$RECURLOOP")

# Migration guard: no workflow source may reintroduce the removed Lexer APIs.
if grep -R -n -E 'LanguageKit:(Slice)?Lexer' "$DIR/.." --include='*.rl' >/dev/null; then
    echo '[language-kit] stale LanguageKit Lexer API reference found' >&2
    grep -R -n -E 'LanguageKit:(Slice)?Lexer' "$DIR/.." --include='*.rl' >&2 || true
    exit 1
fi
for migrated in inferred-language; do
    grep -Fq 'LanguageKit:Cursor:' "$ROOT/libraries/inferred/library.rl" || {
        echo "[language-kit] $migrated is not using LanguageKit:Cursor" >&2
        exit 1
    }
done

rm -f "$KIT_IMAGE"
"$RECURLOOP" --file "$LIBRARY" -- "$KIT_IMAGE" >/dev/null
[[ -s "$KIT_IMAGE" ]] || { echo '[language-kit] image was not created' >&2; exit 1; }

# The removed Go/C++ polyglot workflows used to own the cross-language matrix
# in this runner. Keep the LanguageKit gate focused on its remaining contract:
# the reusable image builds, imports in a fresh process, and does not steal an
# ordinary RecurLoop root form. The surviving language workflows exercise the
# dispatcher and runtime APIs with their own focused suites.
printf '42\n' >"$TMP/smoke.expected"
"$RECURLOOP" --import "$KIT_IMAGE" --string 'print 42' >"$TMP/smoke.out"
diff -u "$TMP/smoke.expected" "$TMP/smoke.out"

echo '[language-kit] image build/import smoke test passed'
