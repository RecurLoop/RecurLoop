// Real runtime and persisted module cache; VS Code rendering is captured at its API boundary.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const repo = path.resolve(__dirname, '../../..');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-highlighting-'));
process.env.RECURLOOP_LIBRARY_PATH = process.env.RECURLOOP_TEST_LIBRARIES || path.join(repo, 'build/Release/libraries');
const executable = process.env.RECURLOOP_TEST_PROGRAM || path.join(repo, 'build/Release/bin/recurloop');
const uri = fsPath => ({ fsPath, toString: () => `file://${fsPath}` });
const folder = { uri: uri(root), name: 'highlighting', index: 0 };
const disposable = () => ({ dispose() {} });
class Position { constructor(line, character) { Object.assign(this, { line, character }); } }
class Range {
  constructor(start, end, endLine, endCharacter) {
    this.start = typeof start === 'number' ? new Position(start, end) : start;
    this.end = typeof start === 'number' ? new Position(endLine, endCharacter) : end;
  }
}
class CancellationError extends Error {}
let enabled = true;
const colors = new Map();
const vscode = { Position, Range, CancellationError, Diagnostic: class {}, DiagnosticSeverity: { Error: 0, Warning: 1 },
  commands: { registerCommand: disposable },
  workspace: { workspaceFolders: [folder], textDocuments: [], getWorkspaceFolder: () => folder,
    getConfiguration: () => ({ get: (key, fallback) => key === 'executablePath' ? executable
      : key === 'terminal.libraries' ? ['shell', 'inferred'] : key === 'analysis.enabled' ? enabled : fallback }),
    onDidChangeTextDocument: disposable, onDidOpenTextDocument: disposable, onDidCloseTextDocument: disposable },
  window: { visibleTextEditors: [], onDidChangeVisibleTextEditors: disposable,
    createTextEditorDecorationType: ({ color }) => ({ color, dispose() { colors.delete(color); } }) },
  languages: new Proxy({ createDiagnosticCollection: () => ({ ...disposable(), set() {}, delete() {} }) }, {
    get: (target, key) => target[key] || disposable
  })
};
const original = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : original.call(this, name, ...rest); };
const { RecurLoopRuntime } = require('../out/runtime');
const { AnalysisController } = require('../out/analysis');
const log = [];
const output = { appendLine: text => log.push(text), append: text => log.push(text) };
const runtime = new RecurLoopRuntime(output);
const analysis = new AnalysisController(runtime, output);
const source = `include "probe.rl"

link shared "c"
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

let Probe:main = fn () -> i64 {
    var distance:i64 = 0
    var tick:i64 = 1
    var value:i64 = 2
    value = described_query(value)
    while tick <= 3 {
        distance = Probe:advance(distance, 10)
        printf("Tick %lld: %lld km\\n", tick, distance)
        tick += 1
    }
    return 0
}
` + '// π 😀 ' + 'padding '.repeat(1100) + '\n';
const lines = source.split('\n');
const document = { uri: uri(path.join(root, 'main.rl')), languageId: 'recurloop', version: 1,
  getText: () => source, lineCount: lines.length, lineAt: line => ({ text: lines[line] }),
  positionAt: offset => { const prefix = source.slice(0, offset).split('\n'); return new Position(prefix.length - 1, prefix.at(-1).length); } };
const editor = { document, setDecorations: (decoration, ranges) => colors.set(decoration.color, ranges) };
vscode.window.visibleTextEditors = [editor];
const plain = () => assert.ok([...colors.values()].every(ranges => ranges.length === 0));
const palette = () => [...colors].flatMap(([color, ranges]) => ranges.map(range => [
  range.start.line, range.start.character, range.end.line, range.end.character, color
])).sort();
const assertLet = () => {
  const letColors = [...colors].filter(([, ranges]) => ranges.some(range =>
    range.start.line === 5 && range.start.character <= 0 && range.end.line === 5 && range.end.character >= 3
  )).map(([color]) => color);
  assert.deepEqual(letColors, ['#569CD6']);
};
(async () => {
  const manifest = require('../package.json');
  assert.equal(manifest.contributes.grammars, undefined);
  // A loose file never starts analysis or receives guessed keyword colors.
  await analysis.refresh(document);
  plain();
  assert.equal(log.length, 0);
  fs.writeFileSync(document.uri.fsPath, source);
  fs.writeFileSync(path.join(root, 'probe.rl'), `let Probe = phrase { dictionary = true permanent = true }
let value = phrase { docs = "A root phrase unrelated to the local parameter." }
extern described_query(value:i64) -> i64 abi sysv-amd64
set described_query.docs = "An external function with documentation and no explicit color."
let Probe:advance = fn (distance:i64, speed:i64) -> i64 { return distance + speed }
`);
  const entry = path.join(root, 'recurloop.project.rl');
  fs.writeFileSync(entry, 'include "main.rl"\n');
  // The host's palette must render even while complete semantic inspection is
  // delayed, including files larger than the former console-only 8 KiB limit.
  const inspect = runtime.inspect.bind(runtime);
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  runtime.inspect = async (...args) => { await gate; return inspect(...args); };
  let painted;
  const firstPaint = new Promise(resolve => { painted = resolve; });
  const setDecorations = editor.setDecorations;
  editor.setDecorations = (...args) => { setDecorations(...args); if (args[1].length) painted(); };
  const refresh = analysis.refresh(document);
  try {
    await Promise.race([firstPaint, new Promise((_, reject) => {
      const timer = setTimeout(() => reject(new Error('Palette waited for semantic inspection')), 10000);
      timer.unref();
    })]);
    assertLet();
  } finally {
    release(); runtime.inspect = inspect; editor.setDecorations = setDecorations;
  }
  await refresh;
  assertLet();
  const first = palette();
  assert.ok(first.length > 0);
  const assertWord = (word, color) => {
    const offset = source.indexOf(word, source.indexOf('let Probe:main'));
    const position = document.positionAt(offset);
    assert.ok(colors.get(color)?.some(range => range.start.line === position.line && range.end.line === position.line
      && range.start.character <= position.character && range.end.character >= position.character + word.length), word);
  };
  assertWord('value', '#9CDCFE');
  assertWord('described_query', '#DCDCAA');
  // Both the editor result cache and module images must preserve the colors.
  await analysis.refresh(document);
  assert.deepEqual(palette(), first);
  await runtime.restart(folder.uri);
  await analysis.refresh(document);
  assertLet();
  assert.deepEqual(palette(), first);
  enabled = false;
  await analysis.refresh(document);
  plain();
  enabled = true;
  await analysis.refresh(document);
  assertLet();
  fs.unlinkSync(entry);
  await analysis.refresh(document);
  plain();
  console.log('Highlighting passed: plain loose files, runtime let colors, editor cache, persisted module cache, disabled analysis and removed project.');
})().catch(error => { console.error(error, log.join('\n')); process.exitCode = 1; })
  .finally(() => { analysis.dispose(); runtime.dispose(); fs.rmSync(root, { recursive: true, force: true }); });
