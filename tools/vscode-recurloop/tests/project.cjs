// Short scheduling checks: no host process, socket, watcher delay or build target.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-project-queue-'));
const folder = { uri: { fsPath: root } };
let saved = true;
const vscode = { workspace: {
  getWorkspaceFolder: () => folder,
  saveAll: async () => saved,
  getConfiguration: () => ({ get: (_key, fallback) => fallback })
} };
const original = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : original.call(this, name, ...rest); };
const { RecurLoopRuntime } = require('../out/runtime');
const { ProjectController } = require('../out/project');
const runtime = new RecurLoopRuntime({ append() {}, appendLine() {} });
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
(async () => {
  fs.writeFileSync(path.join(root, 'recurloop.project.rl'), '');
  runtime.revision(folder.uri);
  const workspace = runtime.workspaces.get(root);
  workspace.ensureStarted = async () => {};
  const started = deferred(), finish = deferred();
  const calls = [];
  workspace.request = async (_socket, commands) => {
    calls.push(commands[0]);
    if (commands[0] === 'first') { started.resolve(); await finish.promise; }
    if (commands[0] === 'fail') throw new Error('request failed');
    return '';
  };
  const first = runtime.execute(folder.uri, ['first']);
  await started.promise;
  const reload = runtime.reload(folder.uri);
  const next = runtime.execute(folder.uri, ['next']);
  const controller = new AbortController();
  const cancelled = assert.rejects(runtime.execute(folder.uri, ['cancelled'], controller.signal), /cancelled/);
  controller.abort(new Error('cancelled'));
  assert.deepEqual(calls, ['first']);
  finish.resolve();
  await Promise.all([first, reload, next, cancelled]);
  assert.deepEqual(calls, ['first', ':baseline', 'next']);
  await assert.rejects(runtime.execute(folder.uri, ['fail']), /request failed/);
  await runtime.execute(folder.uri, ['after-failure']);
  assert.equal(calls.at(-1), 'after-failure');

  const published = deferred(), reloading = deferred();
  let executed = false;
  const project = new ProjectController({
    reload: async (_uri, signal) => { assert.ok(signal); reloading.resolve(); await published.promise; },
    execute: async (_uri, _commands, signal) => { assert.ok(signal); executed = true; return 'done'; }
  });
  const run = project.run(folder.uri, 'build', new AbortController().signal);
  await reloading.promise;
  assert.equal(executed, false);
  published.resolve();
  assert.equal(await run, 'done');
  saved = false;
  await assert.rejects(project.run(folder.uri, 'build'), /Save project files/);
  console.log('Project scheduling passed: ordered reload, cancellation, failure recovery and save barrier.');
})().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => { runtime.dispose(); Module._load = original; fs.rmSync(root, { recursive: true, force: true }); });
