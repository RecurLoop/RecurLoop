// Real LanguageKit/project server. Count wire commands to verify incremental work.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const net = require('node:net');
const { execFileSync } = require('node:child_process');
const repo = path.resolve(__dirname, '../../..');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-navigation-test-'));
const external = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-navigation-dependency-'));
process.env.RECURLOOP_LIBRARY_PATH = process.env.RECURLOOP_TEST_LIBRARIES || path.join(repo, 'build/Release/libraries');
const testProgram = process.env.RECURLOOP_TEST_PROGRAM || path.join(repo, 'build/Release/bin/recurloop');
class CancellationError extends Error { constructor() { super('Canceled'); } }
class Token {
  isCancellationRequested = false;
  listeners = new Set();
  onCancellationRequested = callback => { this.listeners.add(callback); return { dispose: () => this.listeners.delete(callback) }; };
  cancel() { this.isCancellationRequested = true; for (const callback of this.listeners) callback(); }
}
class Position { constructor(line, character) { this.line = line; this.character = character; } }
class Range { constructor(start, end) { this.start = start; this.end = end; } }
class Location { constructor(uri, range) { this.uri = uri; this.range = range; } }
class WorkspaceEdit { edits = []; replace(uri, range, value) { this.edits.push({ uri, range, value }); } }
class DocumentSymbol { constructor(name) { this.name = name; } }
class SymbolInformation { constructor(name, kind, container, location) { Object.assign(this, { name, kind, container, location }); } }
const folder = { uri: { fsPath: root }, name: 'fixture', index: 0 };
const documents = new Map();
function document(file, text = fs.readFileSync(file, 'utf8')) {
  const doc = { uri: { fsPath: file }, version: 1, getText: () => text,
    setText(value) { text = value; this.version++; },
    offsetAt: p => text.split('\n').slice(0, p.line).reduce((a, line) => a + line.length + 1, 0) + p.character,
    positionAt: offset => { const lines = text.slice(0, offset).split('\n'); return new Position(lines.length - 1, lines.at(-1).length); } };
  documents.set(file, doc); return doc;
}
const vscode = { CancellationError, Position, Range, Location, WorkspaceEdit, DocumentSymbol, SymbolInformation,
  SymbolKind: { Function: 11, Class: 4, Namespace: 2, Field: 7, Variable: 12 }, Uri: { file: fsPath => ({ fsPath }) },
  workspace: { workspaceFolders: [folder], get textDocuments() { return [...documents.values()]; }, getWorkspaceFolder: uri => uri.fsPath === root || uri.fsPath.startsWith(root + path.sep) ? folder : undefined,
    openTextDocument: async uri => documents.get(uri.fsPath) ?? document(uri.fsPath),
    getConfiguration: () => ({ get: (key, fallback) => key === 'executablePath' ? testProgram : key === 'terminal.libraries' ? [] : fallback }) } };
const originalLoad = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : originalLoad.call(this, name, ...rest); };
const commands = [];
let onCommand;
const originalConnect = net.createConnection;
net.createConnection = function(...args) {
  const socket = originalConnect.apply(this, args);
  const write = socket.write;
  socket.write = function(data, ...rest) {
    for (const command of String(data).split('\n').filter(Boolean)) { commands.push(command); onCommand?.(command); }
    return write.call(this, data, ...rest);
  };
  return socket;
};
const { RecurLoopRuntime } = require('../out/runtime');
const { NavigationController } = require('../out/navigation');
const runtime = new RecurLoopRuntime({ appendLine() {}, append() {} });
const nav = new NavigationController(runtime);
const count = prefix => commands.filter(command => command.startsWith(prefix)).length;
const updates = () => count('recurloop languagekit_analysis_request\tupdate');
const traces = () => count(':trace\t');
const queries = () => count('recurloop languagekit_analysis_request\tquery');
const at = (doc, text, occurrence = 0) => {
  let offset = -1;
  for (let i = 0; i <= occurrence; ++i) offset = doc.getText().indexOf(text, offset + 1);
  assert.ok(offset >= 0, text); return doc.positionAt(offset);
};
(async () => {
  const externalPath = path.join(external, 'functions.rl');
  const imagePath = path.join(external, 'binary.rli');
  const imageSource = path.join(external, 'binary.rl');
  fs.writeFileSync(imageSource, `let imported_value = fn (value:i64) -> i64 { return value + 10 }\nengine export ${JSON.stringify(imagePath)}\n`);
  execFileSync(testProgram, ['--file', imageSource], { stdio: 'pipe' });
  fs.writeFileSync(externalPath, 'let multiply = fn (value:i64) -> i64 { return value * 2 }\n');
  const defsPath = path.join(root, 'definitions.rl');
  const callsPath = path.join(root, 'calls.rl');
  const entryPath = path.join(root, 'recurloop.project.rl');
  const definitions = 'record Box { value:i64 }\nlet add = fn (value:i64) -> i64 { let result = value + 1; return result }\nlet shadow = fn (value:i64) -> i64 { let result = value; if value > 0 { var result = value + 2; result += 1 }; return result }\n';
  const calls = '// add in comment\nlet caller = fn () -> i64 { let marker:u8* = "😀"; return add(42) }\nlet use_box = fn (box:Box*) -> i64 { return box.value }\nlet external_caller = fn () -> i64 { return multiply(2) }\nlet library_caller = fn () -> i64 { return imported_value(2) }\n';
  fs.writeFileSync(defsPath, definitions); fs.writeFileSync(callsPath, calls);
  fs.writeFileSync(entryPath, `engine import ${JSON.stringify(imagePath)}\ninclude ${JSON.stringify(externalPath)}\ninclude "definitions.rl"\ninclude "calls.rl"\n`);
  const defs = document(defsPath), caller = document(callsPath);
  // Document/local operations inspect only the current file, even in a cold project.
  assert.ok((await nav.symbols(defs)).some(symbol => symbol.name === 'add'));
  assert.equal(traces(), 1); assert.equal(updates(), 1); assert.equal(count(':cache-dependencies'), 0);
  // Built-in/image-only phrases have no definition in the source graph. Cold
  // Ctrl+click must not inspect unrelated files, even if the library's build
  // source happens to still be present on disk.
  assert.equal((await nav.locations(defs, at(defs, 'i64'), 'definition')).length, 0);
  assert.equal(traces(), 1); assert.equal(updates(), 1); assert.equal(count(':cache-dependencies'), 0);
  const local = await nav.locations(defs, at(defs, 'result', 1), 'definition');
  assert.equal(local.length, 1); assert.equal(local[0].range.start.character, definitions.split('\n')[1].indexOf('result'));
  assert.equal(traces(), 1); assert.equal(updates(), 1); assert.equal(count(':cache-dependencies'), 0);
  const inner = await nav.locations(defs, at(defs, 'result', 3), 'references', false);
  assert.equal(inner.length, 1); assert.equal(inner[0].range.start.line, 2);
  const outer = await nav.locations(defs, at(defs, 'result', 2), 'references', false);
  assert.equal(outer.length, 1); assert.equal(outer[0].range.start.character, definitions.split('\n')[2].lastIndexOf('result'));
  assert.equal((await nav.locations(caller, at(caller, 'imported_value'), 'definition')).length, 0);
  assert.equal(traces(), 2); assert.equal(updates(), 2); assert.equal(count(':cache-dependencies'), 0);
  const binaryTrace = await runtime.inspect(caller);
  assert.ok(!binaryTrace.includes('E\t'), binaryTrace);
  const binaryOrigin = binaryTrace.split('\n').map(row => row.split('\t'))
    .find(fields => fields[0] === 'G' && Buffer.from(fields[2], 'hex').toString() === 'imported_value');
  assert.equal(Buffer.from(binaryOrigin[4], 'hex').toString(), imagePath);
  assert.equal(binaryOrigin[5], '0');
  assert.equal((await nav.locations(caller, at(caller, 'imported_value'), 'references', false)).length, 1);
  const refs = await nav.locations(defs, at(defs, 'add'), 'references', false);
  assert.equal(refs.length, 1); assert.equal(refs[0].uri.fsPath, callsPath); assert.equal(refs[0].range.start.line, 1); assert.equal(refs[0].range.start.character, calls.split('\n')[1].indexOf('add'));
  assert.ok((await nav.locations(caller, at(caller, 'box:Box'), 'type-definition')).some(item => item.uri.fsPath === defsPath && item.range.start.line === 0));
  assert.ok((await nav.locations(caller, at(caller, 'multiply'), 'definition')).some(item => item.uri.fsPath === externalPath));
  const warm = { traces: traces(), updates: updates(), dependencies: count(':cache-dependencies') };
  const warmQueries = queries();
  await Promise.all([nav.locations(defs, at(defs, 'add'), 'references'), nav.locations(caller, at(caller, 'add', 1), 'definition')]);
  assert.deepEqual({ traces: traces(), updates: updates(), dependencies: count(':cache-dependencies') }, warm);
  // Ctrl+hover and Ctrl+click ask for the same location repeatedly. Once cached,
  // both definition and references must avoid even scope/query round trips.
  const cachedQueries = queries();
  assert.ok(cachedQueries > warmQueries);
  for (let repeat = 0; repeat < 10; ++repeat) {
    assert.equal((await nav.locations(caller, at(caller, 'add', 1), 'definition')).length, 1);
    assert.equal((await nav.locations(defs, at(defs, 'add'), 'references', false)).length, 1);
  }
  assert.equal(queries(), cachedQueries);
  // An unsaved edit rebuilds exactly one file, preserving the project index.
  caller.setText(calls.replace('add(42)', 'add(add(42))'));
  assert.equal((await nav.locations(defs, at(defs, 'add'), 'references', false)).length, 2);
  assert.equal(traces(), warm.traces + 1); assert.equal(updates(), warm.updates + 1);
  const edit = await nav.rename(defs, at(defs, 'add'), 'sum'); assert.equal(edit.edits.length, 3);
  assert.ok((await nav.workspaceSymbols('add')).some(symbol => symbol.name === 'add'));
  caller.setText(calls + 'definitely_missing_phrase\n');
  await nav.locations(defs, at(defs, 'add'), 'references');
  assert.equal((await nav.locations(defs, at(defs, 'result', 1), 'definition')).length, 1);
  assert.equal((await nav.rename(defs, at(defs, 'result', 1), 'total')).edits.length, 2);
  await assert.rejects(nav.rename(defs, at(defs, 'add'), 'sum'));
  caller.setText(calls);
  // Shared inspections survive cancellation of one consumer.
  caller.setText(calls.replace('42', '43'));
  const controller = new AbortController();
  onCommand = command => {
    if (command.startsWith(':trace\t')) { onCommand = undefined; setImmediate(() => controller.abort(new CancellationError())); }
  };
  const first = runtime.inspect(caller, true, controller.signal);
  const second = runtime.inspect(caller, true);
  await assert.rejects(first, CancellationError); assert.ok((await second).includes('P\t'));
  // Queued cancellation must not discard or interrupt another query.
  const queuedToken = new Token();
  const live = nav.locations(defs, at(defs, 'add'), 'references');
  const queued = nav.locations(defs, at(defs, 'add'), 'references', true, queuedToken);
  queuedToken.cancel(); await assert.rejects(queued, CancellationError); await live;
  // Cancel during a server-side update. Finish that atomic step and retain all
  // classified files rather than importing LanguageKit/rebuilding the project.
  const activeToken = new Token();
  caller.setText(calls + ' '.repeat(3000));
  const beforeCancellation = { traces: traces(), updates: updates(), imports: count(':baseline') };
  onCommand = command => {
    if (command.startsWith('recurloop languagekit_analysis_request\tupdate')) {
      onCommand = undefined; setImmediate(() => activeToken.cancel());
    }
  };
  await assert.rejects(nav.locations(caller, at(caller, 'add', 1), 'definition', true, activeToken), CancellationError);
  assert.ok((await nav.locations(caller, at(caller, 'add', 1), 'definition')).some(item => item.uri.fsPath === defsPath));
  assert.equal(traces(), beforeCancellation.traces + 1);
  assert.equal(updates(), beforeCancellation.updates + 1);
  assert.equal(count(':baseline'), beforeCancellation.imports);
  // Cancel an active read too; the next query reuses the same private session.
  const readToken = new Token();
  const beforeRead = { traces: traces(), updates: updates(), imports: count(':baseline') };
  onCommand = command => {
    if (command.startsWith('recurloop languagekit_analysis_request\tquery')) {
      onCommand = undefined; setImmediate(() => readToken.cancel());
    }
  };
  await assert.rejects(nav.locations(caller, at(caller, 'multiply'), 'references', true, readToken), CancellationError);
  assert.equal((await nav.locations(caller, at(caller, 'multiply'), 'references', false)).length, 1);
  assert.deepEqual({ traces: traces(), updates: updates(), imports: count(':baseline') }, beforeRead);
  // Moving the cursor during an expensive trace must retain that shared work,
  // even when there is no highlighting request keeping it alive.
  const traceToken = new Token();
  caller.setText(calls + ' '.repeat(4000));
  const beforeTrace = { traces: traces(), updates: updates(), imports: count(':baseline') };
  onCommand = command => {
    if (command.startsWith(':trace\t')) {
      onCommand = undefined; setImmediate(() => traceToken.cancel());
    }
  };
  await assert.rejects(nav.locations(caller, at(caller, 'add', 1), 'definition', true, traceToken), CancellationError);
  assert.equal((await nav.locations(caller, at(caller, 'add', 1), 'definition')).length, 1);
  assert.equal(traces(), beforeTrace.traces + 1);
  assert.equal(updates(), beforeTrace.updates + 1);
  assert.equal(count(':baseline'), beforeTrace.imports);
  caller.setText(calls);
  assert.ok((await nav.locations(caller, at(caller, 'add', 1), 'definition')).some(item => item.uri.fsPath === defsPath));
  // Publication revalidates semantics while unchanged classified files stay cached.
  const beforeReload = updates();
  await runtime.reload(folder.uri);
  await nav.locations(defs, at(defs, 'add'), 'references');
  assert.equal(updates(), beforeReload);
  fs.writeFileSync(entryPath, 'include "definitions.rl"\n');
  documents.get(entryPath).setText('include "definitions.rl"\n');
  fs.unlinkSync(callsPath);
  await runtime.reload(folder.uri);
  assert.equal((await nav.locations(defs, at(defs, 'add'), 'references', false)).length, 0);
  assert.ok(count('recurloop languagekit_analysis_request\tremove') > 0);
  await runtime.restart(folder.uri);
  assert.equal((await nav.locations(defs, at(defs, 'add'), 'references', false)).length, 0);
  // Types consumed by the compiler carry exact references, including qualified
  // names in intrinsics, signatures and record fields from included files.
  const typesPath = path.join(root, 'types.rl');
  const usesPath = path.join(root, 'type-uses.rl');
  const typesSource = 'let Game = phrase { dictionary = true }\nrecord Game:State { value:i64 }\nrecord Holder { state:Game:State* }\n';
  const usesSource = 'let make = fn (input:Game:State*) -> Game:State* {\n' +
    '    let state = alloc(Game:State)\n' +
    '    let bytes = sizeof(Game:State)\n' +
    '    let converted = cast(Game:State*, input)\n' +
    '    return state\n}\n';
  fs.writeFileSync(typesPath, typesSource); fs.writeFileSync(usesPath, usesSource);
  const typesDoc = document(typesPath), usesDoc = document(usesPath);
  const typeEntry = 'include "types.rl"\ninclude "type-uses.rl"\n';
  fs.writeFileSync(entryPath, typeEntry); documents.get(entryPath).setText(typeEntry);
  await runtime.reload(folder.uri);
  for (const intrinsic of ['alloc', 'sizeof', 'cast']) {
    const offset = usesSource.indexOf(`${intrinsic}(Game:State`) + intrinsic.length + 1;
    for (const component of [0, 5]) {
      const definitions = await nav.locations(usesDoc, usesDoc.positionAt(offset + component), 'definition');
      assert.equal(definitions.length, 1);
      assert.equal(definitions[0].uri.fsPath, typesPath);
      assert.equal(definitions[0].range.start.line, 1);
      assert.equal(definitions[0].range.start.character, 'record '.length);
      assert.equal(definitions[0].range.end.character, 'record Game:State'.length);
    }
  }
  const typeRefs = await nav.locations(typesDoc, at(typesDoc, 'Game:State'), 'references', false);
  assert.equal(typeRefs.length, 6);
  const allocType = usesDoc.positionAt(usesSource.indexOf('alloc(Game:State') + 'alloc('.length + 5);
  assert.equal((await nav.locations(usesDoc, allocType, 'references', false)).length, typeRefs.length);
  for (const location of typeRefs) {
    const doc = documents.get(location.uri.fsPath);
    assert.equal(doc.getText().slice(doc.offsetAt(location.range.start), doc.offsetAt(location.range.end)), 'Game:State');
  }
  // Reopened documents can reuse a version number. Identity must invalidate
  // cached results too, including references requested from another document.
  const reopened = document(usesPath, usesSource + 'let copy = fn (input:Game:State*) -> Game:State* { return input }\n');
  assert.equal(reopened.version, usesDoc.version);
  assert.equal((await nav.locations(typesDoc, at(typesDoc, 'Game:State'), 'references', false)).length, 8);
  // Record fields are resolved by receiver type, including reads, writes,
  // inferred aliases, nested records, pointer/array indexing and a local with
  // the same name. Other records' identically named fields stay independent.
  const fieldsPath = path.join(root, 'fields.rl');
  const fieldUsesPath = path.join(root, 'field-uses.rl');
  const fieldsSource = 'let Game = phrase { dictionary = true }\n' +
    'record Game:State {\n    paddle_x:f64\n    ball_x:f64 ball_y:f64\n}\n' +
    'record Other { ball_x:f64 }\nrecord Envelope { state:Game:State }\n' +
    'record Tuple (ball_x:f64, paddle_x:f64)\n' +
    'let Game:reset_ball = fn (state:Game:State*, ball_x:f64) -> void {\n' +
    '    state.ball_x = state.paddle_x\n    let alias = state\n    alias.ball_x += ball_x\n}\n';
  const fieldUses = 'let read = fn (state:Game:State*, other:Other*, envelope:Envelope*, tuple:Tuple*, rows:Game:State*) -> f64 {\n' +
    '    let value = state.ball_x\n    other.ball_x = value\n    envelope.state.ball_x = tuple.ball_x\n' +
    '    rows[0].ball_x = value\n    let allocated = alloc(Game:State)\n    allocated.ball_x = value\n' +
    '    let converted = cast(Game:State*, rows)\n    converted.ball_x = value\n' +
    '    { let state = other; state.ball_x = value }\n    return state.paddle_x\n}\n';
  fs.writeFileSync(fieldsPath, fieldsSource); fs.writeFileSync(fieldUsesPath, fieldUses);
  const fieldsDoc = document(fieldsPath), fieldUsesDoc = document(fieldUsesPath);
  const fieldsEntry = 'include "fields.rl"\ninclude "field-uses.rl"\n';
  fs.writeFileSync(entryPath, fieldsEntry); documents.get(entryPath).setText(fieldsEntry);
  await runtime.reload(folder.uri);
  const declaration = (doc, offset) => doc.positionAt(offset);
  const ballDeclaration = fieldsSource.indexOf('ball_x:f64');
  const paddleDeclaration = fieldsSource.indexOf('paddle_x:f64');
  const ballUse = fieldsSource.indexOf('state.ball_x') + 'state.'.length;
  const paddleUse = fieldsSource.indexOf('state.paddle_x') + 'state.'.length;
  const checkDefinition = async (doc, offset, expected) => {
    const locations = await nav.locations(doc, declaration(doc, offset), 'definition');
    assert.equal(locations.length, 1);
    assert.equal(locations[0].uri.fsPath, fieldsPath);
    assert.equal(fieldsDoc.offsetAt(locations[0].range.start), expected);
  };
  const beforeFieldLookup = traces();
  await checkDefinition(fieldsDoc, ballUse, ballDeclaration);
  await checkDefinition(fieldsDoc, paddleUse, paddleDeclaration);
  assert.equal(traces(), beforeFieldLookup + 1);
  for (const expression of ['state.ball_x', 'envelope.state.ball_x', 'rows[0].ball_x', 'allocated.ball_x', 'converted.ball_x']) {
    await checkDefinition(fieldUsesDoc, fieldUses.indexOf(expression) + expression.lastIndexOf('.') + 1, ballDeclaration);
  }
  await checkDefinition(fieldUsesDoc, fieldUses.indexOf('other.ball_x') + 6, fieldsSource.indexOf('ball_x:f64', ballDeclaration + 1));
  await checkDefinition(fieldUsesDoc, fieldUses.indexOf('tuple.ball_x') + 6, fieldsSource.indexOf('ball_x:f64', fieldsSource.indexOf('record Tuple')));
  const ballRefs = await nav.locations(fieldsDoc, declaration(fieldsDoc, ballDeclaration), 'references', false);
  assert.equal(ballRefs.length, 7);
  assert.equal((await nav.locations(fieldsDoc, declaration(fieldsDoc, ballUse), 'references', false)).length, 7);
  assert.equal((await nav.locations(fieldsDoc, declaration(fieldsDoc, paddleUse), 'references', false)).length, 2);
  for (const location of ballRefs) {
    const doc = documents.get(location.uri.fsPath);
    assert.equal(doc.getText().slice(doc.offsetAt(location.range.start), doc.offsetAt(location.range.end)), 'ball_x');
  }
  assert.equal((await nav.rename(fieldsDoc, declaration(fieldsDoc, ballDeclaration), 'ball_position')).edits.length, 8);
  await runtime.restart(folder.uri);
  await checkDefinition(fieldsDoc, ballUse, ballDeclaration);
  assert.equal((await nav.locations(fieldsDoc, declaration(fieldsDoc, ballUse), 'references', false)).length, 7);
  console.log('Navigation passed: shared traces, scoped queries, cached results, incremental edits/publication/removal/reopening, Unicode, rename, symbols, retained work after cancellation and restart.');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  nav.dispose(); runtime.dispose(); fs.rmSync(root, { recursive: true, force: true }); fs.rmSync(external, { recursive: true, force: true });
  net.createConnection = originalConnect; Module._load = originalLoad;
});
