// Headless integration: real host/socket, VS Code API shim only at the editor boundary.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const { execFileSync } = require('node:child_process');
let terminalLibraries = ['shell', 'inferred'];
let projectEntry = 'recurloop.project.rl';
const repo = path.resolve(__dirname, '../../..');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-extension-test-'));
process.env.RECURLOOP_LIBRARY_PATH = process.env.RECURLOOP_TEST_LIBRARIES || path.join(repo, 'build/Release/libraries');
const testProgram = process.env.RECURLOOP_TEST_PROGRAM || path.join(repo, 'build/Release/bin/recurloop');
const folder = { uri: { fsPath: root }, name: 'fixture', index: 0 };
const vscode = { workspace: {
  workspaceFolders: [folder], getWorkspaceFolder: () => folder, saveAll: async () => true,
  getConfiguration: () => ({ get: (key, fallback) => key === 'executablePath'
    ? testProgram : key === 'terminal.libraries' ? terminalLibraries : key === 'projectFile' ? projectEntry : fallback })
}, window: { showErrorMessage: async () => undefined } };
const original = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : original.call(this, name, ...rest); };
const { RecurLoopRuntime } = require('../out/runtime');
const { RuntimeSetup } = require('../out/runtimeSetup');
const { ProjectController } = require('../out/project');
const log = [];
const output = { appendLine: text => log.push(text), append: text => log.push(text) };
const setup = new RuntimeSetup({ globalStorageUri: { fsPath: path.join(root, 'extension-storage') },
  asAbsolutePath: relative => path.join(__dirname, '..', relative) }, output);
const runtime = new RecurLoopRuntime(output, uri => setup.ensureExecutable(uri));
const project = new ProjectController(runtime);
(async () => {
  await runtime.restart(folder.uri);
  assert.deepEqual(await project.targets(folder.uri), []);
  assert.equal(await runtime.inspect({ uri: folder.uri, getText: () => 'print 42' }), '');
  await assert.rejects(runtime.execute(folder.uri, ['print 42']), /saved project entry/);
  await assert.rejects(runtime.terminalOptions(folder.uri), /saved project entry/);
  assert.ok(!log.some(line => line.includes('[analysis] starting')));
  fs.writeFileSync(path.join(root, 'grammar.rl'), 'syntax greeting <value:expr> => print ${value}\n');
  fs.writeFileSync(path.join(root, 'main.rl'), 'greeting 42\n');
  fs.writeFileSync(path.join(root, 'recurloop.project.rl'), `include "grammar.rl"
include "main.rl"
target prepare { var target_value = 41 }
target check depends [prepare] { assert target_value + 1 == 42 }
target bad { assert false }
target cycle depends [cycle] {}
`);
  assert.equal((await project.targets(folder.uri)).length, 4);
  await project.run(folder.uri, 'check'); // dependency state must survive in the same session
  await assert.rejects(project.run(folder.uri, 'bad'));
  await assert.rejects(project.run(folder.uri, 'cycle'), /Cyclic/);
  // Disconnecting an active native loop must release the server worker too.
  // A second request proves recovery, beyond rejecting the client's promise.
  const cancellationEntry = path.join(root, 'recurloop.project.rl');
  const beforeCancellation = fs.readFileSync(cancellationEntry, 'utf8');
  fs.appendFileSync(cancellationEntry, '\nrecurloop fn native_spin() -> i64 { while 1 {} }\n');
  await runtime.reload(folder.uri);
  const controller = new AbortController();
  const running = runtime.execute(folder.uri, ['recurloop native_spin()'], controller.signal);
  const timer = setTimeout(() => controller.abort(new Error('native loop cancelled')), 100);
  try { await assert.rejects(running, /native loop cancelled/); }
  finally { clearTimeout(timer); }
  assert.equal((await runtime.execute(folder.uri, ['print 42'])).trim(), '42');
  fs.writeFileSync(cancellationEntry, beforeCancellation);
  await runtime.reload(folder.uri);
  const trace = await runtime.inspect({ uri: { fsPath: path.join(root, 'main.rl') }, getText: () => 'greeting 42\n' });
  assert.ok(trace.includes(Buffer.from('greeting').toString('hex')), trace);
  assert.ok(!trace.includes(Buffer.from('undefined phrase').toString('hex')), trace);
  // Root inspection replays cached includes and replaces the lexicon graph.
  // Analysis must preserve the shared server and its console connections.
  const rootDocument = { uri: { fsPath: path.join(root, 'recurloop.project.rl') },
    getText: () => fs.readFileSync(path.join(root, 'recurloop.project.rl'), 'utf8') };
  for (let repeat = 0; repeat < 2; ++repeat) {
    const rootTrace = await runtime.inspect(rootDocument);
    assert.ok(rootTrace.includes('P\t'), rootTrace);
    assert.ok(!rootTrace.includes('E\t'), rootTrace);
    assert.equal((await runtime.execute(folder.uri, ['print 42'])).trim(), '42');
  }
  const terminal = await runtime.terminalOptions(folder.uri);
  assert.equal(terminal.shellArgs[0], '--connect');
  assert.ok(fs.existsSync(terminal.shellArgs[1]));
  execFileSync('python3', [path.join(__dirname, 'console.py'), terminal.shellPath, terminal.shellArgs[1]], { stdio: 'inherit', timeout: 20000 });
  const entryPath = path.join(root, 'recurloop.project.rl');
  const validEntry = fs.readFileSync(entryPath, 'utf8');
  fs.writeFileSync(entryPath, validEntry + '\ndefinitely_missing_project_phrase\n');
  await assert.rejects(runtime.reload(folder.uri));
  assert.equal((await project.targets(folder.uri)).length, 4); // failed candidate was never published
  fs.writeFileSync(entryPath, validEntry);
  await runtime.reload(folder.uri);
  assert.equal((await runtime.terminalOptions(folder.uri)).shellArgs[1], terminal.shellArgs[1]);
  await runtime.restart(folder.uri);
  assert.equal((await project.targets(folder.uri)).length, 4);
  fs.unlinkSync(entryPath);
  await runtime.reload(folder.uri);
  assert.ok(!fs.existsSync(terminal.shellArgs[1]));
  await runtime.restart(folder.uri);
  assert.deepEqual(await project.targets(folder.uri), []);
  // An arbitrary configured filename opts this folder back in.
  projectEntry = 'project-entry.config';
  fs.writeFileSync(path.join(root, projectEntry), '');
  await runtime.restart(folder.uri);
  assert.equal((await runtime.execute(folder.uri, ['print 42'])).trim(), '42');
  assert.deepEqual(await project.targets(folder.uri), []);
  fs.writeFileSync(path.join(root, projectEntry), validEntry);
  await runtime.reload(folder.uri);
  assert.equal((await project.targets(folder.uri)).length, 4);
  terminalLibraries = [];
  await runtime.restart(folder.uri);
  await assert.rejects(runtime.execute(folder.uri, ['echo missing-shell']));
  terminalLibraries = ['shell', 'inferred'];
  projectEntry = 'recurloop.project.rl';
  fs.writeFileSync(path.join(root, projectEntry), `include ${JSON.stringify(path.join(repo, 'examples/07-workflows/ide/application/main.rl'))}
target build-release {
    emit executable ".cache/recurloop/application" application_main = fn () -> i64 { return ExampleApplication:main() }
}
target build-debug {
    emit executable debug ".cache/recurloop/application-debug" application_debug_main = fn () -> i64 { return ExampleApplication:main() }
}
target run depends [build-release] { ./.cache/recurloop/application }
target debug depends [build-debug] debug executable ".cache/recurloop/application-debug" {}
target check { assert ExampleApplication:advance(3, 2) == 8 }
`);
  await runtime.restart(folder.uri);
  assert.equal((await project.targets(folder.uri)).length, 5);
  await project.run(folder.uri, 'check');
  await project.run(folder.uri, 'build-release');
  await project.run(folder.uri, 'build-debug');
  await project.run(folder.uri, 'run');
  assert.ok(fs.existsSync(path.join(root, '.cache/recurloop/application')));
  assert.ok(fs.existsSync(path.join(root, '.cache/recurloop/application-debug')));
  console.log('Runtime integration passed: project graph, custom syntax, targets, failure, cycle, console and restart.');
})().catch(error => { console.error(error, log.join('\n')); process.exitCode = 1; })
  .finally(() => { runtime.dispose(); setup.dispose(); fs.rmSync(root, { recursive: true, force: true }); });
