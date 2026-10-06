// Project detection and workspace settings through the real activation callbacks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-default-terminal-'));
const folder = { uri: { fsPath: root, scheme: 'file' }, name: 'project', index: 0 };
const otherRoot = path.join(root, 'other');
fs.mkdirSync(otherRoot);
const otherFolder = { uri: { fsPath: otherRoot, scheme: 'file' }, name: 'other', index: 1 };
const platform = process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'osx' : 'linux';
const defaultKey = `defaultProfile.${platform}`;
const profilesKey = `profiles.${platform}`;
const settings = {};
const userSettings = { [defaultKey]: 'bash', [profilesKey]: { bash: { path: '/bin/bash' } } };
const memory = new Map();
const state = { get: key => memory.get(key), update: async (key, value) => {
  if (value === undefined) memory.delete(key);
  else memory.set(key, JSON.parse(JSON.stringify(value)));
} };
const writes = [];
const commands = new Map();
const events = {};
const disposable = { dispose() {} };
let projectName = 'recurloop.project.rl';
let runtimeStarts = 0;
let featureAllocations = 0;
let profileProvider;
let createdTerminal;
let active;
const event = name => listener => { events[name] = listener; return disposable; };
const vscode = {
  ConfigurationTarget: { Global: 1, Workspace: 2, WorkspaceFolder: 3 },
  DebugConfigurationProviderTriggerKind: { Dynamic: 2 },
  TerminalProfile: class { constructor(options) { this.options = options; } },
  workspace: {
    workspaceFolders: [folder],
    getWorkspaceFolder(uri) { return uri.fsPath.startsWith(otherRoot) ? otherFolder : uri.fsPath.startsWith(root) ? folder : undefined; },
    getConfiguration(section, uri) {
      if (section === 'recurloop') return { get: (key, fallback) => key === 'projectFile' ? (uri?.fsPath.startsWith(otherRoot) ? 'recurloop.project.rl' : projectName) : fallback };
      assert.equal(section, 'terminal.integrated');
      return {
        get: key => settings[key] ?? userSettings[key],
        inspect: key => ({ workspaceValue: settings[key], globalValue: userSettings[key] }),
        update: async (key, value, target) => {
          assert.equal(target, vscode.ConfigurationTarget.Workspace);
          writes.push({ key, value });
          if (value === undefined) delete settings[key];
          else settings[key] = JSON.parse(JSON.stringify(value));
        }
      };
    },
    createFileSystemWatcher: () => ({ dispose() {}, onDidChange: event('change'), onDidCreate: event('create'), onDidDelete: event('delete') }),
    onDidChangeConfiguration: event('configuration'), onDidChangeWorkspaceFolders: event('folders')
  },
  window: {
    createOutputChannel: () => { featureAllocations++; return { appendLine() {}, dispose() {} }; },
    registerTerminalProfileProvider: (_id, provider) => { profileProvider = provider; return disposable; },
    createTerminal: options => { createdTerminal = options; return { show() {}, sendText() {} }; }
  },
  tasks: { registerTaskProvider: () => disposable },
  debug: { onDidTerminateDebugSession: () => disposable, registerDebugConfigurationProvider: () => disposable, registerDebugAdapterDescriptorFactory: () => disposable },
  commands: { registerCommand: (name, callback) => { commands.set(name, callback); return disposable; } }
};
const stub = class { dispose() {} invalidate() {} };
const mocks = {
  './analysis': { AnalysisController: stub }, './debugAdapter': { RecurLoopDebugAdapter: stub },
  './project': { ProjectController: stub, TargetRunAdapter: stub },
  './runtimeSetup': { RuntimeSetup: class extends stub { async ensureExecutable() { return '/bin/recurloop'; } } },
  './runtime': { RecurLoopRuntime: class extends stub {
    async restart() { runtimeStarts++; }
    async reload() {}
    async terminalOptions(uri) { return { name: 'RecurLoop', cwd: uri.fsPath, shellPath: '/bin/recurloop', shellArgs: ['--connect', 'project.sock'] }; }
  } }
};
const original = Module._load;
Module._load = function(name, parent, ...rest) {
  if (name === 'vscode') return vscode;
  if (parent?.filename.endsWith('/out/extension.js') && mocks[name]) return mocks[name];
  return original.call(this, name, parent, ...rest);
};
const { activate } = require('../out/extension');
const { TerminalDefaults } = require('../out/terminalDefaults');
async function settle() { for (let turn = 0; turn < 15; turn++) await new Promise(resolve => setImmediate(resolve)); }
function dispose() { active?.subscriptions.forEach(item => item.dispose()); active = undefined; }
function start() { active = { subscriptions: [], workspaceState: state }; activate(active); }
function entry() { return path.join(root, projectName); }
function touch(file = entry()) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, ''); }
async function created() { events.create({ fsPath: entry(), scheme: 'file' }); await settle(); }
async function deleted() { fs.unlinkSync(entry()); events.delete({ fsPath: entry(), scheme: 'file' }); await settle(); }
function configuration() { events.configuration({ affectsConfiguration: name => name === 'recurloop' }); }
(async () => {
  assert.ok(require('../package.json').activationEvents.includes('onStartupFinished'), 'custom entries need startup activation');
  start(); await settle();
  assert.equal(writes.length, 0, 'non-project startup must leave terminal settings alone');
  assert.equal(runtimeStarts, 0);
  assert.equal(featureAllocations, 0);
  assert.equal((await profileProvider.provideTerminalProfile()).options.shellPath, process.env.SHELL || '/bin/sh');

  touch(); await created();
  assert.equal(settings[defaultKey], 'RecurLoop');
  assert.deepEqual(settings[profilesKey].RecurLoop, { extensionIdentifier: 'recurloop.recurloop-vscode', id: 'recurloop.console', title: 'RecurLoop' });
  assert.equal(userSettings[defaultKey], 'bash');
  assert.deepEqual((await profileProvider.provideTerminalProfile()).options.shellArgs, ['--connect', 'project.sock']);
  await deleted();
  assert.equal(settings[defaultKey], undefined);
  assert.equal(settings[profilesKey], undefined);

  // Preserve workspace defaults, other profiles and ownership across a window reload.
  settings[defaultKey] = 'zsh';
  settings[profilesKey] = { zsh: { path: '/bin/zsh' }, RecurLoop: { path: '/custom-shell' } };
  touch(); await created();
  dispose(); start(); await settle();
  await deleted();
  assert.equal(settings[defaultKey], 'zsh');
  assert.deepEqual(settings[profilesKey], { zsh: { path: '/bin/zsh' }, RecurLoop: { path: '/custom-shell' } });

  // A configured entry with an arbitrary extension is detected without opening .rl source.
  dispose(); projectName = 'config/project.entry'; touch(); start(); await settle();
  assert.equal(settings[defaultKey], 'RecurLoop');
  projectName = 'missing.entry'; configuration(); await settle();
  assert.equal(settings[defaultKey], 'zsh');
  projectName = 'config/project.entry'; configuration(); await settle();
  assert.equal(settings[defaultKey], 'RecurLoop');
  await deleted();

  // Keep later user choices and unrelated profile edits.
  touch(); await created();
  settings[defaultKey] = 'fish'; settings[profilesKey].fish = { path: '/bin/fish' };
  configuration(); await settle();
  assert.equal(settings[defaultKey], 'fish');
  await deleted();
  assert.equal(settings[defaultKey], 'fish');
  assert.deepEqual(settings[profilesKey].fish, { path: '/bin/fish' });

  // Keep the default while any project remains; no editor selects a project folder.
  vscode.workspace.workspaceFolders = [otherFolder, folder];
  touch(); await created();
  assert.equal((await profileProvider.provideTerminalProfile()).options.cwd, root);
  touch(path.join(otherRoot, 'recurloop.project.rl'));
  await deleted();
  assert.equal(settings[defaultKey], 'RecurLoop');
  fs.unlinkSync(path.join(otherRoot, 'recurloop.project.rl'));
  events.delete({ fsPath: path.join(otherRoot, 'recurloop.project.rl'), scheme: 'file' }); await settle();
  assert.equal(settings[defaultKey], 'fish');

  // Run Current File must not send a shell command into the project console.
  vscode.workspace.workspaceFolders = [folder]; touch(); await created();
  vscode.window.activeTextEditor = { document: { uri: { fsPath: path.join(root, 'main.rl'), scheme: 'file' }, languageId: 'recurloop', isDirty: false } };
  await commands.get('recurloop.runCurrentFile')();
  assert.equal(createdTerminal.shellPath, process.env.SHELL || '/bin/sh');
  await deleted();

  // Overlapping updates converge on the current project state.
  const defaults = new TerminalDefaults(state);
  touch(); const enabling = defaults.synchronize();
  fs.unlinkSync(entry()); const disabling = defaults.synchronize();
  await Promise.all([enabling, disabling]);
  assert.equal(settings[defaultKey], 'fish');
  console.log('Default terminal passed: startup, custom entries, file/configuration events, restoration, reload, multi-folder workspaces and file-run shell.');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  dispose(); fs.rmSync(root, { recursive: true, force: true });
});
