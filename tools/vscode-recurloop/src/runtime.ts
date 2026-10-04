import { ChildProcessWithoutNullStreams, spawn } from 'child_process';
import * as fs from 'fs';
import * as net from 'net';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { hexEncode, libraryArguments, resolveExecutable, workspaceRoot } from './util';

function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

class WorkspaceRuntime implements vscode.Disposable {
  private process?: ChildProcessWithoutNullStreams;
  private socketPath?: string;
  private starting?: Promise<void>;
  private stderr = '';
  private disposed = false;
  private readonly executions = new Set<Promise<string>>();

  constructor(private readonly output: vscode.OutputChannel) {}

  public async inspect(document: vscode.TextDocument, trace = true): Promise<string> {
    await this.ensureStarted(document.uri);
    const socketPath = this.socketPath;
    if (!socketPath) throw new Error('RecurLoop analysis runtime did not create a socket');

    const contextual = fs.existsSync(projectFile(document.uri));
    const command = `${contextual ? (trace ? ':trace' : ':inspect') : (trace ? ':trace-file' : ':inspect-file')}\t${hexEncode(document.uri.fsPath)}\t${hexEncode(document.getText())}`;
    const timeout = vscode.workspace.getConfiguration('recurloop', document.uri).get('analysis.timeoutMs', 5000) as number;
    return this.request(socketPath, command, timeout);
  }

  public async restart(uri?: vscode.Uri): Promise<void> {
    if (this.starting) await this.starting.catch(() => undefined);
    await Promise.allSettled([...this.executions]);
    this.stop();
    if (uri) await this.ensureStarted(uri);
  }

  public info(uri?: vscode.Uri): string {
    const executable = resolveExecutable(uri);
    const state = this.process && !this.process.killed ? `running pid=${this.process.pid}` : 'stopped';
    return `executable=${executable}\nruntime=${state}\nsocket=${this.socketPath ?? '-'}${this.stderr ? `\nlast stderr=${this.stderr.trim()}` : ''}`;
  }

  public async execute(uri: vscode.Uri, commands: string[]): Promise<string> {
    await this.ensureStarted(uri);
    const request = this.request(this.socketPath!, commands, 120000);
    this.executions.add(request);
    try { return await request; } finally { this.executions.delete(request); }
  }

  public async reload(uri: vscode.Uri): Promise<void> {
    await this.ensureStarted(uri);
    await Promise.allSettled([...this.executions]);
    const entry = projectFile(uri);
    const commands = [':baseline', ':cache'];
    if (fs.existsSync(entry)) commands.push(`:load-file\t${entry}`);
    commands.push(':publish');
    await this.execute(uri, commands);
  }

  public async terminalOptions(uri: vscode.Uri): Promise<vscode.TerminalOptions> {
    await this.ensureStarted(uri);
    return { name: 'RecurLoop', cwd: workspaceRoot(uri), shellPath: resolveExecutable(uri),
      shellArgs: ['--connect', this.socketPath!], env: { NO_COLOR: '1' } };
  }

  private async ensureStarted(uri: vscode.Uri): Promise<void> {
    if (this.disposed) throw new Error('RecurLoop runtime is disposed');
    if (this.starting) return this.starting;
    if (this.process && !this.process.killed && this.socketPath && fs.existsSync(this.socketPath)) return;
    this.starting = this.start(uri).finally(() => { this.starting = undefined; });
    return this.starting;
  }

  private async start(uri: vscode.Uri): Promise<void> {
    this.stop();
    const executable = resolveExecutable(uri);
    const root = workspaceRoot(uri);
    const suffix = `${process.pid}-${Math.random().toString(16).slice(2, 8)}`;
    const socketPath = path.join(os.tmpdir(), `rl-vscode-${suffix}.sock`);
    try { fs.unlinkSync(socketPath); } catch { /* absent */ }

    const project = projectFile(uri);
    const args = [...libraryArguments(uri), '--project-cache',
      path.join(root, '.cache', 'recurloop-vscode'), '--serve', '--unix', socketPath, '--no-stdio'];
    this.output.appendLine(`[analysis] starting ${executable} --serve --unix ${socketPath} --no-stdio`);
    const child = spawn(executable, args, {
      cwd: root,
      env: { ...process.env, NO_COLOR: '1', RECURLOOP_PROJECT_ROOT: root },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    this.process = child;
    this.socketPath = socketPath;
    this.stderr = '';

    child.stdout.on('data', chunk => {
      const text = chunk.toString();
      if (text.trim()) this.output.append(`[analysis stdout] ${text}`);
    });
    child.stderr.on('data', chunk => {
      const text = chunk.toString();
      this.stderr = (this.stderr + text).slice(-8000);
      this.output.append(`[analysis stderr] ${text}`);
    });
    child.on('exit', (code, signal) => {
      this.output.appendLine(`[analysis] runtime exited code=${code ?? '-'} signal=${signal ?? '-'}`);
      if (this.process === child) this.process = undefined;
    });
    child.on('error', error => {
      this.stderr = error.message;
      this.output.appendLine(`[analysis] failed to start: ${error.message}`);
    });

    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      if (fs.existsSync(socketPath)) {
        if (fs.existsSync(project)) {
          try {
            await this.request(socketPath, [':baseline', ':cache', `:load-file\t${project}`, ':publish'], 120000);
          } catch (error) { this.stop(); throw error; }
        }
        return;
      }
      if (child.exitCode !== null) break;
      await delay(25);
    }
    this.stop();
    const details = this.stderr.trim();
    throw new Error(`Cannot start RecurLoop analysis runtime from '${executable}'.${details ? ` ${details}` : ''}`);
  }

  private request(socketPath: string, command: string | string[], timeoutMs: number): Promise<string> {
    return new Promise((resolve, reject) => {
      const socket = net.createConnection(socketPath);
      let buffer = '';
      let ready = false;
      const commands = Array.isArray(command) ? [...command] : [command];
      let result = '';
      const sendNext = () => socket.write(commands.shift()! + '\n');
      let settled = false;
      const timer = setTimeout(() => finish(new Error(`RecurLoop analysis request timed out after ${timeoutMs} ms`)), timeoutMs);

      const finish = (error?: Error, value = '') => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        socket.destroy();
        if (error) reject(error); else resolve(value);
      };

      socket.on('data', chunk => {
        buffer += chunk.toString('utf8');
        if (!ready) {
          if (buffer !== '> ' && !buffer.endsWith('> ')) return;
          ready = true;
          buffer = '';
          sendNext();
          return;
        }
        if (buffer.endsWith('> ')) {
          const reply = buffer.slice(0, -2);
          if (/^status=[1-9][0-9]*$/m.test(reply)) { finish(new Error(reply.trim())); return; }
          result += reply;
          buffer = '';
          if (commands.length) sendNext(); else finish(undefined, result);
        }
      });
      socket.on('error', error => finish(error));
      socket.on('end', () => {
        if (!settled) finish(new Error('RecurLoop analysis runtime closed the socket before replying'));
      });
    });
  }

  private stop(): void {
    const child = this.process;
    this.process = undefined;
    if (child && !child.killed) child.kill('SIGTERM');
    if (this.socketPath) {
      try { fs.unlinkSync(this.socketPath); } catch { /* absent or already removed */ }
    }
    this.socketPath = undefined;
  }

  public dispose(): void {
    this.disposed = true;
    this.stop();
  }
}

export function projectFile(uri: vscode.Uri): string {
  const name = vscode.workspace.getConfiguration('recurloop', uri).get('projectFile', 'recurloop.project.rl');
  return path.resolve(workspaceRoot(uri), name);
}

/** Each workspace owns a separate published language environment. */
export class RecurLoopRuntime implements vscode.Disposable {
  private readonly workspaces = new Map<string, WorkspaceRuntime>();
  constructor(private readonly output: vscode.OutputChannel) {}
  private runtime(uri: vscode.Uri): WorkspaceRuntime {
    const key = workspaceRoot(uri);
    let runtime = this.workspaces.get(key);
    if (!runtime) { runtime = new WorkspaceRuntime(this.output); this.workspaces.set(key, runtime); }
    return runtime;
  }
  inspect(document: vscode.TextDocument, trace = true): Promise<string> { return this.runtime(document.uri).inspect(document, trace); }
  execute(uri: vscode.Uri, commands: string[]): Promise<string> { return this.runtime(uri).execute(uri, commands); }
  terminalOptions(uri: vscode.Uri): Promise<vscode.TerminalOptions> { return this.runtime(uri).terminalOptions(uri); }
  reload(uri: vscode.Uri): Promise<void> { return this.runtime(uri).reload(uri); }
  async restart(uri?: vscode.Uri): Promise<void> {
    if (uri) await this.runtime(uri).restart(uri);
    else { for (const runtime of this.workspaces.values()) runtime.dispose(); this.workspaces.clear(); }
  }
  info(uri?: vscode.Uri): string { return uri ? this.runtime(uri).info(uri) : 'Select a workspace to inspect its runtime.'; }
  dispose(): void { for (const runtime of this.workspaces.values()) runtime.dispose(); this.workspaces.clear(); }
}
