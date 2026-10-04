// Headless integration: real host/socket, VS Code API shim only at the editor boundary.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const { execFileSync } = require('node:child_process');
let terminalLibraries = ['shell', 'inferred'];
const repo = path.resolve(__dirname, '../../..');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-extension-test-'));
process.env.RECURLOOP_LIBRARY_PATH = process.env.RECURLOOP_TEST_LIBRARIES || path.join(repo, 'build/Release/libraries');
const testProgram = process.env.RECURLOOP_TEST_PROGRAM || path.join(repo, 'build/Release/bin/recurloop');
const folder = { uri: { fsPath: root }, name: 'fixture', index: 0 };
const vscode = { workspace: {
  workspaceFolders: [folder], getWorkspaceFolder: () => folder, saveAll: async () => true,
  getConfiguration: () => ({ get: (key, fallback) => key === 'executablePath'
    ? testProgram : key === 'terminal.libraries' ? terminalLibraries : fallback })
} };
const original = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : original.call(this, name, ...rest); };
const { RecurLoopRuntime } = require('../out/runtime');
const { ProjectController } = require('../out/project');
const log = [];
const runtime = new RecurLoopRuntime({ appendLine: text => log.push(text), append: text => log.push(text) });
const project = new ProjectController(runtime);
(async () => {
  fs.writeFileSync(path.join(root, 'grammar.rl'), 'syntax greeting <value:expr> => print ${value}\n');
  fs.writeFileSync(path.join(root, 'main.rl'), 'greeting 42\n');
  const contract = { targets: [
    { name: 'prepare', command: 'var target_value = 41' },
    { name: 'check', dependencies: ['prepare'], command: 'assert target_value + 1 == 42' },
    { name: 'bad', command: 'assert false' },
    { name: 'cycle', dependencies: ['cycle'], command: '' }
  ] };
  fs.writeFileSync(path.join(root, 'recurloop.project.rl'),
    'include "grammar.rl"\ninclude "main.rl"\nlet VSCode = phrase { dictionary = true }\n' +
    `syntax VSCode:describe "project" => print ${JSON.stringify(JSON.stringify(contract))}\n`);
  assert.equal((await project.targets(folder.uri)).length, 4);
  await project.run(folder.uri, 'check'); // dependency state must survive in the same session
  await assert.rejects(project.run(folder.uri, 'bad'));
  await assert.rejects(project.run(folder.uri, 'cycle'), /Cyclic/);
  const trace = await runtime.inspect({ uri: { fsPath: path.join(root, 'main.rl') }, getText: () => 'greeting 42\n' });
  assert.ok(trace.includes(Buffer.from('greeting').toString('hex')), trace);
  assert.ok(!trace.includes(Buffer.from('undefined phrase').toString('hex')), trace);
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
  terminalLibraries = [];
  await runtime.restart(folder.uri);
  await assert.rejects(runtime.execute(folder.uri, ['echo missing-shell']));
  terminalLibraries = ['shell', 'inferred'];
  folder.uri = { fsPath: repo };
  assert.equal((await project.targets(folder.uri)).length, 5);
  await project.run(folder.uri, 'check');
  await project.run(folder.uri, 'build-release');
  await project.run(folder.uri, 'build-debug');
  await project.run(folder.uri, 'run');
  assert.ok(fs.existsSync(path.join(repo, '.cache/recurloop-vscode/application')));
  assert.ok(fs.existsSync(path.join(repo, '.cache/recurloop-vscode/application-debug')));
  console.log('Runtime integration passed: project graph, custom syntax, targets, failure, cycle, console and restart.');
})().catch(error => { console.error(error, log.join('\n')); process.exitCode = 1; })
  .finally(() => { runtime.dispose(); fs.rmSync(root, { recursive: true, force: true }); });
