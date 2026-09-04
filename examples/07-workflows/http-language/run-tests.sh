#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /absolute/path/to/recurloop" >&2
    exit 2
fi

RECURLOOP="$(readlink -f "$1")"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=/tmp/recurloop-http-library.rli
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$RECURLOOP" --file "$DIR/library.rl" >"$TMP/build.out" 2>"$TMP/build.err"
[[ -s "$IMAGE" ]] || {
    echo '[http] image was not created' >&2
    cat "$TMP/build.err" >&2
    exit 1
}

wait_for_port() {
    local port="$1"
    local pid="$2"
    local i
    for i in {1..50}; do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" || true
            echo "[http] server exited before listening on $port" >&2
            return 1
        fi
        if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
            exec 3>&-
            exec 3<&-
            # The readiness probe itself consumes an `http once` connection,
            # so this helper is intentionally unused for once-mode tests.
            return 0
        fi
        sleep 0.05
    done
    echo "[http] timeout waiting for port $port" >&2
    return 1
}

run_once() {
    local name="$1"
    local file="$2"
    local port="$3"
    shift 3

    "$RECURLOOP" --import "$IMAGE" --file "$file" \
        >"$TMP/$name.server.out" 2>"$TMP/$name.server.err" &
    local pid=$!

    # Avoid a TCP readiness probe because `http once` intentionally accepts a
    # single connection. curl retries until bind/listen is ready instead.
    local ok=0
    local attempt
    for attempt in {1..40}; do
        if curl --silent --show-error --fail-with-body \
            --connect-timeout 0.2 --max-time 2 \
            "$@" >"$TMP/$name.response" 2>"$TMP/$name.curl.err"; then
            ok=1
            break
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.05
    done

    wait "$pid" || {
        echo "[http] $name: server failed" >&2
        cat "$TMP/$name.server.err" >&2
        return 1
    }

    if [[ $ok -ne 1 ]]; then
        echo "[http] $name: curl failed" >&2
        cat "$TMP/$name.curl.err" >&2
        cat "$TMP/$name.server.err" >&2
        return 1
    fi
}

run_once query-header "$DIR/tests/once.rl" 18080 \
    -H 'X-Test: yes' 'http://127.0.0.1:18080/hello?name=Recur%20Loop'
grep -qx 'Recur Loop' "$TMP/query-header.response"
printf '[http] %-20s ok\n' 'query-header'

run_once echo "$DIR/tests/echo.rl" 18081 \
    -X POST --data-binary 'hello-body' 'http://127.0.0.1:18081/echo'
grep -qx 'hello-body' "$TMP/echo.response"
printf '[http] %-20s ok\n' 'request-body'

run_once wildcard "$DIR/tests/wildcard.rl" 18082 \
    'http://127.0.0.1:18082/assets/app.js'
grep -qx '/assets/app.js' "$TMP/wildcard.response"
printf '[http] %-20s ok\n' 'wildcard-route'

# 404 is expected, so do not use --fail-with-body for this one.
"$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/not-found.rl" \
    >"$TMP/notfound.server.out" 2>"$TMP/notfound.server.err" &
pid=$!
status=""
for attempt in {1..40}; do
    status="$(curl -s -o "$TMP/notfound.response" -w '%{http_code}' --connect-timeout 0.2 --max-time 2 'http://127.0.0.1:18083/missing' || true)"
    if [[ "$status" == 404 ]]; then break; fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.05
done
wait "$pid"
[[ "$status" == 404 ]]
grep -qx '404 Not Found' "$TMP/notfound.response"
printf '[http] %-20s ok\n' 'not-found'

# HEAD falls back to a matching GET route and suppresses the body.
"$RECURLOOP" --import "$IMAGE" --file "$DIR/tests/head.rl" \
    >"$TMP/head.server.out" 2>"$TMP/head.server.err" &
pid=$!
head_ok=0
for attempt in {1..40}; do
    if curl -sS -I --connect-timeout 0.2 --max-time 2 'http://127.0.0.1:18084/' >"$TMP/head.response" 2>/dev/null; then
        head_ok=1
        break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.05
done
wait "$pid"
[[ $head_ok -eq 1 ]]
grep -q '^HTTP/1.1 200 OK' "$TMP/head.response"
grep -q '^Content-Length: 5' "$TMP/head.response"
printf '[http] %-20s ok\n' 'head-as-get'

echo '[http] all HTTP language tests passed'
