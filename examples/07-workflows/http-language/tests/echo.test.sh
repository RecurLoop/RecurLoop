#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/http-test-lib.sh"
http_prepare "${1:-build/Release/bin/recurloop}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
http_start_once "$DIR/echo.rl" "$TMP/server.out" "$TMP/server.err"
pid=$HTTP_SERVER_PID
http_curl_retry "$pid" "$TMP/response" "$TMP/curl.err" \
    -X POST --data-binary 'hello-body' 'http://127.0.0.1:18081/echo' || {
    cat "$TMP/curl.err" >&2; exit 1;
}
http_finish_server "$pid" "$TMP/server.err"
http_compare_text "$DIR/echo.expected" "$TMP/response"
echo '[http] echo ok'
