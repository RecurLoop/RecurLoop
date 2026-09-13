#!/usr/bin/env bash
set -euo pipefail

HTTP_TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HTTP_DIR=$(cd -- "$HTTP_TEST_DIR/.." && pwd)
HTTP_REPO_ROOT=$(cd -- "$HTTP_DIR/../../.." && pwd)
HTTP_IMAGE=/tmp/recurloop-http-library.rli
HTTP_KIT_IMAGE=/tmp/recurloop-language-kit.rli

http_prepare() {
    local recurloop=${1:-build/Debug/bin/recurloop}
    [[ -x "$recurloop" ]] || { echo "Recurloop executable not found: $recurloop" >&2; return 2; }
    HTTP_RECURLOOP=$(readlink -f "$recurloop")

    if [[ ! -s "$HTTP_IMAGE" || "${HTTP_REBUILD_IMAGE:-0}" == 1 ]]; then
        "$HTTP_RECURLOOP" --file "$HTTP_DIR/../language-kit/library.rl" >/dev/null
        "$HTTP_RECURLOOP" --import "$HTTP_KIT_IMAGE" --file "$HTTP_DIR/library.rl" >/dev/null
    fi
    [[ -s "$HTTP_IMAGE" ]] || { echo "HTTP image was not created: $HTTP_IMAGE" >&2; return 1; }
}

http_start_once() {
    local source=$1
    local out=$2
    local err=$3
    "$HTTP_RECURLOOP" --import "$HTTP_IMAGE" --file "$source" >"$out" 2>"$err" &
    HTTP_SERVER_PID=$!
}

http_curl_retry() {
    local pid=$1
    local out=$2
    local err=$3
    shift 3
    local attempt
    for attempt in {1..40}; do
        if curl --silent --show-error --connect-timeout 0.2 --max-time 2 "$@" >"$out" 2>"$err"; then
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.05
    done
    return 1
}

http_finish_server() {
    local pid=$1
    local err=$2
    if ! wait "$pid"; then
        echo "HTTP server failed" >&2
        cat "$err" >&2
        return 1
    fi
}

http_compare_text() {
    local expected=$1
    local actual=$2
    if [[ "$(cat "$actual")" != "$(cat "$expected")" ]]; then
        echo 'HTTP response mismatch' >&2
        echo '--- expected' >&2
        cat "$expected" >&2
        echo >&2
        echo '--- actual' >&2
        cat "$actual" >&2
        echo >&2
        return 1
    fi
}
