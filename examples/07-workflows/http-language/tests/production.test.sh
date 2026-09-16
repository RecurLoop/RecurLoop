#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/http-test-lib.sh"
http_prepare "${1:-build/Debug/bin/recurloop}"

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

python3 - <<'PY'
import socket
import time

ADDR = ("127.0.0.1", 18086)

def connect():
    deadline = time.monotonic() + 3
    while True:
        try:
            s = socket.create_connection(ADDR, timeout=.25)
            s.settimeout(3)
            return s
        except OSError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(.03)

def exchange(raw: bytes):
    s = connect()
    s.sendall(raw)
    data = b""
    while True:
        part = s.recv(65536)
        if not part:
            break
        data += part
    s.close()
    line, _, rest = data.partition(b"\r\n")
    _, _, body = rest.partition(b"\r\n\r\n")
    return line, body

def expect(name, raw, status, body=None):
    line, actual_body = exchange(raw)
    prefix = f"HTTP/1.1 {status} ".encode()
    if not line.startswith(prefix):
        raise AssertionError(f"{name}: {line!r}")
    if body is not None and actual_body != body:
        raise AssertionError(f"{name}: body {actual_body!r} != {body!r}")

expect("health", b"GET /health HTTP/1.1\r\nHost: x\r\n\r\n", 200, b"ok")
expect("content-length", b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\nabc", 200, b"abc")
expect("content-length garbage", b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3abc\r\n\r\nabc", 400)
expect("duplicate content-length", b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\nContent-Length: 3\r\n\r\nabc", 400)
expect("overflow content-length", b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 999999999999999999999999999999999\r\n\r\n", 413)
expect("te plus cl", b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 1\r\n\r\n0\r\n\r\n", 400)
expect("unsupported transfer coding", b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n", 400)
expect("chunked", b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n3;foo=bar\r\nabc\r\n4\r\ndefg\r\n0\r\nX-Trailer: yes\r\n\r\n", 200, b"abcdefg")
expect("header count", b"GET /health HTTP/1.1\r\nHost: x\r\nA: 1\r\nB: 1\r\nC: 1\r\nD: 1\r\nE: 1\r\nF: 1\r\nG: 1\r\nH: 1\r\n\r\n", 431)

# Body deadline is absolute, not reset by a partial body.
s = connect()
s.sendall(b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 10\r\n\r\nabc")
t0 = time.monotonic()
data = b""
while True:
    part = s.recv(4096)
    if not part:
        break
    data += part
elapsed = time.monotonic() - t0
s.close()
if not data.startswith(b"HTTP/1.1 408 "):
    raise AssertionError(f"body timeout: {data[:80]!r}")
if elapsed > 1.8:
    raise AssertionError(f"body timeout took too long: {elapsed:.3f}s")

# 2 workers + 2 queued clients. Extra accepted clients must be rejected quickly
# with 503 instead of growing an unbounded userspace queue.
held = []
for _ in range(8):
    s = connect()
    s.sendall(b"GET /health HTTP/1.1\r\nHost: x\r\n")
    held.append(s)
time.sleep(.1)
rejected = 0
for s in held:
    s.settimeout(.2)
    try:
        data = s.recv(512)
        if data.startswith(b"HTTP/1.1 503 "):
            rejected += 1
    except (socket.timeout, OSError):
        pass
for s in held:
    s.close()
if rejected == 0:
    raise AssertionError("bounded worker queue did not reject overload with 503")

# The server remains usable after overload.
time.sleep(.1)
expect("post-overload health", b"GET /health HTTP/1.1\r\nHost: x\r\n\r\n", 200, b"ok")
PY

kill "$server_pid"
wait "$server_pid" 2>/dev/null || true
server_pid=''
echo '[http] production hardening/parser/workers ok'
