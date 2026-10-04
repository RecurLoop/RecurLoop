import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { RecurLoopRuntime } from './runtime';
import { codePointToUtf16Map, hexDecode, positionFromCodePoint, rlString, resolveLibraryImage, utf16OffsetToCodePoint } from './util';

interface Match { location: vscode.Location; label: string; role: number; kind: string; signature: string }

/** Classification and symbol identity belong to LanguageKit on the project server. */
export class NavigationController {
  constructor(private readonly runtime: RecurLoopRuntime) {}

  async query(document: vscode.TextDocument, position: vscode.Position, operation: string, argument = ''): Promise<Match[]> {
    const sources = (await this.runtime.execute(document.uri, [':cache-dependencies']))
      .split(/\r?\n/).filter(file => file.endsWith('.rl') && fs.existsSync(file));
    if (!sources.includes(document.uri.fsPath)) sources.push(document.uri.fsPath);
    const documents: vscode.TextDocument[] = [];
    const files: string[] = [];
    const catalogs = new Map<string, Map<string, { kind: string; signature: string }>>();
    let hasAnalyzer = false;
    const versions = new Map<vscode.TextDocument, number>();
    for (const file of sources) {
      const doc = vscode.workspace.textDocuments.find(doc => doc.uri.fsPath === file)
        ?? await vscode.workspace.openTextDocument(vscode.Uri.file(file));
      documents.push(doc);
      versions.set(doc, doc.version);
      const trace = await this.runtime.inspect(doc, true);
      const catalog = new Map<string, { kind: string; signature: string }>();
      for (const line of trace.split('\n')) {
        const fields = line.split('\t');
        if (fields[0] === 'P' && fields.length >= 8) catalog.set(hexDecode(fields[2]), { kind: hexDecode(fields[3]), signature: hexDecode(fields[7]) });
      }
      catalogs.set(file, catalog);
      if (trace.includes(Buffer.from('LanguageKit:Analysis:query_index').toString('hex'))) hasAnalyzer = true;
      files.push(`let file_${files.length} = LanguageKit:Analysis:file(index, ${rlString(file)}, ${rlString(doc.getText())}, ${rlString(trace)})`);
    }
    const current = documents.findIndex(doc => doc.uri.fsPath === document.uri.fsPath);
    const cursor = utf16OffsetToCodePoint(document.getText(), document.offsetAt(position));
    // This file is evaluated in a private session; heap addresses never enter a published image.
    const source = `let __vscode_navigation = phrase {
      type = <phrase-types:elaborate>
      action = fn (state:Context*, called:Phrase*) -> void {
        let index = alloc(LanguageKit:Analysis:Index)
        if !index { return }
        index.files = cast(LanguageKit:Analysis:File*, 0)
        defer LanguageKit:Analysis:destroy(index)
        ${files.join('\n')}
        let result = LanguageKit:Analysis:query_index(index, file_${current}, ${rlString(operation)}, ${cursor}, ${rlString(argument)})
        if result { context:io:write(state, result); free(result) }
      }
    }
    __vscode_navigation\n`;
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-navigation-'));
    const driver = path.join(dir, 'query.rl');
    fs.writeFileSync(driver, source);
    let response: string;
    try { response = await this.runtime.execute(document.uri, [
      ...(hasAnalyzer ? [] : [':baseline', `engine import ${rlString(resolveLibraryImage(document.uri, 'language-kit'))}`]),
      `include ${rlString(driver)}`]); }
    finally { fs.rmSync(dir, { recursive: true, force: true }); }
    for (const [doc, version] of versions) if (doc.version !== version) throw new Error('Source changed during navigation; repeat the operation.');
    const result: Match[] = [];
    for (const line of response.split(/\r?\n/)) {
      const fields = line.split('\t');
      if (fields[0] === 'E') {
        const error = hexDecode(fields[1] ?? '');
        if (operation === 'rename') throw new Error(error);
        continue;
      }
      if (fields[0] !== 'L' || fields.length < 7) continue;
      const file = hexDecode(fields[1]);
      const doc = documents.find(doc => doc.uri.fsPath === file);
      if (!doc) continue;
      const mapping = codePointToUtf16Map(doc.getText());
      result.push({ location: new vscode.Location(doc.uri, new vscode.Range(
        positionFromCodePoint(doc, mapping, Number(fields[2])),
        positionFromCodePoint(doc, mapping, Number(fields[3])))),
        role: Number(fields[5]), label: hexDecode(fields[6]),
        kind: catalogs.get(file)?.get(hexDecode(fields[6]))?.kind ?? '',
        signature: catalogs.get(file)?.get(hexDecode(fields[6]))?.signature ?? '' });
    }
    return result;
  }

  async locations(document: vscode.TextDocument, position: vscode.Position, operation: string, declarations = true): Promise<vscode.Location[]> {
    return (await this.query(document, position, operation)).filter(match => declarations || match.role !== 2).map(match => match.location);
  }

  async symbols(document: vscode.TextDocument): Promise<vscode.DocumentSymbol[]> {
    return (await this.query(document, new vscode.Position(0, 0), 'document-symbols')).map(match =>
      new vscode.DocumentSymbol(match.label, match.signature, symbolKind(match.kind), match.location.range, match.location.range));
  }

  async rename(document: vscode.TextDocument, position: vscode.Position, name: string): Promise<vscode.WorkspaceEdit> {
    const matches = await this.query(document, position, 'rename', name);
    if (!matches.length) throw new Error('No unambiguous semantic definition at the cursor.');
    const edit = new vscode.WorkspaceEdit();
    for (const match of matches) edit.replace(match.location.uri, match.location.range, name);
    return edit;
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
