#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/http-test-lib.sh"
http_prepare "${1:-build/Debug/bin/recurloop}"

TMP=$(mktemp -d)
server_pid=''
cleanup() {
    if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

# Feed the source through stdin on purpose. This is the same root/interactive
# path used when a user pastes `engine import ...` followed by `http ... {}`.
"$HTTP_RECURLOOP" - <"$DIR/top-level.rl" >"$TMP/out" 2>"$TMP/err" &
server_pid=$!

response=''
for _ in {1..80}; do
    if response=$(curl --silent --show-error --connect-timeout 0.2 --max-time 1 \
        --request POST --data-binary 'top-level-ok' http://127.0.0.1:18087/echo 2>"$TMP/curl.err"); then
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        cat "$TMP/err" >&2
        exit 1
    fi
    sleep 0.05
done

[[ "$response" == 'top-level-ok' ]] || {
    echo "top-level HTTP response mismatch: '$response'" >&2
    cat "$TMP/err" >&2
    exit 1
}

kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
server_pid=''
echo '[http] top-level stdin server ok'
