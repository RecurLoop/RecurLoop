// Keep the VS Code PTY alive while the traced application owns its input/output.
// stdin must remain unread here: the debuggee reads it directly from the TTY.
const fs = require('node:fs');
const net = require('node:net');
const socket = net.createConnection(process.argv[2]);
socket.on('connect', () => socket.write(fs.readlinkSync('/proc/self/fd/0') + '\n'));
socket.on('end', () => process.exit(0));
socket.on('error', error => { console.error(error.message); process.exit(1); });
process.on('SIGINT', () => socket.write('interrupt\n'));
process.on('SIGTERM', () => process.exit(0));
