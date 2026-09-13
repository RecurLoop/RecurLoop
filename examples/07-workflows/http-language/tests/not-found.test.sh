#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/http-test-lib.sh"
http_prepare "${1:-build/Debug/bin/recurloop}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
http_start_once "$DIR/not-found.rl" "$TMP/server.out" "$TMP/server.err"
pid=$HTTP_SERVER_PID
status=''
for attempt in {1..40}; do
    status=$(curl -s -o "$TMP/response" -w '%{http_code}' --connect-timeout 0.2 --max-time 2 \
        'http://127.0.0.1:18083/missing' || true)
    [[ "$status" == 404 ]] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
done
http_finish_server "$pid" "$TMP/server.err"
[[ "$status" == 404 ]] || { echo "expected HTTP 404, got: $status" >&2; exit 1; }
http_compare_text "$DIR/not-found.expected" "$TMP/response"
echo '[http] not-found ok'
