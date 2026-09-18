#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/http-test-lib.sh"
http_prepare "${1:-build/Release/bin/recurloop}"

SERVER=/tmp/recurloop-http-production-test-server
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

rm -f "$SERVER"
"$HTTP_RECURLOOP" --import "$HTTP_IMAGE" --file "$DIR/production.rl" >"$TMP/build.out" 2>"$TMP/build.err"
[[ -x "$SERVER" ]] || { cat "$TMP/build.err" >&2; exit 1; }

readelf -h "$SERVER" | grep -q 'DYN (Position-Independent Executable file)'
readelf -d "$SERVER" | grep -q 'BIND_NOW'
if readelf -S "$SERVER" | grep -q '\.recurloop\.language'; then
    echo 'production HTTP executable unexpectedly embeds .recurloop.language' >&2
    exit 1
fi
nm -D "$SERVER" | grep -q '__memcpy_chk'
nm -D "$SERVER" | grep -q '__snprintf_chk'

"$SERVER" >"$TMP/server.out" 2>"$TMP/server.err" &
server_pid=$!

CLIENT="$TMP/production-client"
"${CXX:-clang++}" -std=c++23 -O2 "$DIR/production_client.cpp" -o "$CLIENT"
"$CLIENT"

kill "$server_pid"
wait "$server_pid" 2>/dev/null || true
server_pid=''
echo '[http] production hardening/parser/workers ok'
