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


def visible_output(output):
    return re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b'', output)


def has_prompt(output):
    visible = visible_output(output)
    # The line editor returns to column zero before restoring the cursor with
    # CSI n C. Removing CSI leaves a trailing CR after the visible prompt.
    return re.search(rb'(?:^|[\n\r])> \r?$', visible) is not None


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
            if has_prompt(result):
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
    # Native calls must use this same socket/PTY as core print and Shell output.
    # The emitted machine code uses libc printf, exactly like quickstart Probe.
    assert b'status=' not in command('extern printf(format:u8*, ...) -> i64 abi sysv-amd64')
    assert b'status=' not in command('let ConsoleProbe = phrase { dictionary = true permanent = true }')
    assert b'status=' not in command('let ConsoleProbe:main = fn () -> i64 { var tick:i64 = 1; while tick <= 3 { printf("Tick %lld: %lld km\\n", tick, tick * 10); tick += 1 }; return 0 }')
    ticks = b'Tick 1: 10 km\r\nTick 2: 20 km\r\nTick 3: 30 km\r\n'
    reply = command('ConsoleProbe:main()')
    assert reply.count(ticks) == 1 and b'No such file' not in reply and b'status=' not in reply, reply
    assert ticks + b'0\r\n' in command('print str(ConsoleProbe:main())')
    for call in ['recurloop   ConsoleProbe:main()', '(ConsoleProbe:main())', '-ConsoleProbe:main()']:
        reply = command(call)
        assert reply.count(ticks) == 1 and b'status=' not in reply, reply
    assert b'status=' not in command('let invoke = <"(">')
    reply = command('ConsoleProbe:main invoke )')
    assert reply.count(ticks) == 1 and b'status=' not in reply, reply
    reply = command('Missing:call()')
    assert b'unknown function' in reply and b'status=1' in reply and b'status=127' not in reply, reply
    reply = command('ConsoleProbe:main(42)')
    assert b'expects 0 argument(s)' in reply and b'status=1' in reply, reply
    assert ticks in command('ConsoleProbe:main()')
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
    # Bracketed-paste mode changes can appear between the submitted line and
    # command output. Parse visible text, as prompt detection does above.
    pid_match = re.search(rb'\r\n([0-9]+)\r\n', visible_output(pid_reply))
    assert pid_match is not None, f'server PID missing from console reply: {pid_reply!r}'
    server_pid = int(pid_match.group(1))
    def resident_kib(pid):
        with open(f'/proc/{pid}/status') as status:
            for line in status:
                if line.startswith('VmRSS:'):
                    return int(line.split()[1])
        raise AssertionError(f'RSS unavailable for {pid}')

    def stream_volume(source, byte, marker, volume):
        endpoints = [server_pid, client.pid]
        baseline = [resident_kib(pid) for pid in endpoints]
        peaks = baseline.copy()
        os.write(master, source.encode() + b'\n')
        tail = b''
        received = 0
        deadline = time.monotonic() + 30
        while marker not in tail:
            remaining = deadline - time.monotonic()
            assert remaining > 0 and select.select([master], [], [], remaining)[0], tail
            chunk = os.read(master, 65536)
            received += chunk.count(byte)
            tail = (tail + chunk)[-128:]
            peaks = [max(peak, resident_kib(pid)) for peak, pid in zip(peaks, endpoints)]
        assert received >= volume, received
        if not has_prompt(tail):
            prompt()
        growth = [peak - base for peak, base in zip(peaks, baseline)]
        assert all(kib < 16 * 1024 for kib in growth), f'output retained in memory: {growth} KiB'
        return growth

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
        growth = stream_volume(f'python3 {script}', b'x', b'volume-complete\r\n', volume)
        print(f'64 MiB stream passed; peak RSS growth server/client: {growth} KiB.')
    # One printf must stream formatting, rather than first allocating its entire output.
    command('let ConsoleProbe:volume = fn () -> void { printf("%*s\\nnative-volume-complete\\n", 67108864, "") }')
    growth = stream_volume('ConsoleProbe:volume()', b' ', b'native-volume-complete\r\n', 64 * 1024 * 1024)
    print(f'64 MiB native printf passed; peak RSS growth server/client: {growth} KiB.')
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
