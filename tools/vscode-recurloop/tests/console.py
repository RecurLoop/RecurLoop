"""Exercise the real --connect terminal client over a PTY, including Ctrl+C."""
import errno
import fcntl
import termios
import os
import pty
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
            if result == b'> ' or result.endswith(b'\n> '):
                return result
    raise AssertionError(f'console timed out: {result!r}')


def command(source):
    os.write(master, source.encode() + b'\n')
    return prompt()


try:
    prompt()
    assert b'console-output-42\r\n' in command('echo console-output-42')
    assert b'PIPELINE\r\n' in command('echo pipeline | tr a-z A-Z')
    assert b'console-error-42' in command('sh -c "echo console-error-42 >&2"')
    command('capture echo captured-output-42')
    assert b'captured-output-42' in command('print captured')
    with tempfile.TemporaryDirectory(prefix='rl-console-') as directory:
        target = os.path.join(directory, 'redirected.txt')
        command(f'echo redirected-output > {target}')
        with open(target) as output:
            assert output.read() == 'redirected-output\n'
    command('var console_state = 42')
    for source in ['sleep 100', 'capture sleep 100', 'sleep 100 | cat', 'sh -c "sleep 100; echo should-not-run"']:
        os.write(master, source.encode() + b'\n')
        time.sleep(0.4)
        started = time.monotonic()
        os.write(master, b'\x03')
        reply = prompt(5)
        assert b'^C' in reply, reply
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
