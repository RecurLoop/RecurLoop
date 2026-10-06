// Real project server, real ptrace debuggee, real PTY; only VS Code UI is shimmed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const { spawn } = require('node:child_process');
const repo = path.resolve(__dirname, '../../..');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-editor-test-'));
process.env.RECURLOOP_LIBRARY_PATH = process.env.RECURLOOP_TEST_LIBRARIES || path.join(repo, 'build/Release/libraries');
const testProgram = process.env.RECURLOOP_TEST_PROGRAM || path.join(repo, 'build/Release/bin/recurloop');
let terminalLibraries = ['shell', 'inferred'];
const folder = { uri: { fsPath: repo }, name: 'fixture', index: 0 };
class EventEmitter {
  listeners = [];
  event = listener => { this.listeners.push(listener); return { dispose() {} }; };
  fire(value) { this.listeners.forEach(listener => listener(value)); }
  dispose() {}
}
class Position { constructor(line, character) { this.line = line; this.character = character; } }
class Range { constructor(start, end) { this.start = start; this.end = end; } }
class WorkspaceEdit { edits = []; replace(uri, range, value) { this.edits.push({ uri, range, value }); } }
class Location { constructor(uri, range) { this.uri = uri; this.range = range; } }
const documents = [];
function document(file, text = fs.readFileSync(file, 'utf8')) {
  const doc = { uri: { fsPath: file }, version: 1, getText: () => text,
    offsetAt: p => text.split('\n').slice(0, p.line).reduce((a, line) => a + line.length + 1, 0) + p.character,
    positionAt: offset => { const lines = text.slice(0, offset).split('\n'); return new Position(lines.length - 1, lines.at(-1).length); } };
  documents.push(doc); return doc;
}
let terminalProcess;
const terminalOutput = path.join(root, 'terminal.txt');
const vscode = { EventEmitter, Position, Range, Location, WorkspaceEdit, Uri: { file: fsPath => ({ fsPath }) }, workspace: {
  workspaceFolders: [folder], textDocuments: documents, getWorkspaceFolder: () => folder,
  saveAll: async () => true, openTextDocument: async uri => document(uri.fsPath),
  getConfiguration: () => ({ get: (key, fallback) => key === 'executablePath' ? testProgram : key === 'terminal.libraries' ? terminalLibraries : fallback })
}, window: { createTerminal(options) {
  terminalProcess = spawn('python3', [path.join(__dirname, 'debug-terminal.py'), terminalOutput, options.shellPath, ...options.shellArgs], { env: { ...process.env, ...options.env } });
  terminalProcess.stderr.on('data', data => process.stderr.write(data));
  return { show() {}, dispose() { terminalProcess.kill(); } };
} } };
const original = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : original.call(this, name, ...rest); };
const { RecurLoopRuntime } = require('../out/runtime');
const { ProjectController } = require('../out/project');
const { NavigationController } = require('../out/navigation');
const { RecurLoopDebugAdapter } = require('../out/debugAdapter');
const { DebugConfigurationProvider } = require('../out/extension');
const log = [];
const output = { appendLine: text => log.push(text), append: text => log.push(text) };
const runtime = new RecurLoopRuntime(output);
const project = new ProjectController(runtime);
const adapter = new RecurLoopDebugAdapter(output);
const messages = [];
adapter.onDidSendMessage(message => messages.push(message));
let seq = 1;
async function waitFor(predicate, timeout = 20000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { const value = predicate(); if (value) return value; await new Promise(resolve => setTimeout(resolve, 10)); }
  throw new Error('Timeout; messages=' + JSON.stringify(messages) + '\n' + log.join('\n'));
}
async function request(command, args = {}) {
  const id = seq++;
  adapter.handleMessage({ type: 'request', seq: id, command, arguments: args });
  const result = await waitFor(() => messages.find(message => message.type === 'response' && message.request_seq === id));
  assert.equal(result.success, true, JSON.stringify(result)); return result.body;
}
(async () => {
  const navRoot = path.join(root, 'navigation');
  fs.mkdirSync(navRoot);
  const definitionPath = path.join(navRoot, 'definitions.rl');
  const callsPath = path.join(navRoot, 'calls.rl');
  fs.writeFileSync(definitionPath, 'record Box { value:i64 }\nlet add = fn (value:i64) -> i64 { let result = value + 1; return result }\n');
  const callsSource = 'let caller = fn () -> i64 { return add(42) } // add in comment\n';
  fs.writeFileSync(callsPath, callsSource.replace('42', '41'));
  fs.writeFileSync(path.join(navRoot, 'recurloop.project.rl'), 'include "definitions.rl"\ninclude "calls.rl"\n');
  folder.uri = { fsPath: navRoot };
  terminalLibraries = [];
  const definitionsDoc = document(definitionPath);
  const callsDoc = document(callsPath, callsSource); // unsaved buffer
  const nav = new NavigationController(runtime);
  const crossDefinitions = await nav.locations(callsDoc, new Position(0, 35), 'definition');
  assert.ok(crossDefinitions.some(item => item.uri.fsPath === definitionPath));
  const crossRefs = await nav.locations(definitionsDoc, new Position(1, 5), 'references', false);
  assert.equal(crossRefs.length, 1, JSON.stringify(crossRefs));
  assert.equal(crossRefs[0].uri.fsPath, callsPath);
  const rename = await nav.rename(definitionsDoc, new Position(1, 5), 'sum');
  assert.equal(rename.edits.length, 2, JSON.stringify(rename.edits));
  folder.uri = { fsPath: repo };
  terminalLibraries = ['shell', 'inferred'];
  const source = path.join(repo, 'examples/07-workflows/ide/application/main.rl');
  const doc = document(source);
  const navigation = new NavigationController(runtime);
  const defs = await navigation.locations(doc, new Position(20, 40), 'definition');
  assert.ok(defs.some(item => item.range.start.line === 8), JSON.stringify(defs));
  const refs = await navigation.locations(doc, new Position(8, 20), 'references');
  assert.ok(refs.some(item => item.range.start.line === 20), JSON.stringify(refs));
  const locals = await navigation.locations(doc, new Position(10, 6), 'definition');
  assert.ok(locals.some(item => item.range.start.line === 9), JSON.stringify(locals));
  const config = { target: 'debug', cwd: repo };
  const provider = new DebugConfigurationProvider(project);
  config.type = 'recurloop';
  await provider.resolveDebugConfiguration(folder, config);
  assert.ok(config.executable);
  await request('initialize');
  await request('launch', config);
  await request('setBreakpoints', { source: { path: source }, breakpoints: [{ line: 11 }] });
  await request('configurationDone');
  let mark = 0;
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  const frames = await request('stackTrace');
  assert.ok(frames.totalFrames >= 2, JSON.stringify(frames));
  assert.equal(frames.stackFrames[0].line, 11);
  const vars = await request('variables', { variablesReference: 1 });
  assert.equal(vars.variables.find(item => item.name === 'next')?.value, '6', JSON.stringify(vars));
  assert.equal(vars.variables.find(item => item.name === 'value')?.value, '3');
  const parent = await request('variables', { variablesReference: 2 });
  assert.equal(parent.variables.find(item => item.name === 'value')?.value, '3', JSON.stringify(parent));
  assert.equal((await request('evaluate', { expression: 'next + value', frameId: 1 })).result, '9');
  assert.equal((await request('setVariable', { variablesReference: 1, name: 'next', value: 'next + 1' })).value, '7');
  mark = messages.length;
  await request('next');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  assert.equal((await request('variables', { variablesReference: 1 })).variables.find(item => item.name === 'next')?.value, '7');
  await request('setBreakpoints', { source: { path: source }, breakpoints: [] });
  mark = messages.length;
  await request('continue');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'terminated'));
  const terminal = fs.readFileSync(terminalOutput, 'utf8');
  assert.ok(terminal.includes('RecurLoop IDE example application'), terminal);
  assert.ok(terminal.includes('result ='), terminal);
  assert.ok(!messages.some(message => message.event === 'output' && String(message.body.output).includes('result =')), 'Application output leaked into Debug Console');
  await request('setBreakpoints', { source: { path: source }, breakpoints: [{ line: 11, condition: 'step >= 2', hitCondition: '>= 3' }] });
  mark = messages.length;
  await request('restart');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  assert.equal((await request('evaluate', { expression: 'step', frameId: 1 })).result, '2');
  mark = messages.length;
  await request('stepOut');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  assert.equal((await request('stackTrace')).stackFrames[0].name, 'ExampleApplication:main');
  await request('setBreakpoints', { source: { path: source }, breakpoints: [{ line: 22, logMessage: 'value {value}' }] });
  mark = messages.length;
  await request('continue');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'terminated'));
  assert.ok(messages.some(message => message.event === 'output' && String(message.body.output).includes('value ')));
  await request('setBreakpoints', { source: { path: source }, breakpoints: [] });
  await request('setFunctionBreakpoints', { breakpoints: [{ name: 'ExampleApplication:advance', condition: 'step >= 1', hitCondition: '>= 2' }] });
  mark = messages.length;
  await request('restart');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  assert.equal((await request('stackTrace')).stackFrames[0].name, 'ExampleApplication:advance');
  assert.equal((await request('evaluate', { expression: 'step', frameId: 1 })).result, '1');
  mark = messages.length;
  await request('stepOut');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  await request('setFunctionBreakpoints', { breakpoints: [] });
  mark = messages.length;
  await request('stepIn');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  await request('terminate');
  await request('setFunctionBreakpoints', { breakpoints: [] });
  config.stopOnEntry = true;
  await request('launch', config);
  mark = messages.length;
  await request('configurationDone');
  const entryStop = await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  assert.equal(entryStop.body.reason, 'entry');
  // The native entry wrapper is emitted by the project file; stopOnEntry must
  // stop there before stepping into the included application implementation.
  const entryFrame = (await request('stackTrace')).stackFrames[0];
  assert.equal(entryFrame.source.path, path.join(repo, 'recurloop.project.rl'));
  assert.equal(entryFrame.name, 'application_debug_main');
  mark = messages.length;
  await request('stepIn');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  const applicationFrame = (await request('stackTrace')).stackFrames[0];
  assert.equal(applicationFrame.source.path, source);
  assert.equal(applicationFrame.name, 'ExampleApplication:main');
  await request('terminate');
  const ioSource = path.join(root, 'input.rl');
  const ioExecutable = path.join(root, 'input-application');
  fs.writeFileSync(ioSource, `link shared "c"
extern getchar() -> i32 abi sysv-amd64
extern puts(text:u8*) -> i32 abi sysv-amd64
let terminal_main = fn () -> i64 {
    puts("waiting-for-input")
    let input = getchar()
    puts("input-received")
    return 0
}
`);
  await runtime.execute(folder.uri, [`include ${JSON.stringify(ioSource)}`, `emit executable debug ${JSON.stringify(ioExecutable)} io_entry = fn () -> i64 { return terminal_main() }`]);
  await request('launch', { executable: ioExecutable, cwd: root });
  mark = messages.length;
  await request('configurationDone');
  await waitFor(() => fs.existsSync(terminalOutput) && fs.readFileSync(terminalOutput, 'utf8').includes('waiting-for-input'));
  await request('pause');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  mark = messages.length;
  await request('continue');
  fs.writeFileSync(terminalOutput + '.input', Buffer.from([3]));
  await waitFor(() => messages.slice(mark).find(message => message.event === 'stopped'));
  mark = messages.length;
  await request('continue');
  fs.writeFileSync(terminalOutput + '.input', 'x\n');
  await waitFor(() => messages.slice(mark).find(message => message.event === 'terminated'));
  assert.ok(fs.readFileSync(terminalOutput, 'utf8').includes('input-received'));
  console.log('Editor integration passed: server definitions/references/locals, native stack/variables/watch/set/steps/restart/conditions/logpoints/functions/pause, terminal input/output isolation.');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  adapter.dispose(); runtime.dispose(); terminalProcess?.kill(); fs.rmSync(root, { recursive: true, force: true });
});
