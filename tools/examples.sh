#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:-list}
RECURLOOP=${2:-$ROOT/build/Release/bin/recurloop}
EXAMPLE=${3:-}

workflows=(
    reusable-language-image
    reusable-syntax-image
    language-kit
    shell-language
    inferred-language
    http-language
    source-debugger
    amber-language
    prolog-language
    haskell-language
    erlang-language
)

list_examples() {
    find "$ROOT/examples" \
        -path "$ROOT/examples/07-workflows" -prune -o \
        -name main.rl -printf '%h\n' \
        | sed "s|^$ROOT/examples/||" \
        | sort
    printf '07-workflows/%s\n' "${workflows[@]}"
}

require_binary() {
    [[ -x "$RECURLOOP" ]] || {
        echo "recurloop executable not found: $RECURLOOP" >&2
        exit 2
    }
    RECURLOOP=$(readlink -f "$RECURLOOP")
}

run_workflow() {
    local name=$1
    local dir="$ROOT/examples/07-workflows/$name"
    case "$name" in
        reusable-language-image)
            "$RECURLOOP" --file "$dir/build.rl"
            "$RECURLOOP" --import /tmp/recurloop-phrase-language.rli --file "$dir/use.rl"
            ;;
        reusable-syntax-image)
            "$RECURLOOP" --file "$dir/build.rl"
            "$RECURLOOP" --import /tmp/recurloop-phrase-syntax.rli --file "$dir/use.rl"
            ;;
        source-debugger)
            "$RECURLOOP" --file "$dir/debugger.rl" </dev/null
            ;;
        *)
            [[ -x "$dir/run-tests.sh" ]] || {
                echo "missing workflow runner: $dir/run-tests.sh" >&2
                exit 1
            }
            "$dir/run-tests.sh" "$RECURLOOP"
            ;;
    esac
}

run_example() {
    local name=${1#examples/}
    name=${name%/}
    if [[ -f "$ROOT/examples/$name/main.rl" ]]; then
        "$RECURLOOP" --file "$ROOT/examples/$name/main.rl"
        return
    fi
    name=${name#07-workflows/}
    for workflow in "${workflows[@]}"; do
        if [[ "$name" == "$workflow" ]]; then
            run_workflow "$workflow"
            return
        fi
    done
    echo "unknown example: $1" >&2
    exit 2
}

run_all() {
    mapfile -t core_examples < <(
        find "$ROOT/examples" \
            -path "$ROOT/examples/07-workflows" -prune -o \
            -name main.rl -print | sort
    )

    printf '== Core examples (%d) ==\n' "${#core_examples[@]}"
    local i=0
    for file in "${core_examples[@]}"; do
        i=$((i + 1))
        printf '[core %02d/%02d] %s\n' "$i" "${#core_examples[@]}" "${file#$ROOT/}"
        "$RECURLOOP" --file "$file" >/dev/null
    done

    printf '\n== Workflows (%d) ==\n' "${#workflows[@]}"
    i=0
    for workflow in "${workflows[@]}"; do
        i=$((i + 1))
        printf '\n[workflow %02d/%02d] %s\n' "$i" "${#workflows[@]}" "$workflow"
        run_workflow "$workflow"
    done

    printf '\nAll examples and workflows passed.\n'
}

case "$MODE" in
    list)
        list_examples
        ;;
    run)
        require_binary
        [[ -n "$EXAMPLE" ]] || { echo 'example name is required' >&2; exit 2; }
        run_example "$EXAMPLE"
        ;;
    all)
        require_binary
        run_all
        ;;
    *)
        echo "usage: $0 {list|run|all} [recurloop] [example]" >&2
        exit 2
        ;;
esac
