"""A real PTY boundary for the headless VS Code createTerminal shim."""
import os, pty, select, signal, subprocess, sys, fcntl, termios
from pathlib import Path
master, slave = pty.openpty()
def controlling_terminal():
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
child = subprocess.Popen(sys.argv[2:], stdin=slave, stdout=slave, stderr=slave, preexec_fn=controlling_terminal)
os.close(slave)
signal.signal(signal.SIGTERM, lambda *_: child.terminate())
with open(sys.argv[1], 'wb', buffering=0) as output:
    while child.poll() is None:
        input_path = Path(sys.argv[1] + ".input")
        if input_path.exists():
            data = input_path.read_bytes(); input_path.unlink(); os.write(master, data)
        if select.select([master], [], [], .05)[0]:
            try: output.write(os.read(master, 65536))
            except OSError: break
    while select.select([master], [], [], .05)[0]:
        try: output.write(os.read(master, 65536))
        except OSError: break
child.wait()
os.close(master)
