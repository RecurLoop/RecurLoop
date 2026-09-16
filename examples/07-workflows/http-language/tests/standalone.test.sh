#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/http-test-lib.sh"
http_prepare "${1:-build/Debug/bin/recurloop}"

HTTP_EXECUTABLE=/tmp/recurloop-http-server-test
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

# The public example intentionally uses 8080. Tests use a private high port so
# they remain deterministic on developer machines that already have 8080 open.
sed \
    -e 's#emit executable "/tmp/recurloop-http-server"#emit executable "/tmp/recurloop-http-server-test"#' \
    -e 's/http "127\.0\.0\.1" 8080 limits/http "127.0.0.1" 18085 limits/' \
    "$HTTP_DIR/standalone.rl" >"$TMP/standalone.rl"

rm -f "$HTTP_EXECUTABLE"
"$HTTP_RECURLOOP" --import "$HTTP_IMAGE" --file "$TMP/standalone.rl"
[[ -x "$HTTP_EXECUTABLE" ]] || { echo "HTTP executable was not created: $HTTP_EXECUTABLE" >&2; exit 1; }

if readelf -S "$HTTP_EXECUTABLE" | grep -q '\.recurloop\.language'; then
    echo 'standalone production example unexpectedly embeds .recurloop.language' >&2
    exit 1
fi
nm -D "$HTTP_EXECUTABLE" | grep -q '__memcpy_chk'
nm -D "$HTTP_EXECUTABLE" | grep -q '__snprintf_chk'

"$HTTP_EXECUTABLE" >"$TMP/server.out" 2>"$TMP/server.err" &
server_pid=$!
http_curl_retry "$server_pid" "$TMP/response" "$TMP/curl.err" \
    -X POST --data-binary 'standalone-body' 'http://127.0.0.1:18085/echo' || {
    cat "$TMP/curl.err" >&2
    cat "$TMP/server.err" >&2
    exit 1
}
printf 'standalone-body' >"$TMP/expected"
http_compare_text "$TMP/expected" "$TMP/response"

kill "$server_pid"
wait "$server_pid" 2>/dev/null || true
server_pid=''
echo '[http] standalone executable ok'
