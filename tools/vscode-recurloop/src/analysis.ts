import * as vscode from 'vscode';
import { RecurLoopRuntime } from './runtime';
import { NavigationController } from './navigation';
import { assistanceItems, helpMarkdown, HelpFact, ArgumentFact, ExpectedFact, ValueFact } from './assistance';
import {
  codePointToUtf16Map,
  hexDecode,
  hasProject,
  positionFromCodePoint,
  stripAnsi,
  utf16OffsetToCodePoint
} from './util';

export interface SemanticSpan {
  start: number;
  end: number;
  group: number;
  color: string;
  kind: string;
  docs: string;
  owner: string;
}

export interface SymbolFact {
  version: number;
  name: string;
  kind: string;
  docs: string;
  prototype: string;
  type: string;
  signature: string;
}

export interface Occurrence {
  start: number;
  end: number;
  line: number;
  version: number;
  name: string;
}

export interface AnalysisResult {
  version: number;
  source: string;
  mapping: number[];
  spans: SemanticSpan[];
  symbols: SymbolFact[];
  occurrences: Occurrence[];
  help: HelpFact[];
  arguments: ArgumentFact[];
  expected: ExpectedFact[];
  values: ValueFact[];
  dictionary: string;
  completionStart?: number;
  diagnostic?: string;
}

function number(value: string): number {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function parseInspection(document: Pick<vscode.TextDocument, 'getText' | 'version'>, response: string): AnalysisResult {
  const spans: SemanticSpan[] = [];
  const symbols: SymbolFact[] = [];
  const occurrences: Occurrence[] = [];
  const help: HelpFact[] = [];
  const arguments_: ArgumentFact[] = [];
  const expected: ExpectedFact[] = [];
  const values: ValueFact[] = [];
  let dictionary = '';
  let completionStart: number | undefined;
  let diagnostic: string | undefined;

  for (const rawLine of response.split(/\r?\n/)) {
    if (!rawLine) continue;
    const fields = rawLine.split('\t');
    switch (fields[0]) {
      case 'H':
        if (fields.length >= 8) help.push({ version: number(fields[1]), name: hexDecode(fields[2]),
          pattern: hexDecode(fields[3]), snippet: hexDecode(fields[4]), example: hexDecode(fields[5]),
          summary: hexDecode(fields[6]), tags: hexDecode(fields[7]) });
        break;
      case 'J':
        if (fields.length >= 8) arguments_.push({ version: number(fields[1]), owner: hexDecode(fields[2]), name: hexDecode(fields[3]),
          docs: hexDecode(fields[4]), dictionary: hexDecode(fields[5]), kind: hexDecode(fields[6]), prototype: hexDecode(fields[7]) });
        break;
      case 'X':
        if (fields.length >= 7) expected.push({ version: number(fields[1]), owner: hexDecode(fields[2]), start: number(fields[3]),
          name: hexDecode(fields[4]), matcher: hexDecode(fields[5]), literal: hexDecode(fields[6]), insertion: hexDecode(fields[7] ?? fields[6]) });
        break;
      case 'D':
        dictionary = hexDecode(fields[1] ?? '');
        if (fields.length >= 3) completionStart = number(fields[2]);
        break;
      case 'V':
        if (fields.length >= 6) values.push({ version: number(fields[1]), owner: hexDecode(fields[2]), argument: hexDecode(fields[3]),
          name: hexDecode(fields[4]), spelling: hexDecode(fields[5]) });
        break;
      case 'S':
        if (fields.length >= 8) {
          spans.push({
            start: number(fields[1]),
            end: number(fields[2]),
            group: number(fields[3]),
            color: hexDecode(fields[4]),
            kind: hexDecode(fields[5]),
            docs: hexDecode(fields[6]),
            owner: hexDecode(fields[7])
          });
        }
        break;
      case 'E':
        diagnostic = hexDecode(fields[1] ?? '');
        break;
      case 'R':
        if (fields.length >= 6) {
          occurrences.push({
            start: number(fields[1]),
            end: number(fields[2]),
            line: number(fields[3]),
            version: number(fields[4]),
            name: hexDecode(fields[5])
          });
        }
        break;
      case 'P':
        if (fields.length >= 8) {
          symbols.push({
            version: number(fields[1]),
            name: hexDecode(fields[2]),
            kind: hexDecode(fields[3]),
            docs: hexDecode(fields[4]),
            prototype: hexDecode(fields[5]),
            type: hexDecode(fields[6]),
            signature: hexDecode(fields[7])
          });
        }
        break;
    }
  }

  const source = document.getText();
  return {
    version: document.version,
    source,
    mapping: codePointToUtf16Map(source),
    spans,
    symbols,
    occurrences,
    help, arguments: arguments_, expected, values, dictionary, completionStart,
    diagnostic
  };
}

function completionKind(kind: string): vscode.CompletionItemKind {
  switch (kind.toLowerCase()) {
    case 'function': return vscode.CompletionItemKind.Function;
    case 'method': return vscode.CompletionItemKind.Method;
    case 'type': return vscode.CompletionItemKind.Class;
    case 'keyword': return vscode.CompletionItemKind.Keyword;
    case 'literal': return vscode.CompletionItemKind.Value;
    case 'namespace':
    case 'dictionary': return vscode.CompletionItemKind.Module;
    case 'phrase field':
    case 'field': return vscode.CompletionItemKind.Field;
    case 'variable': return vscode.CompletionItemKind.Variable;
    default: return vscode.CompletionItemKind.Text;
  }
}

export class AnalysisController implements vscode.Disposable {
  private readonly diagnostics = vscode.languages.createDiagnosticCollection('recurloop');
  private readonly cache = new Map<string, AnalysisResult>();
  private readonly debounce = new Map<string, NodeJS.Timeout>();
  private readonly decorations = new Map<string, vscode.TextEditorDecorationType>();
  private readonly disposables: vscode.Disposable[] = [];

  constructor(
    private readonly runtime: RecurLoopRuntime,
    private readonly output: vscode.OutputChannel
  ) {
    const navigation = new NavigationController(runtime);
    const selector: vscode.DocumentSelector = { language: 'recurloop', scheme: 'file' };

    this.disposables.push(
      navigation,
      vscode.languages.registerWorkspaceSymbolProvider({ provideWorkspaceSymbols: (query, token) => navigation.workspaceSymbols(query, token) }),
      vscode.languages.registerHoverProvider(selector, { provideHover: (document, position, token) => this.hover(document, position, token) }),
      vscode.languages.registerCompletionItemProvider(selector, { provideCompletionItems: (document, position, token) => this.completions(document, position, token) }, ':', '.', ' '),
      vscode.languages.registerSignatureHelpProvider(selector, { provideSignatureHelp: (document, position, token) => this.signatureHelp(document, position, token) }, '(', ',', ' '),
      vscode.commands.registerCommand('recurloop.help', () => this.showHelp()),
      vscode.languages.registerDefinitionProvider(selector, { provideDefinition: (document, position, token) => navigation.locations(document, position, 'definition', true, token) }),
      vscode.languages.registerReferenceProvider(selector, { provideReferences: (document, position, context, token) => navigation.locations(document, position, 'references', context.includeDeclaration, token) }),
      vscode.languages.registerTypeDefinitionProvider(selector, { provideTypeDefinition: (document, position, token) => navigation.locations(document, position, 'type-definition', true, token) }),
      vscode.languages.registerImplementationProvider(selector, { provideImplementation: (document, position, token) => navigation.locations(document, position, 'implementations', true, token) }),
      vscode.languages.registerRenameProvider(selector, { provideRenameEdits: (document, position, name, token) => navigation.rename(document, position, name, token) }),
      vscode.languages.registerDocumentSymbolProvider(selector, { provideDocumentSymbols: (document, token) => navigation.symbols(document, token) }),
      vscode.workspace.onDidChangeTextDocument(event => {
        if (event.document.languageId === 'recurloop') this.schedule(event.document);
      }),
      vscode.workspace.onDidOpenTextDocument(document => {
        if (document.languageId === 'recurloop') this.schedule(document, 0);
      }),
      vscode.workspace.onDidCloseTextDocument(document => {
        for (const key of this.cache.keys()) if (key.startsWith(`${document.uri.toString()}#`)) this.cache.delete(key);
        this.diagnostics.delete(document.uri);
      }),
      vscode.window.onDidChangeVisibleTextEditors(editors => {
        for (const editor of editors) if (editor.document.languageId === 'recurloop') void this.refreshEditor(editor);
      })
    );

    for (const document of vscode.workspace.textDocuments) {
      if (document.languageId === 'recurloop') this.schedule(document, 0);
    }
  }

  public invalidate(): void {
    this.cache.clear();
    for (const document of vscode.workspace.textDocuments) {
      if (document.languageId === 'recurloop') this.schedule(document, 0);
    }
  }

  public async get(document: vscode.TextDocument, token?: vscode.CancellationToken): Promise<AnalysisResult> {
    if (token?.isCancellationRequested) throw new vscode.CancellationError();
    const enabled = vscode.workspace.getConfiguration('recurloop', document.uri).get('analysis.enabled', true) as boolean;
    const source = document.getText();
    const version = document.version;
    if (!enabled || !hasProject(document.uri)) {
      return parseInspection({ version, getText: () => source }, '');
    }
    const revision = this.runtime.revision(document.uri);
    const epoch = this.runtime.epoch(document.uri);
    const prefix = `${document.uri.toString()}#`;
    const key = `${prefix}${version}:${revision}`;
    const cached = this.cache.get(key);
    if (cached) return cached;
    const controller = new AbortController();
    const cancellation = token?.onCancellationRequested(() => controller.abort(new vscode.CancellationError()));
    try {
      const response = await this.runtime.inspect(document, true, controller.signal);
      if (document.version !== version || (this.runtime.epoch(document.uri) === epoch && this.runtime.revision(document.uri) !== revision)) throw new vscode.CancellationError();
      const result = this.cache.get(key) ?? parseInspection({ getText: () => source, version }, response);
      for (const oldKey of this.cache.keys()) if (oldKey.startsWith(prefix) && oldKey !== key) this.cache.delete(oldKey);
      this.cache.set(`${prefix}${version}:${this.runtime.revision(document.uri)}`, result);
      return result;
    } finally { cancellation?.dispose(); }
  }

  private schedule(document: vscode.TextDocument, explicitDelay?: number): void {
    const key = document.uri.toString();
    const existing = this.debounce.get(key);
    if (existing) clearTimeout(existing);
    const delay = explicitDelay ?? vscode.workspace.getConfiguration('recurloop', document.uri).get('analysis.debounceMs', 180) as number;
    const timer = setTimeout(() => {
      this.debounce.delete(key);
      void this.refresh(document);
    }, delay);
    this.debounce.set(key, timer);
  }

  private async refresh(document: vscode.TextDocument): Promise<void> {
    try {
      const result = await this.get(document);
      if (document.version !== result.version) return;
      this.publishDiagnostic(document, result);
      for (const editor of vscode.window.visibleTextEditors) {
        if (editor.document.uri.toString() === document.uri.toString()) this.applyColors(editor, result);
      }
    } catch (error) {
      if (error instanceof vscode.CancellationError || !hasProject(document.uri)) return;
      const message = error instanceof Error ? error.message : String(error);
      this.output.appendLine(`[analysis] ${document.uri.fsPath}: ${message}`);
      this.diagnostics.set(document.uri, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), message, vscode.DiagnosticSeverity.Warning)]);
    }
  }

  private async refreshEditor(editor: vscode.TextEditor): Promise<void> {
    try {
      const result = await this.get(editor.document);
      if (editor.document.version === result.version) this.applyColors(editor, result);
    } catch {
      // Diagnostic refresh reports the actual error.
    }
  }

  private publishDiagnostic(document: vscode.TextDocument, result: AnalysisResult): void {
    if (!result.diagnostic) {
      this.diagnostics.delete(document.uri);
      return;
    }
    const text = stripAnsi(result.diagnostic).trim();
    const location = text.match(/(?:^|\n)(.*?):(\d+):(\d+):\s*(.*)/s);
    let range = new vscode.Range(0, 0, 0, Math.min(1, document.lineAt(0).text.length));
    let message = text;
    if (location) {
      const line = Math.max(0, Number.parseInt(location[2], 10) - 1);
      const column = Math.max(0, Number.parseInt(location[3], 10) - 1);
      if (line < document.lineCount) {
        const end = Math.min(document.lineAt(line).text.length, column + 1);
        range = new vscode.Range(line, Math.min(column, end), line, end);
      }
      message = location[4].trim() || text;
    }
    this.diagnostics.set(document.uri, [new vscode.Diagnostic(range, message, vscode.DiagnosticSeverity.Error)]);
  }

  private applyColors(editor: vscode.TextEditor, result: AnalysisResult): void {
    const groups = new Map<string, vscode.Range[]>();
    for (const span of result.spans) {
      const color = span.color.trim();
      if (!/^#[0-9A-Fa-f]{6}$/.test(color) || span.end <= span.start) continue;
      const ranges = groups.get(color) ?? [];
      ranges.push(new vscode.Range(
        positionFromCodePoint(editor.document, result.mapping, span.start),
        positionFromCodePoint(editor.document, result.mapping, span.end)
      ));
      groups.set(color, ranges);
    }
    for (const [color, decoration] of this.decorations) editor.setDecorations(decoration, groups.get(color) ?? []);
    for (const [color, ranges] of groups) {
      let decoration = this.decorations.get(color);
      if (!decoration) {
        decoration = vscode.window.createTextEditorDecorationType({ color });
        this.decorations.set(color, decoration);
      }
      editor.setDecorations(decoration, ranges);
    }
  }

  private async hover(document: vscode.TextDocument, position: vscode.Position, token?: vscode.CancellationToken): Promise<vscode.Hover | undefined> {
    const result = await this.get(document, token);
    const offset = utf16OffsetToCodePoint(result.source, document.offsetAt(position));
    const occurrence = result.occurrences
      .filter(item => item.start <= offset && offset <= item.end)
      .sort((a, b) => (a.end - a.start) - (b.end - b.start))[0];
    const span = result.spans
      .filter(item => item.start <= offset && offset <= item.end && item.docs)
      .sort((a, b) => (a.end - a.start) - (b.end - b.start))[0];
    const fact = occurrence
      ? result.symbols.find(item => item.name === occurrence.name && item.version === occurrence.version) ?? result.symbols.find(item => item.name === occurrence.name)
      : undefined;
    if (!fact && !span) return undefined;

    let markdown = new vscode.MarkdownString(undefined, true);
    markdown.isTrusted = false;
    if (fact) {
      const contract = result.help.find(item => item.version === fact.version && item.name === fact.name);
      if (contract) {
        markdown = helpMarkdown(contract, fact.docs || span?.docs);
      } else {
        markdown.appendCodeblock(fact.signature || fact.name, 'recurloop');
        const metadata = [fact.kind, fact.type ? `type: ${fact.type}` : '', fact.prototype ? `prototype: ${fact.prototype}` : ''].filter(Boolean);
        if (metadata.length) markdown.appendMarkdown(`*${metadata.join(' · ')}*\n\n`);
        const docs = fact.docs || span?.docs;
        if (docs) markdown.appendMarkdown(docs);
      }
    } else if (span) {
      if (span.kind) markdown.appendMarkdown(`*${span.kind}*\n\n`);
      markdown.appendMarkdown(span.docs);
    }
    const range = occurrence
      ? new vscode.Range(positionFromCodePoint(document, result.mapping, occurrence.start), positionFromCodePoint(document, result.mapping, occurrence.end))
      : undefined;
    return new vscode.Hover(markdown, range);
  }

  private async atCursor(document: vscode.TextDocument, position: vscode.Position, token?: vscode.CancellationToken): Promise<AnalysisResult> {
    if (token?.isCancellationRequested) throw new vscode.CancellationError();
    const version = document.version;
    const source = document.getText().slice(0, document.offsetAt(position));
    if (!hasProject(document.uri) || !vscode.workspace.getConfiguration('recurloop', document.uri).get('analysis.enabled', true))
      return parseInspection({ version, getText: () => source }, '');
    const controller = new AbortController();
    const cancellation = token?.onCancellationRequested(() => controller.abort(new vscode.CancellationError()));
    try {
      const snapshot = { uri: document.uri, version, getText: () => source } as vscode.TextDocument;
      const response = await this.runtime.inspect(snapshot, true, controller.signal);
      if (document.version !== version) throw new vscode.CancellationError();
      return parseInspection(snapshot, response);
    } finally { cancellation?.dispose(); }
  }

  private async completions(document: vscode.TextDocument, position: vscode.Position, token?: vscode.CancellationToken): Promise<vscode.CompletionItem[]> {
    return assistanceItems(document, await this.atCursor(document, position, token), completionKind);
  }

  private async showHelp(): Promise<void> {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'recurloop') return;
    const result = await this.atCursor(editor.document, editor.selection.active);
    const entries = result.help.filter(item => item.summary || item.example || item.snippet)
      .sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)
      .map(contract => ({ label: contract.name, description: contract.summary, detail: contract.tags, contract }));
    const selected = await vscode.window.showQuickPick(entries, { placeHolder: 'Find a phrase by name, purpose or tags', matchOnDescription: true, matchOnDetail: true });
    if (!selected || editor.document.version !== result.version) return;
    const snippet = selected.contract.snippet;
    if (snippet) await editor.insertSnippet(new vscode.SnippetString(snippet.replaceAll('${phrase}', selected.contract.name)));
    else {
      const panel = vscode.window.createWebviewPanel('recurloop.help', selected.label, vscode.ViewColumn.Beside, {});
      const escape = (text: string) => text.replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]!));
      panel.webview.html = `<meta http-equiv="Content-Security-Policy" content="default-src 'none';"><h2>${escape(selected.label)}</h2><p>${escape(selected.description)}</p><pre>${escape(selected.contract.example || selected.contract.pattern)}</pre>`;
    }
  }

  private async signatureHelp(document: vscode.TextDocument, position: vscode.Position, token?: vscode.CancellationToken): Promise<vscode.SignatureHelp | undefined> {
    const result = await this.atCursor(document, position, token);
    if (result.expected.length) {
      const signatures = new Map<string, vscode.SignatureInformation>();
      for (const expected of result.expected) {
        if (!expected.literal && !expected.matcher) continue;
        const contract = result.help.find(item => item.version === expected.version && item.name === expected.owner);
        if (!contract) continue;
        const label = `${expected.owner} ${contract.pattern}`;
        const info = new vscode.SignatureInformation(label, helpMarkdown(contract));
        const argument = result.arguments.find(item => item.owner === expected.owner && item.version === expected.version && item.name === expected.name);
        const capture = `<${expected.name}:${expected.matcher}>`;
        const start = label.indexOf(capture);
        if (start >= 0) info.parameters = [new vscode.ParameterInformation([start, start + capture.length], argument?.docs)];
        signatures.set(label, info);
      }
      if (signatures.size) {
        const help = new vscode.SignatureHelp();
        help.activeParameter = 0; help.activeSignature = 0; help.signatures = [...signatures.values()];
        return help;
      }
    }
    const linePrefix = document.lineAt(position.line).text.slice(0, position.character);
    const match = linePrefix.match(/([A-Za-z_][A-Za-z0-9_:]*)\s*\(([^()]*)$/);
    if (!match) return undefined;
    const name = match[1];
    const activeParameter = match[2].trim() ? match[2].split(',').length - 1 : 0;
    const qualified = result.dictionary ? `${result.dictionary}:${name}` : name;
    const symbol = result.symbols.find(item => item.name === qualified) ?? result.symbols.find(item => item.name === name);
    if (!symbol?.signature) return undefined;
    const help = new vscode.SignatureHelp();
    help.activeParameter = activeParameter;
    help.activeSignature = 0;
    help.signatures = symbol.signature.split('\n').filter(Boolean).map(signature => {
      const info = new vscode.SignatureInformation(signature, symbol.docs ? new vscode.MarkdownString(symbol.docs) : undefined);
      const params = signature.match(/\((.*)\)/)?.[1] ?? '';
      if (params && params !== '...') info.parameters = params.split(',').map(value => new vscode.ParameterInformation(value.trim()));
      return info;
    });
    return help;
  }

  public dispose(): void {
    for (const timer of this.debounce.values()) clearTimeout(timer);
    for (const decoration of this.decorations.values()) decoration.dispose();
    for (const disposable of this.disposables) disposable.dispose();
    this.diagnostics.dispose();
  }
}
