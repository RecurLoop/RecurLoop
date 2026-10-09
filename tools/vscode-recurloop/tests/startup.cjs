// Real child and Unix socket: readiness comes from the greeting, not a timer or socket file.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const net = require('node:net');
const { once } = require('node:events');
const { setTimeout: delay, setImmediate: nextTurn } = require('node:timers/promises');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-startup-'));
const folder = { uri: { fsPath: root } };
const executable = path.join(root, 'server.cjs');
fs.writeFileSync(path.join(root, 'recurloop.project.rl'), '');
fs.writeFileSync(executable, `#!${process.execPath}
const net = require('node:net');
const readline = require('node:readline');
const socket = process.argv[process.argv.indexOf('--unix') + 1];
let client;
let server;
let greeted = false;
readline.createInterface({ input: process.stdin }).on('line', line => {
  if (line === 'listen') {
    server = net.createServer(connection => {
      client = connection;
      if (greeted) connection.write('> ');
      connection.on('error', () => {});
      let buffer = '';
      connection.on('data', chunk => {
        buffer += chunk;
        while (buffer.includes('\\n')) {
          const end = buffer.indexOf('\\n');
          const command = buffer.slice(0, end);
          buffer = buffer.slice(end + 1);
          if (command === ':transport-stream-v2') continue;
          const status = Buffer.from([83, 0, 0, 0, 1, 48, 80, 0, 0, 0, 0]);
          connection.write(status);
          if (command === ':publish') process.stdout.write('published\\n');
        }
      });
      process.stdout.write('connected\\n');
    }).listen(socket, () => process.stdout.write('listening\\n'));
  } else if (line === 'greet') { greeted = true; client.write('>'); setImmediate(() => client.write(' ')); }
  else if (line === 'invalid') client.write('??');
  else if (line === 'exit') process.exit(7);
});
process.stdout.write('booting\\n');
`, { mode: 0o755 });
const vscode = { workspace: {
  workspaceFolders: [folder], getWorkspaceFolder: () => folder,
  getConfiguration: () => ({ get: (_key, fallback) => fallback })
} };
const original = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : original.call(this, name, ...rest); };
const { RecurLoopRuntime } = require('../out/runtime');
const { resolveExecutable } = require('../out/util');
const log = [];
const runtime = new RecurLoopRuntime({ appendLine: line => log.push(line), append: line => log.push(line) }, async () => executable);
async function child() {
  while (!runtime.workspaces.get(root)?.process) await nextTurn();
  return runtime.workspaces.get(root).process;
}
async function command(process, line, expected) {
  const observed = (async () => {
    for (;;) {
      const [data] = await once(process.stdout, 'data');
      if (data.toString().includes(expected)) return;
    }
  })();
  process.stdin.write(line + '\n');
  return observed;
}
(async () => {
  // Reproduce a socket that exists but refuses the first connection.
  const connect = net.createConnection;
  let refused = false;
  net.createConnection = function(...args) {
    if (!refused) {
      refused = true;
      const socket = new net.Socket();
      setImmediate(() => socket.emit('error', Object.assign(new Error('not listening yet'), { code: 'ECONNREFUSED' })));
      return socket;
    }
    return connect.apply(this, args);
  };
  let ready = false;
  const starting = runtime.terminalOptions(folder.uri).then(result => { ready = true; return result; });
  const process = await child();
  // Regress the former five-second startup deadline.
  await delay(5200);
  assert.equal(ready, false);
  await command(process, 'listen', 'connected');
  assert.ok(fs.existsSync(runtime.workspaces.get(root).socketPath));
  await delay(50);
  assert.equal(ready, false); // accepting connections without a greeting is insufficient
  process.stdin.write('greet\n');
  const terminal = await starting;
  net.createConnection = connect;
  assert.ok(refused);
  assert.equal(ready, true);
  assert.ok(log.some(line => line.includes('server ready; project published')));
  assert.equal(terminal.shellArgs[0], '--connect');
  // A managed/prepared server must also supply the client executable and info.
  assert.equal(terminal.shellPath, executable);
  assert.ok(runtime.info(folder.uri).includes(`executable=${executable}\n`));
  assert.ok(runtime.info(folder.uri).includes(`configured executable=${resolveExecutable(folder.uri)}\n`));
  runtime.dispose();

  const failing = new RecurLoopRuntime({ appendLine() {}, append() {} }, async () => executable);
  const stopped = failing.terminalOptions(folder.uri);
  const rejection = assert.rejects(stopped, /exited before startup completed.*code=7/);
  while (!failing.workspaces.get(root)?.process) await nextTurn();
  failing.workspaces.get(root).process.stdin.write('exit\n');
  await rejection;
  failing.dispose();

  const cancelled = new RecurLoopRuntime({ appendLine() {}, append() {} }, async () => executable);
  const pending = cancelled.terminalOptions(folder.uri);
  const cancellation = assert.rejects(pending, /cancelled/);
  while (!cancelled.workspaces.get(root)?.process) await nextTurn();
  cancelled.dispose();
  await cancellation;

  const removed = new RecurLoopRuntime({ appendLine() {}, append() {} }, async () => executable);
  const removedStartup = removed.terminalOptions(folder.uri);
  const removal = assert.rejects(removedStartup, /cancelled/);
  while (!removed.workspaces.get(root)?.process) await nextTurn();
  fs.unlinkSync(path.join(root, 'recurloop.project.rl'));
  await removed.restart(folder.uri);
  await removal;
  removed.dispose();
  console.log('Startup passed: delayed process, greeting readiness, project publication, process failure and cancellation.');
})().catch(error => { console.error(error, log.join('\n')); process.exitCode = 1; })
  .finally(() => { runtime.dispose(); fs.rmSync(root, { recursive: true, force: true }); });
