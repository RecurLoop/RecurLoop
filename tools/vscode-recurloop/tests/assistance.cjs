// Real project/runtime; only VS Code's rendering boundary is replaced.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const repo = path.resolve(__dirname, '../../..');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-assistance-test-'));
process.env.RECURLOOP_LIBRARY_PATH = process.env.RECURLOOP_TEST_LIBRARIES || path.join(repo, 'build/Release/libraries');
const executable = process.env.RECURLOOP_TEST_PROGRAM || path.join(repo, 'build/Release/bin/recurloop');
class Position { constructor(line, character) { Object.assign(this, { line, character }); } }
class Range { constructor(start, end) { Object.assign(this, { start, end }); } }
class MarkdownString {
  constructor(value = '') { this.value = value; }
  appendMarkdown(value) { this.value += value; return this; }
  appendCodeblock(value) { this.value += `\n\n${value}`; return this; }
}
class SnippetString {
  constructor(value = '') { this.value = value; }
  appendPlaceholder(value) { this.value += '${1:' + value + '}'; return this; }
}
class CompletionItem { constructor(label, kind) { Object.assign(this, { label, kind }); } }
class SignatureInformation { constructor(label, documentation) { Object.assign(this, { label, documentation, parameters: [] }); } }
class ParameterInformation { constructor(label, documentation) { Object.assign(this, { label, documentation }); } }
class Hover { constructor(contents, range) { Object.assign(this, { contents, range }); } }
class CancellationError extends Error {}
const disposable = () => ({ dispose() {} });
const providers = {}, commands = {};
const colorRanges = new Map();
const uri = fsPath => ({ fsPath, toString: () => `file://${fsPath}` });
const folder = { uri: uri(root), name: 'help', index: 0 };
const vscode = { Position, Range, MarkdownString, SnippetString, CompletionItem, SignatureInformation, ParameterInformation, Hover,
  SignatureHelp: class {}, CancellationError, CompletionItemKind: { Text: 0, Keyword: 1, Snippet: 2, Value: 3, Module: 4, Class: 5 },
  commands: { registerCommand(name, callback) { commands[name] = callback; return disposable(); } },
  workspace: { workspaceFolders: [folder], textDocuments: [], getWorkspaceFolder: () => folder,
    getConfiguration: () => ({ get: (key, fallback) => key === 'executablePath' ? executable : key === 'terminal.libraries' ? [] : fallback }),
    onDidChangeTextDocument: disposable, onDidOpenTextDocument: disposable, onDidCloseTextDocument: disposable },
  window: { visibleTextEditors: [], onDidChangeVisibleTextEditors: disposable,
    createTextEditorDecorationType: ({ color }) => ({ color, dispose() { colorRanges.delete(color); } }) },
  languages: new Proxy({ createDiagnosticCollection: () => ({ ...disposable(), set() {}, delete() {} }) }, {
    get(target, key) {
      return target[key] || ((_selector, provider) => { providers[key] = provider || _selector; return disposable(); });
    }
  })
};
const original = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : original.call(this, name, ...rest); };
const { RecurLoopRuntime } = require('../out/runtime');
const { AnalysisController, parseInspection } = require('../out/analysis');
const output = { appendLine() {}, append() {} };
const runtime = new RecurLoopRuntime(output);
const analysis = new AnalysisController(runtime, output);
function document(source) {
  return { uri: uri(path.join(root, 'main.rl')), languageId: 'recurloop', version: 1,
    getText: () => source,
    offsetAt: position => source.split('\n').slice(0, position.line).reduce((n, line) => n + line.length + 1, 0) + position.character,
    positionAt: offset => { const lines = source.slice(0, offset).split('\n'); return new Position(lines.length - 1, lines.at(-1).length); },
    lineAt: line => ({ text: source.split('\n')[line] }) };
}
const complete = async (source, offset = source.length) => {
  const doc = document(source);
  return providers.registerCompletionItemProvider.provideCompletionItems(doc, doc.positionAt(offset));
};
const labels = items => items.map(item => item.label);
(async () => {
  const definitions = fs.readFileSync(path.join(repo, 'examples/03-phrases-and-syntax/editor-help/main.rl'), 'utf8');
  fs.writeFileSync(path.join(root, 'main.rl'), definitions);
  fs.writeFileSync(path.join(root, 'recurloop.project.rl'), 'include "main.rl"\n');
  // The source's selector controls the result, including an inherited alias.
  for (const phrase of ['show', 'display']) {
    const items = await complete(definitions + `\n${phrase} `);
    assert.deepEqual(labels(items), ['answer', 'greeting']);
    assert.match(items[0].documentation.value, /A name in Values/);
  }
  // An argument dictionary may itself be an alias, preserving docs/selectors.
  const inherited = definitions + `
let BorrowedHelp = [ arguments = <ShowHelp:arguments> ]
set show.help = <BorrowedHelp>
show `;
  const inheritedItems = await complete(inherited);
  assert.deepEqual(labels(inheritedItems), ['answer', 'greeting']);
  assert.match(inheritedItems[0].documentation.value, /A name in Values/);
  const unicode = definitions + '\n// 😀\nshow gr';
  const items = await complete(unicode);
  assert.deepEqual(labels(items), ['greeting']);
  assert.equal(document(unicode).offsetAt(items[0].range.start), unicode.length - 2);
  // Snippets use the spelling actually chosen, including aliases.
  const alias = (await complete(definitions + '\ndisp')).find(item => item.label === 'display');
  assert.equal(alias.insertText.value, 'display ${1:answer}');
  // No source after the cursor can introduce a completion candidate.
  const prefix = definitions + '\nla';
  const later = prefix + '\nsyntax later <value:expr> => print ${value}\n';
  assert.ok(!labels(await complete(later, prefix.length)).includes('later'));
  const custom = definitions + '\nsyntax choose [quiet] (fast | safe) <value:number> => print ${value}\nchoose ';
  assert.deepEqual(labels(await complete(custom)), ['fast', 'quiet', 'safe']);
  assert.deepEqual(labels(await complete(custom + 'sa')), ['safe']);
  const separated = definitions + '\nsyntax named <name:id> with <value:number> => print 42\nnamed item';
  assert.equal((await complete(separated)).find(item => item.label === 'with').insertText, ' with');
  const joined = definitions + '\nsyntax sealed <value:raw> <join:none> end => print 42\nsealed item';
  assert.equal((await complete(joined)).find(item => item.label === 'end').insertText, 'end');
  const finishedIf = definitions + '\nif true {}\n';
  const next = labels(await complete(finishedIf));
  assert.ok(next.includes('else') && next.includes('show'));
  const multiword = definitions + '\nlet "ask for help" = <print>\nask f';
  assert.deepEqual(labels(await complete(multiword)), ['ask for help']);
  assert.deepEqual(labels(await complete(definitions + '\nValues:gr')), ['greeting']);
  const selected = definitions + `
let Base = phrase {}
let Objects = []
let Objects:allowed = phrase { prototype = <Base> kind = "literal" }
let Objects:wrong_kind = phrase { prototype = <Base> kind = "type" }
let Objects:wrong_prototype = phrase { kind = "literal" }
syntax use <value:id> => print 42
let UseHelp = [
    arguments = [ value = phrase { dictionary = true docs = "Compatible object." } ]
]
let UseHelp:arguments:value:dictionary = <Objects>
let UseHelp:arguments:value:prototype = <Base>
let UseHelp:arguments:value:kind = phrase { payload = "literal" }
set use.help = <UseHelp>
use `;
  assert.deepEqual(labels(await complete(selected)), ['allowed']);
  const opaque = definitions + `
let OpaqueHelp = [
    pattern = phrase { payload = "(yes | no)" }
]
let confirm = phrase {
    type = <phrase-types:elaborate>
    help = <OpaqueHelp>
    action = fn (state:Context*, called:Phrase*) -> void {
        if context:source:consume(state, "yes") { return }
        if context:source:consume(state, "no") { return }
        context:diagnostic:error(state, "Choose yes or no.")
    }
}
confirm `;
  assert.deepEqual(labels(await complete(opaque)), ['no', 'yes']);
  const sigDoc = document(definitions + '\nshow ');
  const signature = await providers.registerSignatureHelpProvider.provideSignatureHelp(sigDoc, sigDoc.positionAt(sigDoc.getText().length));
  assert.equal(signature.signatures[0].label, 'show <value:id>');
  assert.match(signature.signatures[0].parameters[0].documentation, /A name in Values/);
  // Help discovery uses the same catalog and inserts author-owned snippets.
  let inserted;
  vscode.window.activeTextEditor = { document: sigDoc, selection: { active: sigDoc.positionAt(definitions.length) }, insertSnippet: async snippet => { inserted = snippet.value; } };
  vscode.window.showQuickPick = async entries => entries.find(item => item.label === 'display');
  await commands['recurloop.help']();
  assert.equal(inserted, 'display ${1:answer}');
  const disabled = parseInspection({ version: 1, getText: () => '' }, '');
  assert.deepEqual(disabled.expected, []);
  // Runtime variable docs must reach both declarations and expression reads.
  // Comments/string contents and longer names must not be treated as reads.
  const variableSource = `// π 😀 pi in a comment\r\nvar pi = 3.14\r\nset pi.docs = "Przybliżenie **liczby π**."\r\nconst tau = pi * 2\r\nset tau.docs = "Dwa razy π."\r\nprint str(pi)\r\nprint pi+2\r\nvar pirate = 7\r\nprint pirate\r\nprint "pi in a string"\r\n`;
  fs.writeFileSync(path.join(root, 'main.rl'), variableSource);
  await runtime.reload(folder.uri);
  analysis.invalidate();
  const variableDoc = document(variableSource);
  const hoverAt = offset => providers.registerHoverProvider.provideHover(variableDoc, variableDoc.positionAt(offset));
  const variableOccurrences = ['var pi', 'const tau = pi', 'str(pi)', 'print pi+2'];
  for (const fragment of variableOccurrences) {
    const start = variableSource.indexOf(fragment) + fragment.indexOf('pi');
    const hover = await hoverAt(start + 1);
    assert.match(hover.contents.value, /Przybliżenie \*\*liczby π\*\*\./);
    assert.equal(variableDoc.offsetAt(hover.range.start), start);
    assert.equal(variableDoc.offsetAt(hover.range.end), start + 2);
  }
  assert.match((await hoverAt(variableSource.indexOf('tau') + 1)).contents.value, /Dwa razy π\./);
  for (const offset of [variableSource.indexOf('pi in a comment'), variableSource.indexOf('pi in a string'),
    variableSource.indexOf('print pirate') + 7, variableSource.indexOf('pi+2') + 2]) {
    assert.ok(!(await hoverAt(offset))?.contents.value.includes('Przybliżenie'));
  }
  // The same response remains valid through editor cache hits and image replay.
  assert.match((await hoverAt(variableSource.indexOf('var pi') + 5)).contents.value, /Przybliżenie/);
  await runtime.restart(folder.uri);
  analysis.invalidate();
  assert.match((await hoverAt(variableSource.indexOf('str(pi)') + 5)).contents.value, /Przybliżenie/);
  // An unsaved metadata change must invalidate the old document result.
  const changed = variableSource.replace('Przybliżenie **liczby π**.', 'Nowy opis π.');
  const changedDoc = { ...document(changed), version: 2 };
  const changedHover = await providers.registerHoverProvider.provideHover(changedDoc,
    changedDoc.positionAt(changed.indexOf('var pi') + 5));
  assert.match(changedHover.contents.value, /Nowy opis π\./);
  assert.ok(!changedHover.contents.value.includes('Przybliżenie'));
  // Metadata restored from an included module must document reads in another file.
  fs.writeFileSync(path.join(root, 'values.rl'), 'var pi = 3.14\nset pi.docs = "Opis z biblioteki."\n');
  const consumer = 'include "values.rl"\nprint pi\n';
  fs.writeFileSync(path.join(root, 'main.rl'), consumer);
  await runtime.reload(folder.uri);
  analysis.invalidate();
  const consumerDoc = document(consumer);
  const consumerHover = await providers.registerHoverProvider.provideHover(consumerDoc,
    consumerDoc.positionAt(consumer.indexOf('print pi') + 7));
  assert.match(consumerHover.contents.value, /Opis z biblioteki\./);
  const localSource = `// π 😀\r\nvar tick = 99
set tick.docs = "Global description."
let Probe = phrase { dictionary = true permanent = true }
link shared "c"
extern printf(format:u8*, ...) -> i32 abi sysv-amd64
let Probe:advance = fn (distance:i64, speed:i64) -> i64 { return distance + speed }
let Probe:main = fn () -> i64 {
    var distance:i64 = 0
    var tick:i64 = 1
    const before = tick
    set tick.docs = "Przykładowa treść"
    // tick in a comment
    const caption = "tick in a string"
    while tick <= 3 {
        distance = Probe:advance(distance, 10)
        printf("Tick %lld: %lld km\\n", tick, distance)
        tick += 1
    }
    if tick > 0 {
        var tick:i64 = 10
        set tick.docs = "Inner description."
        tick += 2
    }
    return tick
}
let other = fn () -> i64 {
    var tick:i64 = 7
    return tick
}
print tick
`;
  fs.writeFileSync(path.join(root, 'main.rl'), localSource);
  await runtime.reload(folder.uri);
  analysis.invalidate();
  const localDoc = document(localSource);
  const localHover = async fragment => {
    const start = localSource.indexOf(fragment) + fragment.indexOf('tick');
    const hover = await providers.registerHoverProvider.provideHover(localDoc, localDoc.positionAt(start + 1));
    assert.equal(localDoc.offsetAt(hover.range.start), start);
    assert.equal(localDoc.offsetAt(hover.range.end), start + 4);
    return hover.contents.value;
  };
  for (const fragment of ['var tick:i64 = 1\n', 'const before = tick', 'set tick.docs = "Przykładowa',
    'while tick', ', tick, distance)', 'tick += 1', 'return tick\n}']) {
    assert.match(await localHover(fragment), /Przykładowa treść/);
  }
  for (const fragment of ['var tick:i64 = 10', 'set tick.docs = "Inner', 'tick += 2']) {
    const text = await localHover(fragment);
    assert.match(text, /Inner description/);
    assert.ok(!text.includes('Przykładowa') && !text.includes('Global description'));
  }
  const undocumented = await localHover('var tick:i64 = 7');
  assert.ok(!undocumented.includes('description') && !undocumented.includes('Przykładowa'));
  assert.ok(!(await localHover('return tick\n}\nprint tick')).includes('Przykładowa'));
  for (const fragment of ['tick in a comment', 'tick in a string']) {
    const hover = await providers.registerHoverProvider.provideHover(localDoc,
      localDoc.positionAt(localSource.indexOf(fragment) + 1));
    assert.ok(!hover?.contents.value.includes('Przykładowa'));
  }
  assert.match(await localHover('print tick'), /Global description/);
  await runtime.restart(folder.uri);
  analysis.invalidate();
  assert.match(await localHover('tick += 1'), /Przykładowa treść/);
  const editedLocal = localSource.replace('Przykładowa treść', 'Zmieniony opis lokalny.');
  const editedDoc = { ...document(editedLocal), version: 2 };
  const editedHover = await providers.registerHoverProvider.provideHover(editedDoc,
    editedDoc.positionAt(editedLocal.indexOf('while tick') + 7));
  assert.match(editedHover.contents.value, /Zmieniony opis lokalny/);
  assert.ok(!editedHover.contents.value.includes('Przykładowa treść'));
  const functionSource = localSource.replace('    var distance:i64 = 0', `    var distance:i64 = 0
    let exampleFn = fn() -> i64 {
        return 1
    }
    set exampleFn.color = "#008800"
    set exampleFn.docs = "aaa"
    exampleFn()`) + `
let exampleFn = fn() -> i64 {
    return 1
}
exampleFn()
set exampleFn.color = "#FF8800"
set exampleFn.docs = "bbb"
exampleFn()
print exampleFn()
`;
  fs.writeFileSync(path.join(root, 'main.rl'), functionSource);
  await runtime.reload(folder.uri);
  analysis.invalidate();
  const functionDoc = document(functionSource);
  vscode.window.visibleTextEditors = [{ document: functionDoc,
    setDecorations: (decoration, ranges) => colorRanges.set(decoration.color, ranges) }];
  const localFunctionEnd = functionSource.indexOf('\nlet exampleFn');
  const expectedFunctionRanges = [];
  const expectedGlobalRanges = [];
  for (const match of functionSource.matchAll(/\bexampleFn\b/g)) {
    const hover = await providers.registerHoverProvider.provideHover(functionDoc,
      functionDoc.positionAt(match.index + 1));
    if (match.index < localFunctionEnd) {
      assert.match(hover.contents.value, /aaa/);
      assert.ok(!hover.contents.value.includes('bbb'));
      expectedFunctionRanges.push([match.index, match.index + 'exampleFn'.length]);
    } else {
      assert.match(hover.contents.value, /bbb/);
      assert.ok(!hover.contents.value.includes('aaa'));
      expectedGlobalRanges.push([match.index, match.index + 'exampleFn'.length]);
    }
  }
  const checkFunctionColor = async () => {
    await analysis.refresh(functionDoc);
    assert.deepEqual(colorRanges.get('#008800').map(range => [functionDoc.offsetAt(range.start),
      functionDoc.offsetAt(range.end)]).sort((a, b) => a[0] - b[0]), expectedFunctionRanges);
    assert.deepEqual(colorRanges.get('#FF8800').map(range => [functionDoc.offsetAt(range.start),
      functionDoc.offsetAt(range.end)]).sort((a, b) => a[0] - b[0]), expectedGlobalRanges);
    for (const [color, ranges] of colorRanges) {
      for (const range of ranges) {
        const offsets = [functionDoc.offsetAt(range.start), functionDoc.offsetAt(range.end)];
        const local = expectedFunctionRanges.some(item => item[0] === offsets[0] && item[1] === offsets[1]);
        const global = expectedGlobalRanges.some(item => item[0] === offsets[0] && item[1] === offsets[1]);
        if (local) assert.equal(color, '#008800');
        if (global) assert.equal(color, '#FF8800');
      }
    }
  };
  await checkFunctionColor();
  await runtime.restart(folder.uri);
  analysis.invalidate();
  await checkFunctionColor();

  // Unsaved changes retain earlier versions and replace only the edited binding.
  const redefinedSource = functionSource + `
let exampleFn = fn() -> i64 { return 2 }
set exampleFn.color = "#123456"
set exampleFn.docs = "ccc"
exampleFn()
`;
  const redefinedDoc = { ...document(redefinedSource), version: 2 };
  vscode.window.visibleTextEditors[0].document = redefinedDoc;
  const newRanges = [];
  for (const match of redefinedSource.matchAll(/\bexampleFn\b/g)) {
    const hover = await providers.registerHoverProvider.provideHover(redefinedDoc,
      redefinedDoc.positionAt(match.index + 1));
    const expected = match.index < localFunctionEnd ? 'aaa' : match.index < functionSource.length ? 'bbb' : 'ccc';
    assert.match(hover.contents.value, new RegExp(expected));
    for (const other of ['aaa', 'bbb', 'ccc'].filter(item => item !== expected))
      assert.ok(!hover.contents.value.includes(other));
    if (match.index >= functionSource.length) newRanges.push([match.index, match.index + 'exampleFn'.length]);
  }
  await analysis.refresh(redefinedDoc);
  const rendered = color => (colorRanges.get(color) || []).map(range =>
    [redefinedDoc.offsetAt(range.start), redefinedDoc.offsetAt(range.end)]).sort((a, b) => a[0] - b[0]);
  assert.deepEqual(rendered('#123456'), newRanges);
  assert.deepEqual(rendered('#FF8800'), expectedGlobalRanges);
  assert.deepEqual(rendered('#008800'), expectedFunctionRanges);
  const clearedDoc = { ...document(redefinedSource.replace('#123456', '')), version: 3 };
  vscode.window.visibleTextEditors[0].document = clearedDoc;
  await analysis.refresh(clearedDoc);
  assert.deepEqual(rendered('#123456'), []);
  assert.deepEqual(rendered('#FF8800'), expectedGlobalRanges);
  assert.deepEqual(rendered('#008800'), expectedFunctionRanges);
  console.log('Assistance passed: source-owned help, selectors, aliases, choices, cursor visibility, Unicode, signature, discovery and variable documentation hovers.');
})().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => { analysis.dispose(); runtime.dispose(); fs.rmSync(root, { recursive: true, force: true }); });
