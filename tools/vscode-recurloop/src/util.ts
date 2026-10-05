import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

export function workspaceFolderFor(uri?: vscode.Uri): vscode.WorkspaceFolder | undefined {
  if (uri) {
    const folder = vscode.workspace.getWorkspaceFolder(uri);
    if (folder) return folder;
  }
  return vscode.workspace.workspaceFolders?.[0];
}

export function workspaceRoot(uri?: vscode.Uri): string {
  return workspaceFolderFor(uri)?.uri.fsPath ?? process.cwd();
}

export function projectFile(uri: vscode.Uri): string {
  const name = vscode.workspace.getConfiguration('recurloop', uri).get('projectFile', 'recurloop.project.rl');
  return path.resolve(workspaceRoot(uri), name);
}

/** A saved project entry explicitly opts a workspace folder into execution. */
export function hasProject(uri?: vscode.Uri): boolean {
  const folder = uri ? vscode.workspace.getWorkspaceFolder(uri) : vscode.workspace.workspaceFolders?.[0];
  if (!folder || (uri && uri.scheme !== undefined && uri.scheme !== 'file')) return false;
  try { return fs.statSync(projectFile(folder.uri)).isFile(); } catch { return false; }
}

export function requireProject(uri?: vscode.Uri): void {
  if (!hasProject(uri)) throw new Error('RecurLoop requires a saved project entry in this workspace. Use RecurLoop: Initialize Project or create the file configured by recurloop.projectFile (default: recurloop.project.rl).');
}

export function expandWorkspaceVariables(value: string, uri?: vscode.Uri): string {
  const root = workspaceRoot(uri);
  return value
    .replaceAll('${workspaceFolder}', root)
    .replaceAll('${workspaceFolderBasename}', path.basename(root))
    .replaceAll('${file}', uri?.fsPath ?? '')
    .replaceAll('${fileDirname}', uri ? path.dirname(uri.fsPath) : root)
    .replaceAll('${fileBasename}', uri ? path.basename(uri.fsPath) : '')
    .replaceAll('${fileBasenameNoExtension}', uri ? path.parse(uri.fsPath).name : '');
}

export function configuredExecutable(uri?: vscode.Uri, override?: string): string {
  if (override?.trim()) return expandWorkspaceVariables(override.trim(), uri);
  const configured = vscode.workspace.getConfiguration('recurloop', uri).get('executablePath') as string | undefined;
  const setting = configured?.trim();
  if (setting) return expandWorkspaceVariables(setting, uri);
  return 'recurloop';
}

let managedExecutable: string | undefined;

export function setManagedExecutable(executable?: string): void {
  managedExecutable = executable;
}

/** Locate a regular executable, resolving relative paths against the workspace. */
export function findExecutable(executable: string, uri?: vscode.Uri): string | undefined {
  const hasPath = path.isAbsolute(executable) || executable.includes('/') || executable.includes(path.sep);
  const candidates = hasPath ? [path.resolve(workspaceRoot(uri), executable)]
    : (process.env.PATH ?? '').split(path.delimiter).filter(Boolean).map(directory => path.resolve(directory, executable));
  for (const candidate of candidates) {
    try {
      if (!fs.statSync(candidate).isFile()) continue;
      fs.accessSync(candidate, fs.constants.X_OK);
      return fs.realpathSync(candidate);
    } catch { /* absent or not executable */ }
  }
  return undefined;
}

export function resolveExecutable(uri?: vscode.Uri, override?: string): string {
  const configured = configuredExecutable(uri, override);
  const found = findExecutable(configured, uri);
  if (found) return found;
  if (configured === 'recurloop' && !override?.trim() && managedExecutable) {
    return findExecutable(managedExecutable, uri) ?? configured;
  }
  return configured;
}

export function hexEncode(value: string): string {
  return Buffer.from(value, 'utf8').toString('hex');
}

export function hexDecode(value: string): string {
  if (!value) return '';
  try {
    return Buffer.from(value, 'hex').toString('utf8');
  } catch {
    return '';
  }
}

export function stripAnsi(value: string): string {
  // eslint-disable-next-line no-control-regex
  return value.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '');
}

export function rlString(value: string): string {
  return JSON.stringify(value);
}

export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

export function codePointToUtf16Map(source: string): number[] {
  const result = [0];
  let utf16 = 0;
  for (const character of source) {
    utf16 += character.length;
    result.push(utf16);
  }
  return result;
}

export function utf16OffsetToCodePoint(source: string, utf16Offset: number): number {
  if (utf16Offset <= 0) return 0;
  return Array.from(source.slice(0, utf16Offset)).length;
}

export function positionFromCodePoint(document: vscode.TextDocument, mapping: number[], offset: number): vscode.Position {
  const bounded = Math.max(0, Math.min(offset, mapping.length - 1));
  return document.positionAt(mapping[bounded]);
}

export function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export function likelyExecutableLine(source: string, requestedLine: number): number {
  const lines = source.split(/\r?\n/);
  let inBlockComment = false;
  const start = Math.max(1, Math.min(requestedLine, Math.max(1, lines.length)));
  for (let line = start; line <= lines.length; ++line) {
    let text = lines[line - 1] ?? '';
    if (inBlockComment) {
      const close = text.indexOf('*/');
      if (close < 0) continue;
      text = text.slice(close + 2);
      inBlockComment = false;
    }
    while (true) {
      const open = text.indexOf('/*');
      const slash = text.indexOf('//');
      if (slash >= 0 && (open < 0 || slash < open)) text = text.slice(0, slash);
      if (open < 0 || (slash >= 0 && slash < open)) break;
      const close = text.indexOf('*/', open + 2);
      if (close < 0) {
        text = text.slice(0, open);
        inBlockComment = true;
        break;
      }
      text = text.slice(0, open) + text.slice(close + 2);
    }
    const trimmed = text.trim();
    if (!trimmed || trimmed === '{' || trimmed === '}' || trimmed === '};') continue;
    return line;
  }
  return start;
}

export function libraryArguments(uri?: vscode.Uri): string[] {
  const libraries = vscode.workspace.getConfiguration('recurloop', uri).get<string[]>('terminal.libraries', ['shell', 'inferred']);
  return libraries.flatMap(name => ['--library', name]);
}

/** Resolve an editor-only image without changing the project's configured imports. */
export function resolveLibraryImage(uri: vscode.Uri, name: string): string {
  let executable = resolveExecutable(uri);
  if (!path.isAbsolute(executable)) {
    const found = (process.env.PATH ?? '').split(path.delimiter).map(directory => path.join(directory, executable)).find(candidate => fs.existsSync(candidate));
    if (found) executable = fs.realpathSync(found);
  }
  const prefix = path.dirname(path.dirname(executable));
  const paths = [
    ...(process.env.RECURLOOP_LIBRARY_PATH ?? '').split(path.delimiter).filter(Boolean),
    path.join(prefix, 'libraries'), path.join(prefix, 'share/recurloop/libraries'),
    path.join(workspaceRoot(uri), 'libraries'), '/usr/local/share/recurloop/libraries', '/usr/share/recurloop/libraries'
  ];
  for (const directory of paths) {
    const image = path.join(directory, `${name}.rli`);
    if (fs.existsSync(image)) return image;
  }
  throw new Error(`Editor analysis requires ${name}.rli; build/install libraries or set RECURLOOP_LIBRARY_PATH.`);
}
