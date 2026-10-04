"""Exercise the real --connect terminal client over a PTY, including Ctrl+C."""
import errno
import fcntl
import termios
import os
import pty
import re
import select
import socket
import subprocess
import sys
import time
import tempfile

host, socket_path = sys.argv[1:]
master, slave = pty.openpty()
def child_terminal():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


client = subprocess.Popen([host, '--connect', socket_path], stdin=slave, stdout=slave,
                          stderr=slave, preexec_fn=child_terminal)
os.close(slave)


def prompt(timeout=5):
    result = b''
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if select.select([master], [], [], max(0, deadline - time.monotonic()))[0]:
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    raise AssertionError(f'console exited: {result!r}') from error
                raise
            if not chunk:
                raise AssertionError(f'console closed: {result!r}')
            result += chunk
            # A redirection typed into the PTY can end an input-echo chunk in
            # '> '. Only the prompt at the start of a new line completes a command.
            visible = re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b'', result)
            if visible == b'> ' or visible.endswith((b'\n> ', b'\r> ')):
                return result
    raise AssertionError(f'console timed out: {result!r}')


def read_until(marker, timeout=5):
    result = bytearray()
    deadline = time.monotonic() + timeout
    while marker not in result:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([master], [], [], remaining)[0], bytes(result)
        result.extend(os.read(master, 65536))
    return bytes(result)


def command(source):
    os.write(master, source.encode() + b'\n')
    return prompt()


try:
    prompt()
    assert b'console-output-42\r\n' in command('echo console-output-42')
    reply = command('true && echo chain-ok && false && echo should-not-run || echo recovered')
    assert b'chain-ok\r\n' in reply and b'recovered\r\n' in reply, reply
    assert b'\r\nshould-not-run\r\n' not in reply, reply
    assert b'PIPELINE\r\n' in command('echo pipeline | tr a-z A-Z')
    assert b'console-error-42' in command('sh -c "echo console-error-42 >&2"')
    command('capture echo captured-output-42')
    assert b'captured-output-42' in command('print captured')
    with tempfile.TemporaryDirectory(prefix='rl-console-') as directory:
        target = os.path.join(directory, 'redirected.txt')
        command(f'echo redirected-output > {target}')
        with open(target) as output:
            assert output.read() == 'redirected-output\n'
    # The child cannot exit until the terminal receives both output streams.
    # Include NUL and prompt-looking bytes to exercise binary-safe framing.
    with tempfile.TemporaryDirectory(prefix='rl-console-stream-') as directory:
        script = os.path.join(directory, 'stream.py')
        release = os.path.join(directory, 'release')
        with open(script, 'w') as output:
            output.write("import os, sys, time\n"
                         "os.write(1, b'live-stdout\\n> \\x00\\n')\n"
                         "os.write(2, b'live-stderr\\n')\n"
                         "while not os.path.exists(sys.argv[1]): time.sleep(0.01)\n"
                         "os.write(1, b'stream-complete\\n')\n")
        os.write(master, f'python3 {script} {release}\n'.encode())
        try:
            reply = read_until(b'live-stderr\r\n')
            assert b'live-stdout\r\n> \x00\r\n' in reply, reply
            assert b'stream-complete' not in reply, reply
        finally:
            with open(release, 'w'):
                pass
        assert b'stream-complete\r\n' in prompt(), 'prompt text in output ended the command early'
    # Drain a large stream without retaining it in this test either. Sample
    # both endpoints while bytes are flowing, so end-of-command frees cannot
    # hide a buffer proportional to the complete output.
    command('extern getpid() -> i32 abi sysv-amd64')
    pid_reply = command('print getpid()')
    server_pid = int(re.search(rb'\r\n([0-9]+)\r\n', pid_reply).group(1))
    def resident_kib(pid):
        with open(f'/proc/{pid}/status') as status:
            for line in status:
                if line.startswith('VmRSS:'):
                    return int(line.split()[1])
        raise AssertionError(f'RSS unavailable for {pid}')

    with tempfile.TemporaryDirectory(prefix='rl-console-volume-') as directory:
        script = os.path.join(directory, 'volume.py')
        volume = 64 * 1024 * 1024
        with open(script, 'w') as output:
            output.write("import os\n"
                         "chunk = b'x' * 4096\n"
                         "for _ in range(16384):\n"
                         "    view = memoryview(chunk)\n"
                         "    while view: view = view[os.write(1, view):]\n"
                         "os.write(1, b'\\nvolume-complete\\n')\n")
        endpoints = [server_pid, client.pid]
        baseline = [resident_kib(pid) for pid in endpoints]
        peaks = baseline.copy()
        os.write(master, f'python3 {script}\n'.encode())
        tail = b''
        received = 0
        deadline = time.monotonic() + 30
        while b'volume-complete\r\n' not in tail:
            remaining = deadline - time.monotonic()
            assert remaining > 0 and select.select([master], [], [], remaining)[0], tail
            chunk = os.read(master, 65536)
            received += chunk.count(b'x')
            tail = (tail + chunk)[-128:]
            peaks = [max(peak, resident_kib(pid)) for peak, pid in zip(peaks, endpoints)]
        assert received >= volume, received
        visible = re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b'', tail)
        if not visible.endswith((b'\n> ', b'\r> ')):
            prompt()
        growth = [peak - base for peak, base in zip(peaks, baseline)]
        assert all(kib < 16 * 1024 for kib in growth), f'output retained in memory: {growth} KiB'
        print(f'64 MiB stream passed; peak RSS growth server/client: {growth} KiB.')
    command('var console_state = 42')
    for source in ['sleep 100', 'sleep 100 && echo should-not-run', 'capture sleep 100', 'sleep 100 | cat', 'sh -c "sleep 100; echo should-not-run"']:
        os.write(master, source.encode() + b'\n')
        time.sleep(0.4)
        started = time.monotonic()
        os.write(master, b'\x03')
        reply = prompt(5)
        assert b'^C' in reply, reply
        assert b'\r\nshould-not-run\r\n' not in reply, reply
        assert time.monotonic() - started < 5
        assert client.poll() is None, 'Ctrl+C killed the RecurLoop client'
        assert b'after-interrupt\r\n' in command('echo after-interrupt')
        assert b'42' in command('print console_state')
    # Ctrl+C must not affect another session's foreground job.
    other = socket.socket(socket.AF_UNIX)
    other.settimeout(5)
    other.connect(socket_path)
    def other_prompt():
        reply = b''
        while not reply.endswith(b'> '):
            chunk = other.recv(4096)
            assert chunk, reply
            reply += chunk
        return reply
    try:
        other_prompt()
        started = time.monotonic()
        other.sendall(b'sleep 2\n')
        os.write(master, b'sleep 100\n')
        time.sleep(0.4)
        os.write(master, b'\x03')
        prompt()
        assert b'status=130' not in other_prompt()
        assert time.monotonic() - started >= 1.8
        other.sendall(b'echo independent-session\n')
        assert b'independent-session\n' in other_prompt()
        other.sendall(b'sleep 100\n\x03')
        assert b'status=130' in other_prompt()
    finally:
        other.close()
    print('PTY console passed: stdout, stderr, pipelines, Ctrl+C, child groups and persistent state.')
finally:
    if client.poll() is None:
        client.terminate()
    client.wait(timeout=5)
    os.close(master)
