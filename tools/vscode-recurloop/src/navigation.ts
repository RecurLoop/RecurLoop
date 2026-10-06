import * as fs from 'fs';
import { createHash } from 'crypto';
import * as vscode from 'vscode';
import { RecurLoopRuntime } from './runtime';
import { RuntimeConnection } from './transport';
import { codePointToUtf16Map, hasProject, hexDecode, hexEncode, positionFromCodePoint, rlString, resolveLibraryImage, utf16OffsetToCodePoint, workspaceRoot, projectFile } from './util';

interface Match { location: vscode.Location; label: string; role: number; kind: string; signature: string }

interface IndexedFile {
  document: vscode.TextDocument;
  version: number;
  source: string;
  fingerprint: string;
  revision: number;
  mapping: number[];
  catalog: Map<string, { kind: string; signature: string }>;
}
interface ProjectIndex {
  queue: Promise<unknown>;
  connection?: RuntimeConnection;
  files: Map<string, IndexedFile>;
  revision: number;
  epoch: number;
  dependencies?: string[];
}

/** LanguageKit owns classification and queries; the client synchronizes snapshots. */
export class NavigationController implements vscode.Disposable {
  private readonly controllers = new Set<AbortController>();
  private disposed = false;
  private readonly projects = new Map<string, ProjectIndex>();
  constructor(private readonly runtime: RecurLoopRuntime) {}

  async query(document: vscode.TextDocument, position: vscode.Position, operation: string, argument = '', token?: vscode.CancellationToken): Promise<Match[]> {
    if (this.disposed || !hasProject(document.uri)) return [];
    const controller = new AbortController();
    this.controllers.add(controller);
    const cancellation = token?.onCancellationRequested(() => controller.abort(new vscode.CancellationError()));
    if (token?.isCancellationRequested) controller.abort(new vscode.CancellationError());
    const signal = controller.signal;
    const root = workspaceRoot(document.uri);
    let project = this.projects.get(root);
    if (!project) {
      project = { queue: Promise.resolve(), files: new Map(), revision: -1, epoch: -1 };
      this.projects.set(root, project);
    }
    const index = project;
    const task = index.queue.then(async () => {
      signal.throwIfAborted();
      try { return await this.run(index, document, position, operation, argument, signal); }
      catch (error) {
        index.connection?.close(); index.connection = undefined;
        index.files.clear(); index.dependencies = undefined;
        throw error;
      }
    });
    index.queue = task.catch(() => undefined);
    // A queued cancellation returns immediately without interrupting another caller.
    try {
      return await new Promise<Match[]>((resolve, reject) => {
        const abort = () => reject(signal.reason);
        signal.addEventListener('abort', abort, { once: true });
        task.then(resolve, reject).finally(() => signal.removeEventListener('abort', abort));
        if (signal.aborted) abort();
      });
    } finally { cancellation?.dispose(); this.controllers.delete(controller); }
  }

  private async run(index: ProjectIndex, document: vscode.TextDocument, position: vscode.Position,
    operation: string, argument: string, signal: AbortSignal): Promise<Match[]> {
    const uri = document.uri;
    const version = document.version;
    if (index.epoch !== this.runtime.epoch(uri)) {
      index.connection?.close(); index.connection = undefined; index.files.clear(); index.dependencies = undefined;
    }
    if (!index.connection) {
      const trace = await this.runtime.inspect(document, true, signal);
      index.connection = await this.runtime.openAnalysis(uri);
      index.epoch = this.runtime.epoch(uri);
      // Use project policy when available; a core-only project needs a LanguageKit session.
      if (!trace.includes(hexEncode('languagekit_analysis_request'))) {
        await index.connection.request([':baseline', `engine import ${rlString(resolveLibraryImage(uri, 'language-kit'))}`], 120000, signal);
      }
    }
    const connection = index.connection;
    const timeout = vscode.workspace.getConfiguration('recurloop', uri).get('analysis.timeoutMs', 5000) as number;
    const request = (fields: string[]) => connection.request([`recurloop languagekit_analysis_request\t${fields.join('\t')}`], timeout, signal);
    const revision = this.runtime.revision(uri);
    const participating = new Map<string, IndexedFile>();
    const synchronize = async (doc: vscode.TextDocument) => {
      signal.throwIfAborted();
      const source = doc.getText();
      const docVersion = doc.version;
      const old = index.files.get(doc.uri.fsPath);
      if (old?.source === source && old.revision === revision) {
        old.document = doc; old.version = docVersion; participating.set(doc.uri.fsPath, old);
        return;
      }
      const response = await this.runtime.inspect(doc, true, signal, uri);
      const trace = response.split(/\r?\n/).filter(line => /^[PRE]\t/.test(line)).join('\n');
      const fingerprint = createHash('sha256').update(trace).digest('hex');
      signal.throwIfAborted();
      if (this.runtime.revision(uri) !== revision || doc.version !== docVersion || doc.getText() !== source) throw new vscode.CancellationError();
      if (old?.source === source && old.fingerprint === fingerprint) {
        old.document = doc; old.version = docVersion; old.revision = revision;
        participating.set(doc.uri.fsPath, old);
        return;
      }
      await request(['update', hexEncode(doc.uri.fsPath), hexEncode(source), hexEncode(trace)]);
      const catalog = new Map<string, { kind: string; signature: string }>();
      for (const line of trace.split('\n')) {
        const fields = line.split('\t');
        if (fields[0] === 'P' && fields.length >= 8) catalog.set(hexDecode(fields[2]), { kind: hexDecode(fields[3]), signature: hexDecode(fields[7]) });
      }
      const file = { document: doc, version: docVersion, source, fingerprint, revision, catalog, mapping: codePointToUtf16Map(source) };
      index.files.set(doc.uri.fsPath, file); participating.set(doc.uri.fsPath, file);
    };
    await synchronize(document);
    if (index.revision !== revision) { index.dependencies = undefined; index.revision = revision; }
    const cursor = utf16OffsetToCodePoint(document.getText(), document.offsetAt(position));
    const query = (name: string, value = argument) => request(['query', hexEncode(uri.fsPath), hexEncode(name), String(cursor), hexEncode(value)]);
    if (operation !== 'document-symbols') {
      const scope = await query('scope', operation);
      if (scope.includes('Q\tnone') && operation !== 'workspace-symbols') {
        if (operation === 'rename') throw new Error('No unambiguous semantic definition at the cursor.');
        return [];
      }
      if (!scope.includes('Q\tlocal') || operation === 'workspace-symbols') {
        if (!index.dependencies) index.dependencies = (await this.runtime.execute(uri, [':cache-dependencies'], signal))
          .split(/\r?\n/).filter(file => file.endsWith('.rl') && fs.existsSync(file));
        const sources = new Set([...index.dependencies, uri.fsPath]);
        for (const file of index.files.keys()) if (!sources.has(file)) {
          await request(['remove', hexEncode(file)]); index.files.delete(file);
        }
        const open = new Map(vscode.workspace.textDocuments.map(doc => [doc.uri.fsPath, doc]));
        for (const file of sources) {
          signal.throwIfAborted();
          if (file === uri.fsPath) continue;
          const doc = open.get(file) ?? await vscode.workspace.openTextDocument(vscode.Uri.file(file));
          await synchronize(doc);
        }
      }
    }
    const response = await query(operation);
    signal.throwIfAborted();
    if (document.version !== version || this.runtime.revision(uri) !== revision) throw new vscode.CancellationError();
    for (const file of participating.values()) if (file.document.version !== file.version) throw new vscode.CancellationError();
    const result: Match[] = [];
    for (const line of response.split(/\r?\n/)) {
      const fields = line.split('\t');
      if (fields[0] === 'E') {
        if (operation === 'rename') throw new Error(hexDecode(fields[1] ?? ''));
        continue;
      }
      if (fields[0] !== 'L' || fields.length < 7) continue;
      const file = index.files.get(hexDecode(fields[1]));
      if (!file) continue;
      const label = hexDecode(fields[6]);
      const fact = file.catalog.get(label);
      result.push({ location: new vscode.Location(file.document.uri, new vscode.Range(
        positionFromCodePoint(file.document, file.mapping, Number(fields[2])),
        positionFromCodePoint(file.document, file.mapping, Number(fields[3])))),
        role: Number(fields[5]), label, kind: fact?.kind ?? '', signature: fact?.signature ?? '' });
    }
    return result;
  }

  async locations(document: vscode.TextDocument, position: vscode.Position, operation: string, declarations = true, token?: vscode.CancellationToken): Promise<vscode.Location[]> {
    return (await this.query(document, position, operation, '', token)).filter(match => declarations || match.role !== 2).map(match => match.location);
  }

  async symbols(document: vscode.TextDocument, token?: vscode.CancellationToken): Promise<vscode.DocumentSymbol[]> {
    return (await this.query(document, new vscode.Position(0, 0), 'document-symbols', '', token)).map(match =>
      new vscode.DocumentSymbol(match.label, match.signature, symbolKind(match.kind), match.location.range, match.location.range));
  }

  async workspaceSymbols(query: string, token?: vscode.CancellationToken): Promise<vscode.SymbolInformation[]> {
    const result: vscode.SymbolInformation[] = [];
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
      if (token?.isCancellationRequested) throw new vscode.CancellationError();
      if (!hasProject(folder.uri)) continue;
      const document = await vscode.workspace.openTextDocument(vscode.Uri.file(projectFile(folder.uri)));
      for (const match of await this.query(document, new vscode.Position(0, 0), 'workspace-symbols', query, token)) {
        result.push(new vscode.SymbolInformation(match.label, symbolKind(match.kind), '', match.location));
      }
    }
    return result;
  }

  async rename(document: vscode.TextDocument, position: vscode.Position, name: string, token?: vscode.CancellationToken): Promise<vscode.WorkspaceEdit> {
    const matches = await this.query(document, position, 'rename', name, token);
    if (!matches.length) throw new Error('No unambiguous semantic definition at the cursor.');
    const edit = new vscode.WorkspaceEdit();
    for (const match of matches) edit.replace(match.location.uri, match.location.range, name);
    return edit;
  }

  dispose(): void {
    this.disposed = true;
    for (const controller of this.controllers) controller.abort(new vscode.CancellationError());
    this.controllers.clear();
    for (const index of this.projects.values()) index.connection?.close();
    this.projects.clear();
  }
}

function symbolKind(kind: string): vscode.SymbolKind {
  switch (kind.toLowerCase()) {
    case 'function': return vscode.SymbolKind.Function;
    case 'type': return vscode.SymbolKind.Class;
    case 'dictionary': return vscode.SymbolKind.Namespace;
    case 'field':
    case 'phrase field': return vscode.SymbolKind.Field;
    default: return vscode.SymbolKind.Variable;
  }
}
