#!/usr/bin/env python3
"""Exercise the source-owned IDE index against the ordinary Project server."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[4]
PROGRAM = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else REPO / 'build/Release/bin/recurloop'
with tempfile.TemporaryDirectory(prefix='recurloop-analysis-') as directory:
    root = Path(directory)
    (root / 'definitions.rl').write_text('''record Box { value:i64 }
let base = <debug:ping>
let derived = <base>
let add = fn (item:Box*, value:i64) -> i64 {
    let copy:Box* = item
    let result:i64 = value + 1
    if value < 0 { let result:i64 = 99; let ignored:i64 = result }
    let copied:i64 = result
    return result
}
''')
    (root / 'calls.rl').write_text('''let caller = fn () -> i64 { return add(cast(Box*, 0), 41) }
''')
    (root / 'main.rl').write_text('include "definitions.rl"\ninclude "calls.rl"\n')
    socket_path = root / 'runtime.sock'
    server = subprocess.Popen([str(PROGRAM), '--serve', '--unix', str(socket_path), '--no-stdio',
                               '--project-cache', str(root / 'cache')], cwd=REPO,
                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        client = socket.socket(socket.AF_UNIX)
        client.settimeout(30)
        deadline = time.monotonic() + 30
        while True:
            try:
                client.connect(str(socket_path))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if server.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError('Project server did not start')
                time.sleep(.02)

        def receive():
            result = b''
            while not result.endswith(b'> '):
                chunk = client.recv(65536)
                if not chunk:
                    raise RuntimeError('Project server closed the connection')
                result += chunk
            return result[:-2].decode()

        receive()
        for command in [':baseline', ':cache', ':load-file\t' + str(root / 'main.rl'), ':publish']:
            client.sendall(command.encode() + b'\n')
            response = receive()
            if 'status=' in response:
                raise RuntimeError(response)
        # A trace must preserve the ordinary execution environment and support
        # aliased phrases without any host knowledge of their source spelling.
        source = (root / 'definitions.rl').read_bytes()
        client.sendall(b':trace\t' + str(root / 'definitions.rl').encode().hex().encode() + b'\t' + source.hex().encode() + b'\n')
        trace = receive()
        if 'E\t' in trace or 'P\t' not in trace:
            raise RuntimeError('Source-entry replay failed: ' + trace[:1000])
        client.sendall(b'print caller()\n')
        if receive().strip() != '42':
            raise RuntimeError('Inspection mutated the published program')
        client.close()
        env = dict(os.environ, RECURLOOP_ANALYSIS_TEST_ROOT=str(root),
                   RECURLOOP_ANALYSIS_TEST_SOCKET=str(socket_path),
                   RECURLOOP_ANALYSIS_TEST_PROGRAM=str(PROGRAM))
        result = subprocess.run([str(PROGRAM), '--file', 'examples/07-workflows/ide/ide.rl',
                                 '--file', 'examples/07-workflows/ide/tests/analysis.rl'],
                                cwd=REPO, env=env, timeout=120)
        if result.returncode:
            sys.exit(result.returncode)
    finally:
        server.terminate()
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
