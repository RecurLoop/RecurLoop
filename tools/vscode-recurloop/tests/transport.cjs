const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { once } = require('node:events');
const { RuntimeConnection } = require('../out/transport');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-progress-'));
const socketPath = path.join(root, 'server.sock');
function frame(kind, text) {
  const payload = Buffer.from(text);
  const header = Buffer.alloc(5);
  header[0] = kind.charCodeAt(0);
  header.writeUInt32BE(payload.length, 1);
  return Buffer.concat([header, payload]);
}
const server = net.createServer(socket => {
  socket.write('> ');
  let pending = '';
  socket.on('data', data => {
    pending += data;
    while (pending.includes('\n')) {
      const end = pending.indexOf('\n');
      const command = pending.slice(0, end);
      pending = pending.slice(end + 1);
      if (command === ':transport-stream-v2') continue;
      const unicode = Buffer.from('Loading zażółć.rl\n');
      // Split a UTF-8 codepoint between progress frames, and fragment headers.
      const first = Buffer.concat([frame('T', ''), frame('O', 'program output\n'), frame('T', '')]);
      const part = Buffer.alloc(5);
      part[0] = 84; part.writeUInt32BE(10, 1);
      const rest = Buffer.alloc(5);
      rest[0] = 84; rest.writeUInt32BE(unicode.length - 10, 1);
      const response = Buffer.concat([first, part, unicode.subarray(0, 10), rest, unicode.subarray(10),
        frame('S', command === 'fail' ? '1' : '0'), frame('P', '')]);
      socket.write(response.subarray(0, 3));
      setImmediate(() => socket.write(response.subarray(3)));
    }
  });
});
(async () => {
  server.listen(socketPath);
  await once(server, 'listening');
  const connection = new RuntimeConnection(socketPath);
  const output = [], progress = [], completed = [];
  try {
    const response = await connection.request(['load', 'publish'], 2000, undefined, {
      output: text => output.push(text), progress: text => progress.push(text), completed: count => completed.push(count)
    });
    assert.equal(response, 'program output\nprogram output\n');
    assert.equal(output.join(''), response);
    assert.equal(progress.join(''), 'Loading zażółć.rl\nLoading zażółć.rl\n');
    assert.deepEqual(completed, [1, 2]);
    await assert.rejects(connection.request(['fail'], 2000, undefined, { completed: () => assert.fail('Failed stage completed') }), /status=1/);
  } finally { connection.close(); }
  console.log('Transport passed: live progress, separate output, fragmented UTF-8 frames and failure status.');
})().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => server.close(() => fs.rmSync(root, { recursive: true, force: true })));
