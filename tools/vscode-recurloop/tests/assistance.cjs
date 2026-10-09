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
const uri = fsPath => ({ fsPath, toString: () => `file://${fsPath}` });
const folder = { uri: uri(root), name: 'help', index: 0 };
const vscode = { Position, Range, MarkdownString, SnippetString, CompletionItem, SignatureInformation, ParameterInformation, Hover,
  SignatureHelp: class {}, CancellationError, CompletionItemKind: { Text: 0, Keyword: 1, Snippet: 2, Value: 3, Module: 4, Class: 5 },
  commands: { registerCommand(name, callback) { commands[name] = callback; return disposable(); } },
  workspace: { workspaceFolders: [folder], textDocuments: [], getWorkspaceFolder: () => folder,
    getConfiguration: () => ({ get: (key, fallback) => key === 'executablePath' ? executable : key === 'terminal.libraries' ? [] : fallback }),
    onDidChangeTextDocument: disposable, onDidOpenTextDocument: disposable, onDidCloseTextDocument: disposable },
  window: { visibleTextEditors: [], onDidChangeVisibleTextEditors: disposable },
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
  console.log('Assistance passed: source-owned help, selectors, aliases, choices, cursor visibility, Unicode, signature and discovery.');
})().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => { analysis.dispose(); runtime.dispose(); fs.rmSync(root, { recursive: true, force: true }); });
