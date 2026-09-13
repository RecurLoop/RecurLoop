#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/http-test-lib.sh"
http_prepare "${1:-build/Debug/bin/recurloop}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
http_start_once "$DIR/head.rl" "$TMP/server.out" "$TMP/server.err"
pid=$HTTP_SERVER_PID
ok=0
for attempt in {1..40}; do
    if curl -sS -I --connect-timeout 0.2 --max-time 2 \
        'http://127.0.0.1:18084/' >"$TMP/response" 2>"$TMP/curl.err"; then
        ok=1; break
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
done
http_finish_server "$pid" "$TMP/server.err"
[[ $ok -eq 1 ]] || { cat "$TMP/curl.err" >&2; exit 1; }
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    grep -Fq "$line" "$TMP/response" || { echo "missing response header: $line" >&2; cat "$TMP/response" >&2; exit 1; }
done < "$DIR/head.expected"
echo '[http] head ok'
