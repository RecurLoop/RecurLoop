#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/http-test-lib.sh"
http_prepare "${1:-build/Release/bin/recurloop}"
TMP=$(mktemp -d)
pid=''
cleanup() {
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT
http_start_once "$DIR/phrase-grammar.rl" "$TMP/server.out" "$TMP/server.err"
pid=$HTTP_SERVER_PID
http_curl_retry "$pid" "$TMP/response" "$TMP/curl.err" 'http://127.0.0.1:18089/phrases' || {
    cat "$TMP/server.err" "$TMP/curl.err" >&2; exit 1;
}
http_finish_server "$pid" "$TMP/server.err"
http_compare_text "$DIR/phrase-grammar.expected" "$TMP/response"
pid=''
echo '[http] phrase grammar and opaque native handlers ok'
